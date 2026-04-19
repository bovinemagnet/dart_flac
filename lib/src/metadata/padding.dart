import 'dart:typed_data';

import 'metadata_block.dart';

/// FLAC PADDING metadata block.
///
/// Contains only zero bytes; used to allow in-place editing of metadata
/// without rewriting the audio data.
class PaddingBlock extends MetadataBlock {
  const PaddingBlock({
    required super.isLast,
    required super.length,
  }) : super(blockType: BlockType.padding);

  /// Parses a [PaddingBlock] from its raw [data] bytes.
  static PaddingBlock parse(bool isLast, int length, Uint8List data) {
    return PaddingBlock(isLast: isLast, length: length);
  }

  @override
  String toString() => 'PaddingBlock(length=$length, isLast=$isLast)';
}
