import 'dart:convert';
import 'dart:typed_data';

import 'metadata_block.dart';

/// FLAC VORBIS_COMMENT metadata block.
///
/// Stores user-defined tags in the Vorbis comment format:
///   - A vendor string (e.g. the encoder name/version).
///   - Zero or more `KEY=value` comment pairs.
///
/// All strings are UTF-8 encoded with 32-bit little-endian length prefixes.
class VorbisCommentBlock extends MetadataBlock {
  /// The encoder/vendor string.
  final String vendor;

  /// Raw comment strings in the form `KEY=value`.
  final List<String> comments;

  const VorbisCommentBlock({
    required super.isLast,
    required super.length,
    required this.vendor,
    required this.comments,
  }) : super(blockType: BlockType.vorbisComment);

  /// Returns the first value for the given tag [key] (case-insensitive),
  /// or `null` if the tag is not present.
  String? tag(String key) {
    final prefix = '${key.toUpperCase()}=';
    for (final comment in comments) {
      if (comment.toUpperCase().startsWith(prefix)) {
        return comment.substring(prefix.length);
      }
    }
    return null;
  }

  /// Returns all values for the given tag [key] (case-insensitive).
  List<String> tags(String key) {
    final prefix = '${key.toUpperCase()}=';
    return [
      for (final comment in comments)
        if (comment.toUpperCase().startsWith(prefix))
          comment.substring(prefix.length),
    ];
  }

  /// Convenience accessors for common tags.
  String? get title => tag('TITLE');
  String? get artist => tag('ARTIST');
  String? get album => tag('ALBUM');
  String? get date => tag('DATE');
  String? get genre => tag('GENRE');
  String? get trackNumber => tag('TRACKNUMBER');
  String? get discNumber => tag('DISCNUMBER');
  String? get comment => tag('COMMENT');

  /// Parses a [VorbisCommentBlock] from its raw [data] bytes.
  static VorbisCommentBlock parse(bool isLast, int length, Uint8List data) {
    var offset = 0;

    // Vendor string.
    if (data.length - offset < 4) {
      throw const FormatException('VORBIS_COMMENT block truncated: '
          'missing vendor length field.');
    }
    final vendorLen = readUint32LE(data, offset);
    offset += 4;
    if (vendorLen > data.length - offset) {
      throw FormatException('VORBIS_COMMENT vendor length $vendorLen '
          'exceeds the ${data.length - offset} bytes remaining in the block.');
    }
    final vendor = utf8.decode(data.sublist(offset, offset + vendorLen),
        allowMalformed: true);
    offset += vendorLen;

    // Comment list.
    if (data.length - offset < 4) {
      throw const FormatException('VORBIS_COMMENT block truncated: '
          'missing comment count field.');
    }
    final commentCount = readUint32LE(data, offset);
    offset += 4;
    final comments = <String>[];
    for (var i = 0; i < commentCount; i++) {
      if (data.length - offset < 4) {
        throw FormatException('VORBIS_COMMENT block truncated: comment $i '
            'of $commentCount has no length field.');
      }
      final commentLen = readUint32LE(data, offset);
      offset += 4;
      if (commentLen > data.length - offset) {
        throw FormatException('VORBIS_COMMENT comment length $commentLen '
            'exceeds the ${data.length - offset} bytes remaining in the '
            'block.');
      }
      final comment = utf8.decode(data.sublist(offset, offset + commentLen),
          allowMalformed: true);
      offset += commentLen;
      comments.add(comment);
    }

    return VorbisCommentBlock(
      isLast: isLast,
      length: length,
      vendor: vendor,
      comments: comments,
    );
  }

  @override
  String toString() => 'VorbisCommentBlock('
      'vendor="$vendor", '
      '${comments.length} comments'
      ')';
}
