import 'dart:typed_data';

import 'metadata_block.dart';

/// FLAC APPLICATION metadata block.
///
/// Allows third-party applications to store binary data in a FLAC file.
/// The first 4 bytes are a registered application ID; the remainder is
/// application-defined data.
class ApplicationBlock extends MetadataBlock {
  /// Registered application ID (4 bytes, big-endian).
  final int applicationId;

  /// Application-specific data (may be empty).
  final Uint8List applicationData;

  const ApplicationBlock({
    required super.isLast,
    required super.length,
    required this.applicationId,
    required this.applicationData,
  }) : super(blockType: BlockType.application);

  /// Returns the application ID as a 4-character ASCII string where possible.
  String get applicationIdString {
    final bytes = [
      (applicationId >> 24) & 0xFF,
      (applicationId >> 16) & 0xFF,
      (applicationId >> 8) & 0xFF,
      applicationId & 0xFF,
    ];
    return String.fromCharCodes(bytes);
  }

  /// Parses an [ApplicationBlock] from its raw [data] bytes.
  ///
  /// [data] must be at least 4 bytes.
  static ApplicationBlock parse(bool isLast, int length, Uint8List data) {
    if (data.length < 4) {
      throw FormatException(
          'APPLICATION block too short: ${data.length} bytes (need ≥ 4).');
    }
    final id = readUint32BE(data, 0);
    final appData = data.length > 4 ? data.sublist(4) : Uint8List(0);
    return ApplicationBlock(
      isLast: isLast,
      length: length,
      applicationId: id,
      applicationData: appData,
    );
  }

  @override
  String toString() => 'ApplicationBlock('
      'id=0x${applicationId.toRadixString(16).padLeft(8, '0')}, '
      'dataLength=${applicationData.length}'
      ')';
}
