import 'dart:typed_data';

import '../bit_reader.dart';
import '../crc.dart';
import 'subframe.dart';

/// Channel assignment identifiers used in FLAC frame headers.
abstract final class ChannelAssignment {
  /// 1–8 independent audio channels (value 0–7 encodes channelCount - 1).
  static const int independent = 0; // values 0–7 represent channel count

  /// Left/side stereo: channel 0 is left, channel 1 is the difference
  /// (left − right).
  static const int leftSide = 8;

  /// Right/side stereo: channel 0 is the difference (left − right),
  /// channel 1 is right.
  static const int rightSide = 9;

  /// Mid/side stereo: channel 0 is mid ((left + right) >> 1),
  /// channel 1 is side (left − right).
  static const int midSide = 10;
}

/// The blocking strategy used in a FLAC frame.
enum BlockingStrategy {
  /// Every frame contains the same number of samples (fixed-blocksize stream).
  fixedBlocksize,

  /// Frames may have different numbers of samples (variable-blocksize stream).
  variableBlocksize,
}

/// The decoded header of a single FLAC audio frame.
class FrameHeader {
  /// Whether this stream uses fixed or variable blocking.
  final BlockingStrategy blockingStrategy;

  /// Number of inter-channel samples in this frame.
  final int blockSize;

  /// Audio sample rate in Hz.
  final int sampleRate;

  /// Channel assignment (see [ChannelAssignment]).
  final int channelAssignment;

  /// Number of channels encoded in this frame.
  final int channelCount;

  /// Bits per sample for this frame.
  final int bitsPerSample;

  /// For variable-blocksize streams: the sample number of the first sample
  /// in this frame.  For fixed-blocksize streams: the frame number.
  final int number;

  const FrameHeader({
    required this.blockingStrategy,
    required this.blockSize,
    required this.sampleRate,
    required this.channelAssignment,
    required this.channelCount,
    required this.bitsPerSample,
    required this.number,
  });

  @override
  String toString() => 'FrameHeader('
      'blockSize=$blockSize, '
      'sampleRate=$sampleRate, '
      'channels=$channelCount, '
      'bitsPerSample=$bitsPerSample'
      ')';
}

/// A fully decoded FLAC audio frame containing one or more channels.
class FlacFrame {
  /// The parsed frame header.
  final FrameHeader header;

  /// Decoded PCM samples, one [Int32List] per channel.
  ///
  /// Each list contains [header.blockSize] 32-bit signed samples.
  final List<Int32List> channelSamples;

  const FlacFrame({required this.header, required this.channelSamples});

  /// Number of audio channels.
  int get channelCount => channelSamples.length;

  /// Number of PCM samples per channel in this frame.
  int get blockSize => header.blockSize;
}

/// Parses FLAC audio frames from raw byte data.
///
/// Create an instance with stream-level parameters from the STREAMINFO block,
/// then call [parseFrame] or [parseAllFrames] to decode audio data.
class FrameParser {
  final Uint8List _data;
  final int _sampleRateFromStreamInfo;
  final int _bitsPerSampleFromStreamInfo;

  FrameParser({
    required Uint8List data,
    required int sampleRateFromStreamInfo,
    required int bitsPerSampleFromStreamInfo,
  })  : _data = data,
        _sampleRateFromStreamInfo = sampleRateFromStreamInfo,
        _bitsPerSampleFromStreamInfo = bitsPerSampleFromStreamInfo;

  /// Parses and returns the FLAC frame starting at [offset] in the buffer.
  ///
  /// Returns the decoded [FlacFrame] and the offset of the first byte
  /// after the frame.
  (FlacFrame, int) parseFrame(int offset) {
    final startOffset = offset;
    final r = BitReader.atOffset(_data, offset);

    // -----------------------------------------------------------------------
    // Frame header
    // -----------------------------------------------------------------------

    // Sync code: 14 bits = 0x3FFE.
    final sync = r.readBits(14);
    if (sync != 0x3FFE) {
      throw FormatException(
          'Invalid FLAC frame sync code 0x${sync.toRadixString(16)} '
          'at offset $offset.');
    }

    r.readBit(); // reserved, must be 0
    final blockingStrategyBit = r.readBit();
    final blockingStrategy = blockingStrategyBit == 1
        ? BlockingStrategy.variableBlocksize
        : BlockingStrategy.fixedBlocksize;

    final blockSizeBits = r.readBits(4);
    final sampleRateBits = r.readBits(4);
    final channelAssignmentBits = r.readBits(4);
    final sampleSizeBits = r.readBits(3);
    r.readBit(); // reserved, must be 0

    // UTF-8 coded frame / sample number.
    final number = r.readUtf8CodedNumber();

    // Optional block-size field.
    final int blockSize;
    switch (blockSizeBits) {
      case 0x1:
        blockSize = 192;
      case 0x2:
        blockSize = 576;
      case 0x3:
        blockSize = 1152;
      case 0x4:
        blockSize = 2304;
      case 0x5:
        blockSize = 4608;
      case 0x6:
        // Get 8-bit (blockSize - 1) from end-of-header.
        blockSize = r.readBits(8) + 1;
      case 0x7:
        // Get 16-bit (blockSize - 1) from end-of-header.
        blockSize = r.readBits(16) + 1;
      default:
        if (blockSizeBits >= 0x8) {
          blockSize = 256 << (blockSizeBits - 0x8);
        } else {
          throw FormatException('Reserved block size bits: $blockSizeBits');
        }
    }

    // Optional sample-rate field.
    final int sampleRate;
    switch (sampleRateBits) {
      case 0x0:
        sampleRate = _sampleRateFromStreamInfo;
      case 0x1:
        sampleRate = 88200;
      case 0x2:
        sampleRate = 176400;
      case 0x3:
        sampleRate = 192000;
      case 0x4:
        sampleRate = 8000;
      case 0x5:
        sampleRate = 16000;
      case 0x6:
        sampleRate = 22050;
      case 0x7:
        sampleRate = 24000;
      case 0x8:
        sampleRate = 32000;
      case 0x9:
        sampleRate = 44100;
      case 0xA:
        sampleRate = 48000;
      case 0xB:
        sampleRate = 96000;
      case 0xC:
        sampleRate = r.readBits(8) * 1000;
      case 0xD:
        sampleRate = r.readBits(16);
      case 0xE:
        sampleRate = r.readBits(16) * 10;
      default:
        throw FormatException(
            'Invalid sample rate bits 0xF in frame header.');
    }

    // Channel assignment.
    final int channelCount;
    final int channelAssignment;
    if (channelAssignmentBits <= 7) {
      channelCount = channelAssignmentBits + 1;
      channelAssignment = ChannelAssignment.independent;
    } else if (channelAssignmentBits == 8) {
      channelCount = 2;
      channelAssignment = ChannelAssignment.leftSide;
    } else if (channelAssignmentBits == 9) {
      channelCount = 2;
      channelAssignment = ChannelAssignment.rightSide;
    } else if (channelAssignmentBits == 10) {
      channelCount = 2;
      channelAssignment = ChannelAssignment.midSide;
    } else {
      throw FormatException(
          'Reserved channel assignment: $channelAssignmentBits');
    }

    // Bits per sample.
    final int bitsPerSample;
    switch (sampleSizeBits) {
      case 0x0:
        bitsPerSample = _bitsPerSampleFromStreamInfo;
      case 0x1:
        bitsPerSample = 8;
      case 0x2:
        bitsPerSample = 12;
      case 0x4:
        bitsPerSample = 16;
      case 0x5:
        bitsPerSample = 20;
      case 0x6:
        bitsPerSample = 24;
      case 0x7:
        bitsPerSample = 32;
      default:
        throw FormatException('Reserved sample size bits: $sampleSizeBits');
    }

    // CRC-8 covers all frame header bytes up to (but not including) the CRC.
    final headerEndOffset = r.bytePosition; // absolute offset in _data
    final headerCrc8 = r.readByte();
    final computedCrc8 =
        crc8(_data.sublist(startOffset, headerEndOffset));
    if (headerCrc8 != computedCrc8) {
      throw FormatException(
          'Frame header CRC-8 mismatch at offset $startOffset: '
          'expected 0x${computedCrc8.toRadixString(16)}, '
          'got 0x${headerCrc8.toRadixString(16)}.');
    }

    final header = FrameHeader(
      blockingStrategy: blockingStrategy,
      blockSize: blockSize,
      sampleRate: sampleRate,
      channelAssignment: channelAssignment,
      channelCount: channelCount,
      bitsPerSample: bitsPerSample,
      number: number,
    );

    // -----------------------------------------------------------------------
    // Subframes (one per channel)
    // -----------------------------------------------------------------------
    final rawSamples = <Int32List>[];
    for (var ch = 0; ch < channelCount; ch++) {
      // Side channels in stereo-coded frames need 1 extra bit.
      final extraBit = _sideChannelExtraBit(channelAssignment, ch);
      final samples =
          SubframeDecoder.decode(r, blockSize, bitsPerSample + extraBit);
      rawSamples.add(samples);
    }

    // Byte-align before reading the footer CRC.
    r.skipToByteBoundary();

    // CRC-16 covers the entire frame from sync code to the padding zero bits.
    final frameEndOffset = r.bytePosition; // absolute offset in _data
    final frameCrc16Hi = r.readByte();
    final frameCrc16Lo = r.readByte();
    final storedCrc16 = (frameCrc16Hi << 8) | frameCrc16Lo;
    final computedCrc16 =
        crc16(_data.sublist(startOffset, frameEndOffset));
    if (storedCrc16 != computedCrc16) {
      throw FormatException(
          'Frame CRC-16 mismatch at offset $startOffset: '
          'expected 0x${computedCrc16.toRadixString(16)}, '
          'got 0x${storedCrc16.toRadixString(16)}.');
    }

    final endOffset = r.bytePosition;

    // -----------------------------------------------------------------------
    // Channel decorrelation
    // -----------------------------------------------------------------------
    final channelSamples =
        _decorrelate(channelAssignment, rawSamples, bitsPerSample);

    return (FlacFrame(header: header, channelSamples: channelSamples), endOffset);
  }

  /// Returns 1 if [channel] is the side channel in a stereo-coded frame that
  /// requires one extra bit of precision.
  int _sideChannelExtraBit(int channelAssignment, int channel) {
    if (channelAssignment == ChannelAssignment.leftSide && channel == 1) {
      return 1;
    }
    if (channelAssignment == ChannelAssignment.rightSide && channel == 0) {
      return 1;
    }
    if (channelAssignment == ChannelAssignment.midSide && channel == 1) {
      return 1;
    }
    return 0;
  }

  /// Applies joint-stereo decorrelation and returns the reconstructed PCM
  /// channel data.
  List<Int32List> _decorrelate(
      int channelAssignment, List<Int32List> raw, int bitsPerSample) {
    if (channelAssignment == ChannelAssignment.independent) {
      return raw;
    }

    final left = Int32List(raw[0].length);
    final right = Int32List(raw[0].length);

    switch (channelAssignment) {
      case ChannelAssignment.leftSide:
        for (var i = 0; i < raw[0].length; i++) {
          left[i] = raw[0][i];
          right[i] = raw[0][i] - raw[1][i];
        }
      case ChannelAssignment.rightSide:
        for (var i = 0; i < raw[0].length; i++) {
          left[i] = raw[0][i] + raw[1][i];
          right[i] = raw[1][i];
        }
      case ChannelAssignment.midSide:
        for (var i = 0; i < raw[0].length; i++) {
          final mid = raw[0][i];
          final side = raw[1][i];
          // Restore LSB lost by the mid = (left+right)>>1 operation.
          final m = (mid << 1) | (side & 1);
          left[i] = (m + side) >> 1;
          right[i] = (m - side) >> 1;
        }
    }

    return [left, right];
  }

  /// Parses all audio frames starting at [audioDataOffset] in the buffer.
  ///
  /// Stops when either the end of the buffer is reached or no valid sync code
  /// is found.
  List<FlacFrame> parseAllFrames(int audioDataOffset) {
    final frames = <FlacFrame>[];
    var offset = audioDataOffset;
    while (offset + 2 <= _data.length) {
      // Quick sync check: 0xFF followed by 0xF8-0xFF.
      if (_data[offset] != 0xFF || (_data[offset + 1] & 0xFC) != 0xF8) {
        break;
      }
      final (frame, nextOffset) = parseFrame(offset);
      frames.add(frame);
      offset = nextOffset;
    }
    return frames;
  }
}
