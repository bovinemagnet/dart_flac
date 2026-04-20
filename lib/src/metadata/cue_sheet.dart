import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'metadata_block.dart';

/// A single track in a [CueSheetBlock].
class CueSheetTrack {
  /// Track offset in samples from the beginning of the audio stream.
  final Int64 trackOffset;

  /// Track number (1–99 for CD-DA, 1–254 for others; 170 for lead-out).
  final int trackNumber;

  /// 12-byte International Standard Recording Code, or all spaces/zeroes.
  final String isrc;

  /// Whether the track is audio (false) or data (true).
  final bool isDataTrack;

  /// Whether the track has pre-emphasis.
  final bool hasPreEmphasis;

  /// Track index points.
  final List<CueSheetTrackIndex> indices;

  const CueSheetTrack({
    required this.trackOffset,
    required this.trackNumber,
    required this.isrc,
    required this.isDataTrack,
    required this.hasPreEmphasis,
    required this.indices,
  });

  @override
  String toString() => 'CueSheetTrack($trackNumber, offset=$trackOffset)';
}

/// An index point within a [CueSheetTrack].
class CueSheetTrackIndex {
  /// Sample offset of the index point relative to the track offset, in samples.
  final Int64 offset;

  /// Index number (0 or 1 for the first two index points, etc.).
  final int indexNumber;

  const CueSheetTrackIndex({
    required this.offset,
    required this.indexNumber,
  });
}

/// FLAC CUESHEET metadata block.
///
/// Stores a CD table of contents / cue sheet that allows FLAC files to act as
/// a lossless representation of a complete CD.
class CueSheetBlock extends MetadataBlock {
  /// Media catalog number (128 bytes, ASCII, padded with NULs).
  final String mediaCatalogNumber;

  /// Number of lead-in samples (for CD-DA this is ≥ 2 seconds worth).
  final Int64 leadInSamples;

  /// Whether the cue sheet corresponds to a CD.
  final bool isCD;

  /// The tracks in this cue sheet (including the mandatory lead-out track).
  final List<CueSheetTrack> tracks;

  const CueSheetBlock({
    required super.isLast,
    required super.length,
    required this.mediaCatalogNumber,
    required this.leadInSamples,
    required this.isCD,
    required this.tracks,
  }) : super(blockType: BlockType.cueSheet);

  /// Parses a [CueSheetBlock] from its raw [data] bytes.
  static CueSheetBlock parse(bool isLast, int length, Uint8List data) {
    var offset = 0;

    // Media catalog number: 128 ASCII bytes, NUL-terminated / padded.
    final mcnBytes = data.sublist(offset, offset + 128);
    final mcnEnd = mcnBytes.indexOf(0);
    final mcn = String.fromCharCodes(
        mcnEnd >= 0 ? mcnBytes.sublist(0, mcnEnd) : mcnBytes);
    offset += 128;

    // Lead-in samples (8 bytes BE).
    final leadInSamples = readUint64BE(data, offset);
    offset += 8;

    // Is-CD flag (1 bit), then 7+258*8 reserved bits.
    final isCD = (data[offset] & 0x80) != 0;
    offset += 259; // 1 flag byte + 258 reserved bytes

    // Track count.
    final trackCount = data[offset++];
    final tracks = <CueSheetTrack>[];
    for (var t = 0; t < trackCount; t++) {
      final trackOffset = readUint64BE(data, offset);
      offset += 8;
      final trackNumber = data[offset++];

      // ISRC: 12 bytes ASCII.
      final isrc = String.fromCharCodes(data.sublist(offset, offset + 12));
      offset += 12;

      final flags = data[offset++];
      final isData = (flags & 0x80) != 0;
      final preEmphasis = (flags & 0x40) != 0;
      offset += 13; // 13 reserved bytes

      final indexCount = data[offset++];
      final indices = <CueSheetTrackIndex>[];
      for (var i = 0; i < indexCount; i++) {
        final indexOffset = readUint64BE(data, offset);
        offset += 8;
        final indexNumber = data[offset++];
        offset += 3; // 3 reserved bytes
        indices.add(
            CueSheetTrackIndex(offset: indexOffset, indexNumber: indexNumber));
      }
      tracks.add(CueSheetTrack(
        trackOffset: trackOffset,
        trackNumber: trackNumber,
        isrc: isrc,
        isDataTrack: isData,
        hasPreEmphasis: preEmphasis,
        indices: indices,
      ));
    }

    return CueSheetBlock(
      isLast: isLast,
      length: length,
      mediaCatalogNumber: mcn,
      leadInSamples: leadInSamples,
      isCD: isCD,
      tracks: tracks,
    );
  }

  @override
  String toString() =>
      'CueSheetBlock(${tracks.length} tracks, isCD=$isCD, isLast=$isLast)';
}
