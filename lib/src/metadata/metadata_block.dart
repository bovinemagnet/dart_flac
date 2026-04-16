import 'dart:typed_data';

/// Block type identifiers for FLAC metadata blocks.
abstract final class BlockType {
  /// Contains the minimum metadata for decoding the audio stream.
  static const int streamInfo = 0;

  /// Padding bytes (no data content).
  static const int padding = 1;

  /// Application-specific metadata.
  static const int application = 2;

  /// Table of seek points into the audio stream.
  static const int seekTable = 3;

  /// Vorbis comment (user-readable tags, e.g. TITLE, ARTIST).
  static const int vorbisComment = 4;

  /// Cue sheet with CD-TOC information.
  static const int cueSheet = 5;

  /// Embedded picture (e.g. cover art).
  static const int picture = 6;
}

/// Base class for all FLAC metadata blocks.
abstract class MetadataBlock {
  /// The block type identifier (see [BlockType]).
  final int blockType;

  /// Whether this is the last metadata block before the audio frames.
  final bool isLast;

  /// The length of the block data in bytes (excluding the 4-byte header).
  final int length;

  const MetadataBlock({
    required this.blockType,
    required this.isLast,
    required this.length,
  });
}

/// A metadata block whose type is not recognised by this library version.
class UnknownMetadataBlock extends MetadataBlock {
  /// The raw bytes of this block's data section.
  final Uint8List rawData;

  const UnknownMetadataBlock({
    required super.blockType,
    required super.isLast,
    required super.length,
    required this.rawData,
  });

  @override
  String toString() =>
      'UnknownMetadataBlock(type=$blockType, length=$length, isLast=$isLast)';
}

// ---------------------------------------------------------------------------
// Internal byte-level helper functions used across all metadata block parsers.
// ---------------------------------------------------------------------------

/// Reads a 32-bit little-endian unsigned integer from [data] at [offset].
int readUint32LE(Uint8List data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);

/// Reads a 32-bit big-endian unsigned integer from [data] at [offset].
int readUint32BE(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

/// Reads a 64-bit big-endian unsigned integer from [data] at [offset].
///
/// Dart integers are 64-bit on the VM/AOT target, so this is safe.
int readUint64BE(Uint8List data, int offset) {
  final hi = (data[offset] << 24) |
      (data[offset + 1] << 16) |
      (data[offset + 2] << 8) |
      data[offset + 3];
  final lo = (data[offset + 4] << 24) |
      (data[offset + 5] << 16) |
      (data[offset + 6] << 8) |
      data[offset + 7];
  return (hi * 0x100000000) + (lo & 0xFFFFFFFF);
}

/// Reads a UTF-8 encoded string of [byteLength] bytes from [data] at [offset].
String readUtf8Bytes(Uint8List data, int offset, int byteLength) {
  final bytes = data.sublist(offset, offset + byteLength);
  // Dart strings are UTF-16 internally; this converts UTF-8 bytes correctly.
  return String.fromCharCodes(bytes);
}

/// Reads a string prefixed by a 32-bit little-endian length field.
///
/// Returns the decoded string and the new offset after the string.
(String, int) readLengthPrefixedStringLE(Uint8List data, int offset) {
  final len = readUint32LE(data, offset);
  offset += 4;
  final str = readUtf8Bytes(data, offset, len);
  return (str, offset + len);
}
