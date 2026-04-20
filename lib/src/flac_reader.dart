import 'dart:io';
import 'dart:typed_data';

import 'frame/frame.dart';
import 'md5_verifier.dart';
import 'pcm_output.dart';
import 'metadata/application.dart';
import 'metadata/cue_sheet.dart';
import 'metadata/metadata_block.dart';
import 'metadata/padding.dart';
import 'metadata/picture.dart';
import 'metadata/seek_table.dart';
import 'metadata/stream_info.dart';
import 'metadata/vorbis_comment.dart';

/// Result of verifying decoded PCM against the MD5 signature stored in
/// the STREAMINFO block.
enum Md5VerificationResult {
  /// The MD5 of the decoded samples matched the signature in STREAMINFO.
  match,

  /// The MD5 of the decoded samples did not match.
  mismatch,

  /// The STREAMINFO signature is all zeros – the encoder did not compute
  /// one, so verification is not possible.
  notComputed,
}

/// The magic 4-byte marker that starts every valid FLAC file.
const _flacMarker = [0x66, 0x4C, 0x61, 0x43]; // "fLaC"

/// High-level FLAC file reader.
///
/// Reads a FLAC file from disk (or from a [Uint8List] byte buffer), parses
/// its metadata blocks, and optionally decodes the audio frames.
///
/// ### Example – read metadata only:
/// ```dart
/// final reader = await FlacReader.fromFile('track.flac');
/// print(reader.streamInfo);
/// print(reader.vorbisComment?.title);
/// ```
///
/// ### Example – decode audio:
/// ```dart
/// final reader = await FlacReader.fromFile('track.flac');
/// final frames = reader.decodeFrames();
/// ```
class FlacReader {
  /// The raw bytes of the FLAC file.
  final Uint8List _data;

  /// All metadata blocks in the order they appear in the file.
  final List<MetadataBlock> metadataBlocks;

  /// The byte offset where the audio frame data begins.
  final int audioDataOffset;

  FlacReader._(this._data, this.metadataBlocks, this.audioDataOffset);

  // ---------------------------------------------------------------------------
  // Factory constructors
  // ---------------------------------------------------------------------------

  /// Creates a [FlacReader] from an in-memory [bytes] buffer.
  ///
  /// Throws [FormatException] if the data does not begin with the FLAC
  /// stream marker or the STREAMINFO block is missing.
  factory FlacReader.fromBytes(Uint8List bytes) {
    final markerStart = _skipLeadingTags(bytes);
    _validateMarker(bytes, markerStart);
    final (blocks, audioOffset) = _parseAllBlocks(bytes, markerStart + 4);
    _validateStreamInfo(blocks);
    return FlacReader._(bytes, blocks, audioOffset);
  }

  /// Reads [path] from disk and returns a [FlacReader] for it.
  ///
  /// Throws [FileSystemException] if the file cannot be read, or
  /// [FormatException] if the file is not a valid FLAC stream.
  static Future<FlacReader> fromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return FlacReader.fromBytes(bytes);
  }

  /// Synchronously reads [path] from disk and returns a [FlacReader] for it.
  static FlacReader fromFileSync(String path) {
    final bytes = File(path).readAsBytesSync();
    return FlacReader.fromBytes(bytes);
  }

  // ---------------------------------------------------------------------------
  // Metadata accessors
  // ---------------------------------------------------------------------------

  /// The mandatory STREAMINFO block.
  StreamInfoBlock get streamInfo =>
      metadataBlocks.whereType<StreamInfoBlock>().first;

  /// The VORBIS_COMMENT block, or `null` if not present.
  VorbisCommentBlock? get vorbisComment =>
      metadataBlocks.whereType<VorbisCommentBlock>().firstOrNull;

  /// All PICTURE blocks in the file.
  List<PictureBlock> get pictures =>
      metadataBlocks.whereType<PictureBlock>().toList();

  /// The SEEKTABLE block, or `null` if not present.
  SeekTableBlock? get seekTable =>
      metadataBlocks.whereType<SeekTableBlock>().firstOrNull;

  /// The CUESHEET block, or `null` if not present.
  CueSheetBlock? get cueSheet =>
      metadataBlocks.whereType<CueSheetBlock>().firstOrNull;

  /// All APPLICATION blocks in the file.
  List<ApplicationBlock> get applicationBlocks =>
      metadataBlocks.whereType<ApplicationBlock>().toList();

  /// All PADDING blocks in the file.
  List<PaddingBlock> get paddingBlocks =>
      metadataBlocks.whereType<PaddingBlock>().toList();

  // ---------------------------------------------------------------------------
  // Audio decoding
  // ---------------------------------------------------------------------------

  /// Decodes and returns all audio frames in the file.
  ///
  /// Each [FlacFrame] contains the decoded PCM samples for one block.
  /// Use [streamInfo] to obtain the sample rate, channel count, and bits
  /// per sample needed to interpret the samples.
  ///
  /// If [recoverFromCorruption] is true, frames that fail to parse (e.g.
  /// due to a CRC mismatch or truncated data) are skipped: the decoder
  /// scans forward for the next valid frame sync code and continues.
  /// [onCorruption] is invoked once per skipped frame with the byte
  /// offset at which the parse failed and the triggering error.
  List<FlacFrame> decodeFrames({
    bool recoverFromCorruption = false,
    void Function(int offset, Object error)? onCorruption,
  }) {
    final info = streamInfo;
    final parser = FrameParser(
      data: _data,
      sampleRateFromStreamInfo: info.sampleRate,
      bitsPerSampleFromStreamInfo: info.bitsPerSample,
    );
    if (recoverFromCorruption) {
      return parser.parseAllFramesTolerant(
        audioDataOffset,
        onError: onCorruption ?? (_, __) {},
      );
    }
    return parser.parseAllFrames(audioDataOffset);
  }

  /// Returns a lazy iterable of PCM byte chunks, one per decoded frame.
  ///
  /// Each chunk contains interleaved, little-endian, signed samples,
  /// ready to be fed to a PCM-accepting audio sink such as
  /// `flutter_sound`, `flutter_soloud`, or a PortAudio/SDL FFI wrapper.
  ///
  /// [outputBitsPerSample] defaults to the stream's native bit depth
  /// (rounded up to 8/16/24/32). Override it when your player expects
  /// a specific width — e.g. pass 16 to truncate a 24-bit source for a
  /// player that only accepts 16-bit PCM.
  Iterable<Uint8List> pcmChunks({int? outputBitsPerSample}) sync* {
    final bps = outputBitsPerSample ?? streamInfo.bitsPerSample;
    for (final frame in framesLazy()) {
      yield frameToInterleavedPcm(frame, bps);
    }
  }

  /// Returns a lazy iterable over the audio frames.
  ///
  /// Unlike [decodeFrames] — which decodes every frame before returning —
  /// this iterator decodes one frame per pull. Consumers can stop early
  /// (e.g. after enough samples for a playback buffer) and save the
  /// memory that would otherwise be spent on the tail of the stream.
  ///
  /// The encoded byte buffer is still held in memory; only the decoded
  /// PCM is streamed.
  Iterable<FlacFrame> framesLazy() sync* {
    final info = streamInfo;
    final parser = FrameParser(
      data: _data,
      sampleRateFromStreamInfo: info.sampleRate,
      bitsPerSampleFromStreamInfo: info.bitsPerSample,
    );
    var offset = audioDataOffset;
    while (offset + 2 <= _data.length) {
      if (_data[offset] != 0xFF || (_data[offset + 1] & 0xFC) != 0xF8) break;
      final (frame, nextOffset) = parser.parseFrame(offset);
      yield frame;
      offset = nextOffset;
    }
  }

  /// Verifies that re-decoding the audio produces PCM whose MD5 matches
  /// the signature stored in STREAMINFO.
  ///
  /// Returns [Md5VerificationResult.notComputed] if the encoder did not
  /// compute a signature (i.e. all 16 bytes are zero).
  Md5VerificationResult verifyMd5() {
    final info = streamInfo;
    if (info.md5.every((b) => b == 0)) {
      return Md5VerificationResult.notComputed;
    }
    final frames = decodeFrames();
    final computed = computePcmMd5(frames, info.bitsPerSample);
    for (var i = 0; i < 16; i++) {
      if (computed[i] != info.md5[i]) return Md5VerificationResult.mismatch;
    }
    return Md5VerificationResult.match;
  }

  /// Returns the byte offset of the frame that contains [sampleNumber].
  ///
  /// Uses the SEEKTABLE (if present and usable) to jump close to the target
  /// frame, then falls back to a linear scan through frame headers.
  ///
  /// Throws [RangeError] if [sampleNumber] is negative, or beyond the end
  /// of the stream when [StreamInfoBlock.totalSamples] is known.
  int byteOffsetForSample(int sampleNumber) {
    if (sampleNumber < 0) {
      throw RangeError.value(sampleNumber, 'sampleNumber', 'must be >= 0');
    }
    final info = streamInfo;
    if (info.totalSamples > 0 && sampleNumber >= info.totalSamples) {
      throw RangeError.value(
          sampleNumber, 'sampleNumber', 'beyond end of stream');
    }

    // Start from the best seek-table entry we can find, else the first frame.
    var scanOffset = audioDataOffset;
    var scanSample = 0;
    final table = seekTable;
    if (table != null) {
      for (final pt in table.seekPoints) {
        if (pt.isPlaceholder) continue;
        if (pt.sampleNumber <= sampleNumber &&
            pt.sampleNumber >= scanSample) {
          scanOffset = audioDataOffset + pt.streamOffset;
          scanSample = pt.sampleNumber;
        }
      }
    }

    // Walk frame headers forward until we reach the frame containing the
    // target sample.
    final parser = FrameParser(
      data: _data,
      sampleRateFromStreamInfo: info.sampleRate,
      bitsPerSampleFromStreamInfo: info.bitsPerSample,
    );
    final fixedBlockSize =
        info.minBlockSize == info.maxBlockSize ? info.maxBlockSize : 0;

    while (true) {
      if (scanOffset >= _data.length) {
        throw RangeError.value(
            sampleNumber, 'sampleNumber', 'beyond end of stream');
      }
      final (header, _, _) = parser.parseFrameHeader(scanOffset);
      final startSample = header.blockingStrategy ==
              BlockingStrategy.variableBlocksize
          ? header.number
          : header.number * (fixedBlockSize > 0
              ? fixedBlockSize
              : header.blockSize);
      final endSample = startSample + header.blockSize;
      if (sampleNumber < endSample) return scanOffset;
      // Advance past this frame's body by fully decoding the frame. A
      // header-only walk is not possible because subframes are bit-packed
      // with no length prefix.
      final (_, frameEnd) = parser.parseFrame(scanOffset);
      scanOffset = frameEnd;
      scanSample = endSample;
    }
  }

  /// Decodes all frames starting from the frame that contains [sampleNumber].
  ///
  /// Uses [byteOffsetForSample] to locate the starting frame.
  List<FlacFrame> decodeFramesFromSample(int sampleNumber) {
    final startOffset = byteOffsetForSample(sampleNumber);
    final info = streamInfo;
    final parser = FrameParser(
      data: _data,
      sampleRateFromStreamInfo: info.sampleRate,
      bitsPerSampleFromStreamInfo: info.bitsPerSample,
    );
    return parser.parseAllFrames(startOffset);
  }

  /// Decodes all audio frames and interleaves the channel samples into a
  /// single [Int32List].
  ///
  /// The layout is: `[ch0[0], ch1[0], ch0[1], ch1[1], ...]` for stereo.
  Int32List decodeInterleavedSamples() {
    final frames = decodeFrames();
    final info = streamInfo;
    final totalSamples = info.totalSamples > 0
        ? info.totalSamples * info.channels
        : frames.fold<int>(
            0, (sum, f) => sum + f.blockSize * f.channelCount);
    final output = Int32List(totalSamples);
    var out = 0;
    for (final frame in frames) {
      final channels = frame.channelCount;
      final blockSize = frame.blockSize;
      for (var s = 0; s < blockSize; s++) {
        for (var ch = 0; ch < channels; ch++) {
          output[out++] = frame.channelSamples[ch][s];
        }
      }
    }
    return output.sublist(0, out);
  }

  // ---------------------------------------------------------------------------
  // Validation helpers
  // ---------------------------------------------------------------------------

  static void _validateMarker(Uint8List bytes, int offset) {
    if (bytes.length < offset + 4) {
      throw FormatException('File is too short to be a FLAC stream.');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[offset + i] != _flacMarker[i]) {
        throw FormatException(
            'Missing FLAC stream marker "fLaC". '
            'Got: 0x${bytes[offset + i].toRadixString(16)} at byte ${offset + i}.');
      }
    }
  }

  /// Skips any leading ID3v2 tag and returns the offset of the byte that
  /// should start the `fLaC` marker. Returns 0 if no ID3v2 tag is present.
  ///
  /// ID3v2 header: 10 bytes, starts with ASCII "ID3". Bytes 6-9 encode
  /// the tag size as a 28-bit big-endian synchsafe integer (bit 7 of each
  /// byte is 0). If the footer-present flag (bit 4 of the flags byte) is
  /// set, an additional 10-byte footer follows the tag body.
  static int _skipLeadingTags(Uint8List bytes) {
    if (bytes.length < 10) return 0;
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) return 0;
    final flags = bytes[5];
    final size = ((bytes[6] & 0x7F) << 21) |
        ((bytes[7] & 0x7F) << 14) |
        ((bytes[8] & 0x7F) << 7) |
        (bytes[9] & 0x7F);
    final hasFooter = (flags & 0x10) != 0;
    return 10 + size + (hasFooter ? 10 : 0);
  }

  static void _validateStreamInfo(List<MetadataBlock> blocks) {
    if (blocks.isEmpty || blocks.first is! StreamInfoBlock) {
      throw FormatException(
          'FLAC stream must start with a STREAMINFO metadata block.');
    }
  }

  @override
  String toString() =>
      'FlacReader($streamInfo, audioDataOffset=$audioDataOffset)';
}

(List<MetadataBlock>, int) _parseAllBlocks(Uint8List data, int offset) {
  final blocks = <MetadataBlock>[];
  while (true) {
    if (offset + 4 > data.length) {
      throw FormatException(
          'Truncated metadata block header at offset $offset.');
    }
    final headerByte = data[offset];
    final isLast = (headerByte & 0x80) != 0;
    final type = headerByte & 0x7F;
    final length = (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
    offset += 4;

    if (offset + length > data.length) {
      throw FormatException(
          'Metadata block (type=$type) extends beyond end of data.');
    }

    final blockData = data.sublist(offset, offset + length);
    offset += length;

    final block = parseMetadataBlock(type, isLast, length, blockData);
    blocks.add(block);

    if (isLast) break;
  }
  return (blocks, offset);
}
