import 'dart:async';
import 'dart:typed_data';

import 'frame/frame.dart';
import 'metadata/metadata_block.dart';
import 'metadata/stream_info.dart';
import 'pcm_output.dart';

/// A push-based FLAC decoder.
///
/// Consumers feed incoming bytes via [addBytes] as they arrive (e.g. from a
/// socket or a chunked HTTP response), and receive parsed metadata blocks
/// and decoded audio frames through the [metadata] and [frames] streams.
///
/// This decoder does not require the entire file to be in memory: it
/// maintains a rolling buffer and discards bytes once they have been
/// consumed. It also tolerates a leading ID3v2 tag.
///
/// Typical usage:
/// ```dart
/// final decoder = StreamingFlacDecoder();
/// decoder.frames.listen(playFrame);
/// await decoder.onStreamInfo;  // wait for sample rate etc.
/// await for (final chunk in socket) {
///   decoder.addBytes(chunk);
/// }
/// decoder.close();
/// ```
class StreamingFlacDecoder {
  final _metadataCtrl = StreamController<MetadataBlock>.broadcast();
  final _framesCtrl = StreamController<FlacFrame>.broadcast();
  final _streamInfoCompleter = Completer<StreamInfoBlock>();

  /// Emits each metadata block as it becomes available.
  Stream<MetadataBlock> get metadata => _metadataCtrl.stream;

  /// Emits each decoded audio frame as it becomes available.
  Stream<FlacFrame> get frames => _framesCtrl.stream;

  /// Resolves with the STREAMINFO block once it has been parsed.
  Future<StreamInfoBlock> get onStreamInfo => _streamInfoCompleter.future;

  /// Stream of interleaved little-endian signed PCM byte chunks, one per
  /// decoded frame — the shape most low-level audio sinks expect.
  ///
  /// [outputBitsPerSample] defaults to the stream's native bit depth
  /// (rounded up to 8/16/24/32). Pass an explicit value to force a
  /// specific output width (e.g. 16 for a 16-bit-only player).
  Stream<Uint8List> pcmStream({int? outputBitsPerSample}) {
    return frames.map((f) => frameToInterleavedPcm(
        f, outputBitsPerSample ?? f.header.bitsPerSample));
  }

  _State _state = _State.awaitingMarker;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  Uint8List _buffer = Uint8List(0);
  int _pos = 0;
  bool _closed = false;

  // Set once we've parsed STREAMINFO – lets us size a safe read window for
  // frames without scanning for the next sync code.
  int _maxFrameSize = 0;
  int _sampleRate = 0;
  int _bitsPerSample = 0;

  // Pending block header fields between _State.awaitingBlockBody transitions.
  late int _pendingBlockType;
  late bool _pendingBlockIsLast;
  late int _pendingBlockLength;

  /// Appends [chunk] to the internal buffer and advances the state machine
  /// as far as the buffered bytes allow.
  ///
  /// Throws [StateError] if [close] has already been called.
  void addBytes(Uint8List chunk) {
    if (_closed) {
      throw StateError('addBytes called after close.');
    }
    _builder.add(chunk);
    _flushBuilder();
    _tryAdvance();
  }

  /// Signals that no more bytes will be fed to the decoder. Flushes any
  /// remaining buffered bytes (interpreting them as the final frame), then
  /// closes the output streams.
  void close() {
    if (_closed) return;
    _closed = true;
    _flushBuilder();
    try {
      _tryAdvance(forceFinalFrame: true);
    } catch (e, st) {
      _metadataCtrl.addError(e, st);
      _framesCtrl.addError(e, st);
    }
    if (!_streamInfoCompleter.isCompleted) {
      _streamInfoCompleter.completeError(
          FormatException('Stream ended before STREAMINFO was parsed.'));
    }
    _metadataCtrl.close();
    _framesCtrl.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _flushBuilder() {
    if (_builder.isEmpty) return;
    final incoming = _builder.takeBytes();
    final tail = _buffer.length - _pos;
    if (tail == 0) {
      _buffer = incoming;
    } else {
      // Compact: drop the already-consumed prefix while appending.
      final merged = Uint8List(tail + incoming.length);
      merged.setRange(0, tail, _buffer, _pos);
      merged.setRange(tail, merged.length, incoming);
      _buffer = merged;
    }
    _pos = 0;
  }

  int get _available => _buffer.length - _pos;

  void _tryAdvance({bool forceFinalFrame = false}) {
    while (true) {
      switch (_state) {
        case _State.awaitingMarker:
          if (!_tryParseMarker()) return;
        case _State.awaitingBlockHeader:
          if (!_tryParseBlockHeader()) return;
        case _State.awaitingBlockBody:
          if (!_tryParseBlockBody()) return;
        case _State.parsingFrames:
          if (!_tryParseFrame(forceFinalFrame: forceFinalFrame)) return;
        case _State.done:
          return;
      }
    }
  }

  bool _tryParseMarker() {
    if (_available < 4) return false;
    // ID3v2 tag skip.
    if (_buffer[_pos] == 0x49 &&
        _buffer[_pos + 1] == 0x44 &&
        _buffer[_pos + 2] == 0x33) {
      if (_available < 10) return false;
      final flags = _buffer[_pos + 5];
      final size = ((_buffer[_pos + 6] & 0x7F) << 21) |
          ((_buffer[_pos + 7] & 0x7F) << 14) |
          ((_buffer[_pos + 8] & 0x7F) << 7) |
          (_buffer[_pos + 9] & 0x7F);
      final skip = 10 + size + ((flags & 0x10) != 0 ? 10 : 0);
      if (_available < skip + 4) return false;
      _pos += skip;
    }
    if (_buffer[_pos] != 0x66 ||
        _buffer[_pos + 1] != 0x4C ||
        _buffer[_pos + 2] != 0x61 ||
        _buffer[_pos + 3] != 0x43) {
      throw FormatException('Missing FLAC stream marker "fLaC".');
    }
    _pos += 4;
    _state = _State.awaitingBlockHeader;
    return true;
  }

  bool _tryParseBlockHeader() {
    if (_available < 4) return false;
    final headerByte = _buffer[_pos];
    _pendingBlockIsLast = (headerByte & 0x80) != 0;
    _pendingBlockType = headerByte & 0x7F;
    _pendingBlockLength = (_buffer[_pos + 1] << 16) |
        (_buffer[_pos + 2] << 8) |
        _buffer[_pos + 3];
    _pos += 4;
    _state = _State.awaitingBlockBody;
    return true;
  }

  bool _tryParseBlockBody() {
    if (_available < _pendingBlockLength) return false;
    final data =
        Uint8List.sublistView(_buffer, _pos, _pos + _pendingBlockLength);
    final block = parseMetadataBlock(
        _pendingBlockType, _pendingBlockIsLast, _pendingBlockLength, data);
    _metadataCtrl.add(block);
    if (block is StreamInfoBlock) {
      _maxFrameSize = block.maxFrameSize;
      _sampleRate = block.sampleRate;
      _bitsPerSample = block.bitsPerSample;
      if (!_streamInfoCompleter.isCompleted) {
        _streamInfoCompleter.complete(block);
      }
    }
    _pos += _pendingBlockLength;
    _state =
        _pendingBlockIsLast ? _State.parsingFrames : _State.awaitingBlockHeader;
    return true;
  }

  bool _tryParseFrame({required bool forceFinalFrame}) {
    if (_available < 2) {
      if (forceFinalFrame) _state = _State.done;
      return false;
    }
    // Validate frame sync.
    if (_buffer[_pos] != 0xFF || (_buffer[_pos + 1] & 0xFC) != 0xF8) {
      // Either truncated leading zeros / padding at EOF, or corruption.
      _state = _State.done;
      return false;
    }

    // We need the whole frame in the buffer before we can parse it.
    // STREAMINFO.maxFrameSize is the authoritative upper bound when known;
    // otherwise fall back to scanning for the next frame-sync pair.
    int? frameBudget;
    if (_maxFrameSize > 0) {
      frameBudget = _maxFrameSize;
    } else {
      final next = _scanForNextSync(_pos + 2);
      if (next >= 0) {
        frameBudget = next - _pos + 2; // include footer CRC-16
      }
    }

    if (frameBudget != null && _available < frameBudget && !forceFinalFrame) {
      return false;
    }

    // Spin up a short-lived FrameParser over a slice covering this frame.
    // We need a buffer whose byte positions line up with what parseFrame
    // expects, so hand it the live _buffer and the absolute _pos.
    final parser = FrameParser(
      data: _buffer,
      sampleRateFromStreamInfo: _sampleRate,
      bitsPerSampleFromStreamInfo: _bitsPerSample,
    );
    try {
      final (frame, nextOffset) = parser.parseFrame(_pos);
      _framesCtrl.add(frame);
      _pos = nextOffset;
      return true;
    } on StateError {
      // Ran off the end of the buffer – need more bytes.
      return false;
    }
  }

  int _scanForNextSync(int from) {
    for (var i = from; i + 1 < _buffer.length; i++) {
      if (_buffer[i] == 0xFF && (_buffer[i + 1] & 0xFC) == 0xF8) return i;
    }
    return -1;
  }
}

enum _State {
  awaitingMarker,
  awaitingBlockHeader,
  awaitingBlockBody,
  parsingFrames,
  done,
}
