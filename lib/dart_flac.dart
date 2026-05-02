/// Pure-Dart FLAC decoding and metadata parsing.
///
/// Import this library when you need to read FLAC metadata, decode frames,
/// stream little-endian PCM chunks, verify STREAMINFO MD5 signatures, or write
/// decoded samples to a WAV byte stream. The package has no native bindings and
/// works on the Dart VM, Flutter, AOT, and web when bytes are supplied directly.
library;

export 'src/flac_reader.dart'
    show FlacReader, decodeFlacBytesToPcm, decodeFlacFileToPcm;
export 'src/md5_verifier.dart' show Md5Verifier, Md5VerificationResult;
export 'src/pcm_output.dart' show frameToInterleavedPcm;
export 'src/streaming_decoder.dart' show StreamingFlacDecoder;
export 'src/wav_writer.dart'
    show frameToWavPcmBytes, writeWavBytes, writeWavHeaderBytes;
export 'src/metadata/metadata_block.dart';
export 'src/metadata/stream_info.dart';
export 'src/metadata/padding.dart';
export 'src/metadata/application.dart';
export 'src/metadata/seek_table.dart';
export 'src/metadata/vorbis_comment.dart';
export 'src/metadata/cue_sheet.dart';
export 'src/metadata/picture.dart';
// Frame types: deliberately narrow. `FrameParser` and the subframe-level
// helpers stay package-private so the public API doesn't accidentally
// commit to bit-stream parser internals.
export 'src/frame/frame.dart'
    show BlockingStrategy, ChannelAssignment, FlacFrame, FrameHeader;
