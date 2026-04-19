import 'dart:typed_data';

import '../bit_reader.dart';
import 'metadata_block.dart';

/// Decoded FLAC STREAMINFO metadata block.
///
/// The STREAMINFO block contains essential information about the audio stream
/// and must be the first metadata block in every FLAC file.
class StreamInfoBlock extends MetadataBlock {
  /// Minimum block size (in samples) used in the stream.
  final int minBlockSize;

  /// Maximum block size (in samples) used in the stream.
  ///
  /// If equal to [minBlockSize], the stream is fixed-blocksize.
  final int maxBlockSize;

  /// Minimum frame size in bytes (0 if unknown).
  final int minFrameSize;

  /// Maximum frame size in bytes (0 if unknown).
  final int maxFrameSize;

  /// Audio sample rate in Hz (1–655350).
  final int sampleRate;

  /// Number of audio channels (1–8).
  final int channels;

  /// Bits per sample (4–32).
  final int bitsPerSample;

  /// Total number of inter-channel samples in the stream.
  ///
  /// May be 0 if the total number is unknown.
  final int totalSamples;

  /// MD5 signature of the unencoded audio data.
  ///
  /// All 16 bytes are zero if the signature was not calculated.
  final Uint8List md5;

  const StreamInfoBlock({
    required super.isLast,
    required super.length,
    required this.minBlockSize,
    required this.maxBlockSize,
    required this.minFrameSize,
    required this.maxFrameSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.totalSamples,
    required this.md5,
  }) : super(blockType: BlockType.streamInfo);

  /// Duration of the stream, or [Duration.zero] if [totalSamples] is 0.
  Duration get duration => totalSamples == 0 || sampleRate == 0
      ? Duration.zero
      : Duration(
          microseconds: (totalSamples * 1000000 ~/ sampleRate),
        );

  /// Parses a [StreamInfoBlock] from its raw [data] bytes.
  ///
  /// [data] must be exactly 34 bytes.
  static StreamInfoBlock parse(bool isLast, int length, Uint8List data) {
    if (data.length < 34) {
      throw FormatException(
          'STREAMINFO block too short: ${data.length} bytes (expected 34).');
    }
    final r = BitReader(data);
    final minBlockSize = r.readBits(16);
    final maxBlockSize = r.readBits(16);
    final minFrameSize = r.readBits(24);
    final maxFrameSize = r.readBits(24);
    final sampleRate = r.readBits(20);
    final channels = r.readBits(3) + 1;
    final bitsPerSample = r.readBits(5) + 1;

    // Total samples is a 36-bit value split across bytes 13–17.
    final totalSamplesHi = r.readBits(4);
    final totalSamplesLo = r.readBits(32);
    final totalSamples = (totalSamplesHi * 0x100000000) + totalSamplesLo;

    // MD5 is the final 16 bytes.
    final md5 = r.readBytes(16);

    return StreamInfoBlock(
      isLast: isLast,
      length: length,
      minBlockSize: minBlockSize,
      maxBlockSize: maxBlockSize,
      minFrameSize: minFrameSize,
      maxFrameSize: maxFrameSize,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      totalSamples: totalSamples,
      md5: md5,
    );
  }

  /// Returns a hex string representation of the MD5 signature.
  String get md5Hex =>
      md5.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  @override
  String toString() => 'StreamInfoBlock('
      'sampleRate=$sampleRate, '
      'channels=$channels, '
      'bitsPerSample=$bitsPerSample, '
      'totalSamples=$totalSamples, '
      'minBlockSize=$minBlockSize, '
      'maxBlockSize=$maxBlockSize'
      ')';
}
