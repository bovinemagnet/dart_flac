import 'dart:typed_data';

import 'metadata_block.dart';

/// A single seek point in a FLAC [SeekTableBlock].
class SeekPoint {
  /// Sample number of the first sample of the target frame, or
  /// [SeekPoint.placeholderSampleNumber] if this is a placeholder point.
  final int sampleNumber;

  /// Byte offset from the start of the first frame to the target frame.
  final int streamOffset;

  /// Number of samples in the target frame.
  final int frameSamples;

  /// Sentinel value used to mark a placeholder seek point.
  static const int placeholderSampleNumber = 0xFFFFFFFFFFFFFFFF;

  const SeekPoint({
    required this.sampleNumber,
    required this.streamOffset,
    required this.frameSamples,
  });

  /// Whether this seek point is a placeholder.
  bool get isPlaceholder => sampleNumber == placeholderSampleNumber;

  @override
  String toString() => isPlaceholder
      ? 'SeekPoint(placeholder)'
      : 'SeekPoint(sample=$sampleNumber, offset=$streamOffset, '
          'frameSamples=$frameSamples)';
}

/// FLAC SEEKTABLE metadata block.
///
/// Contains an ordered list of seek points that allow efficient random access
/// into the audio stream.
class SeekTableBlock extends MetadataBlock {
  /// The seek points in ascending order of [SeekPoint.sampleNumber].
  final List<SeekPoint> seekPoints;

  const SeekTableBlock({
    required super.isLast,
    required super.length,
    required this.seekPoints,
  }) : super(blockType: BlockType.seekTable);

  /// Parses a [SeekTableBlock] from its raw [data] bytes.
  ///
  /// The block length must be a multiple of 18 bytes (each seek point is
  /// exactly 18 bytes).
  static SeekTableBlock parse(bool isLast, int length, Uint8List data) {
    if (data.length % 18 != 0) {
      throw FormatException(
          'SEEKTABLE block length (${data.length}) is not a multiple of 18.');
    }
    final count = data.length ~/ 18;
    final points = <SeekPoint>[];
    for (var i = 0; i < count; i++) {
      final offset = i * 18;
      final sampleNumber = readUint64BE(data, offset);
      final streamOffset = readUint64BE(data, offset + 8);
      final frameSamples = (data[offset + 16] << 8) | data[offset + 17];
      points.add(SeekPoint(
        sampleNumber: sampleNumber,
        streamOffset: streamOffset,
        frameSamples: frameSamples,
      ));
    }
    return SeekTableBlock(isLast: isLast, length: length, seekPoints: points);
  }

  @override
  String toString() =>
      'SeekTableBlock(${seekPoints.length} points, isLast=$isLast)';
}
