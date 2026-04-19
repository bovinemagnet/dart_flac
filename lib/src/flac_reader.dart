import 'dart:io';
import 'dart:typed_data';

import 'frame/frame.dart';
import 'metadata/application.dart';
import 'metadata/cue_sheet.dart';
import 'metadata/metadata_block.dart';
import 'metadata/padding.dart';
import 'metadata/picture.dart';
import 'metadata/seek_table.dart';
import 'metadata/stream_info.dart';
import 'metadata/vorbis_comment.dart';

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
    _validateMarker(bytes);
    final (blocks, audioOffset) = _parseAllBlocks(bytes, 4);
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
  List<FlacFrame> decodeFrames() {
    final info = streamInfo;
    final parser = FrameParser(
      data: _data,
      sampleRateFromStreamInfo: info.sampleRate,
      bitsPerSampleFromStreamInfo: info.bitsPerSample,
    );
    return parser.parseAllFrames(audioDataOffset);
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

  static void _validateMarker(Uint8List bytes) {
    if (bytes.length < 4) {
      throw FormatException('File is too short to be a FLAC stream.');
    }
    for (var i = 0; i < 4; i++) {
      if (bytes[i] != _flacMarker[i]) {
        throw FormatException(
            'Missing FLAC stream marker "fLaC". '
            'Got: 0x${bytes[i].toRadixString(16)} at byte $i.');
      }
    }
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

    final block = _parseBlock(type, isLast, length, blockData);
    blocks.add(block);

    if (isLast) break;
  }
  return (blocks, offset);
}

MetadataBlock _parseBlock(
    int type, bool isLast, int length, Uint8List data) {
  switch (type) {
    case BlockType.streamInfo:
      return StreamInfoBlock.parse(isLast, length, data);
    case BlockType.padding:
      return PaddingBlock.parse(isLast, length, data);
    case BlockType.application:
      return ApplicationBlock.parse(isLast, length, data);
    case BlockType.seekTable:
      return SeekTableBlock.parse(isLast, length, data);
    case BlockType.vorbisComment:
      return VorbisCommentBlock.parse(isLast, length, data);
    case BlockType.cueSheet:
      return CueSheetBlock.parse(isLast, length, data);
    case BlockType.picture:
      return PictureBlock.parse(isLast, length, data);
    default:
      return UnknownMetadataBlock(
          blockType: type, isLast: isLast, length: length, rawData: data);
  }
}
