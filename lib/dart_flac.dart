/// A Dart implementation of the FLAC (Free Lossless Audio Codec) library.
///
/// Provides functionality for reading and decoding FLAC audio files,
/// including metadata parsing and audio frame decoding.
library dart_flac;

export 'src/flac_reader.dart' show FlacReader, Md5VerificationResult;
export 'src/pcm_output.dart' show frameToInterleavedPcm;
export 'src/streaming_decoder.dart' show StreamingFlacDecoder;
export 'src/wav_writer.dart' show writeWavBytes;
export 'src/metadata/metadata_block.dart';
export 'src/metadata/stream_info.dart';
export 'src/metadata/padding.dart';
export 'src/metadata/application.dart';
export 'src/metadata/seek_table.dart';
export 'src/metadata/vorbis_comment.dart';
export 'src/metadata/cue_sheet.dart';
export 'src/metadata/picture.dart';
export 'src/frame/frame.dart';
export 'src/frame/subframe.dart';
