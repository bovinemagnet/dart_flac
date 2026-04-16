import 'dart:typed_data';

import 'metadata_block.dart';

/// Picture types as defined in the ID3v2 APIC frame specification.
abstract final class PictureType {
  static const int other = 0;
  static const int fileIcon32x32 = 1;
  static const int otherFileIcon = 2;
  static const int coverFront = 3;
  static const int coverBack = 4;
  static const int leafletPage = 5;
  static const int media = 6;
  static const int leadArtist = 7;
  static const int artist = 8;
  static const int conductor = 9;
  static const int bandOrchestra = 10;
  static const int composer = 11;
  static const int lyricist = 12;
  static const int recordingLocation = 13;
  static const int duringRecording = 14;
  static const int duringPerformance = 15;
  static const int videoScreenCapture = 16;
  static const int brightColoredFish = 17;
  static const int illustration = 18;
  static const int artistLogotype = 19;
  static const int publisherStudioLogotype = 20;
}

/// FLAC PICTURE metadata block.
///
/// Stores an embedded image (typically album cover art).
class PictureBlock extends MetadataBlock {
  /// Picture type (see [PictureType]).
  final int pictureType;

  /// MIME type string (e.g. `"image/jpeg"`, `"image/png"`).
  final String mimeType;

  /// UTF-8 description of the image.
  final String description;

  /// Image width in pixels (0 if unknown or not applicable).
  final int width;

  /// Image height in pixels (0 if unknown or not applicable).
  final int height;

  /// Color depth (bits per pixel, 0 if unknown or not applicable).
  final int colorDepth;

  /// Number of colors (0 for non-indexed images or unknown).
  final int colorsUsed;

  /// The raw image data.
  final Uint8List pictureData;

  const PictureBlock({
    required super.isLast,
    required super.length,
    required this.pictureType,
    required this.mimeType,
    required this.description,
    required this.width,
    required this.height,
    required this.colorDepth,
    required this.colorsUsed,
    required this.pictureData,
  }) : super(blockType: BlockType.picture);

  /// Parses a [PictureBlock] from its raw [data] bytes.
  static PictureBlock parse(bool isLast, int length, Uint8List data) {
    var offset = 0;

    final pictureType = readUint32BE(data, offset);
    offset += 4;

    // MIME type: 32-bit BE length + UTF-8 bytes.
    final mimeLen = readUint32BE(data, offset);
    offset += 4;
    final mimeType = String.fromCharCodes(data.sublist(offset, offset + mimeLen));
    offset += mimeLen;

    // Description: 32-bit BE length + UTF-8 bytes.
    final descLen = readUint32BE(data, offset);
    offset += 4;
    final description =
        String.fromCharCodes(data.sublist(offset, offset + descLen));
    offset += descLen;

    final width = readUint32BE(data, offset);
    offset += 4;
    final height = readUint32BE(data, offset);
    offset += 4;
    final colorDepth = readUint32BE(data, offset);
    offset += 4;
    final colorsUsed = readUint32BE(data, offset);
    offset += 4;

    // Picture data: 32-bit BE length + bytes.
    final dataLen = readUint32BE(data, offset);
    offset += 4;
    final pictureData = data.sublist(offset, offset + dataLen);

    return PictureBlock(
      isLast: isLast,
      length: length,
      pictureType: pictureType,
      mimeType: mimeType,
      description: description,
      width: width,
      height: height,
      colorDepth: colorDepth,
      colorsUsed: colorsUsed,
      pictureData: pictureData,
    );
  }

  @override
  String toString() => 'PictureBlock('
      'type=$pictureType, '
      'mime="$mimeType", '
      '${width}x$height, '
      '${pictureData.length} bytes'
      ')';
}
