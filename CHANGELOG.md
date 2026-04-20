# Changelog

## 0.0.1

Initial release.

### Metadata

- Full parsing of STREAMINFO, PADDING, APPLICATION, SEEKTABLE,
  VORBIS_COMMENT, CUESHEET, and PICTURE blocks.
- Graceful preservation of unknown block types as
  `UnknownMetadataBlock`.
- Tolerates a leading ID3v2 tag (with or without the footer flag).

### Audio decoding

- CONSTANT, VERBATIM, FIXED (orders 0–4), and LPC (orders 1–32)
  subframes.
- PARTITIONED_RICE and PARTITIONED_RICE2 residual coding, including
  the escape partition.
- Left/side, right/side, and mid/side joint-stereo decorrelation.
- CRC-8 (frame header) and CRC-16 (frame footer) validation.
- Wasted-bits-per-sample handling.

### Reader APIs

- `FlacReader.fromFile()` / `fromFileSync()` / `fromBytes()`.
- `decodeFrames()` — batch decode.
- `decodeFrames(recoverFromCorruption: true, onCorruption: …)` —
  resync on corrupt frames.
- `decodeInterleavedSamples()` — all samples as an `Int32List`.
- `framesLazy()` — `Iterable<FlacFrame>` decoding one frame per pull.
- `pcmChunks({outputBitsPerSample})` — lazy
  `Iterable<Uint8List>` of interleaved little-endian signed PCM,
  ready to feed to a PCM-accepting audio sink.
- `byteOffsetForSample()` / `decodeFramesFromSample()` — random
  access using SEEKTABLE with a frame-header walk fallback.
- `verifyMd5()` — compares decoded PCM against STREAMINFO.md5,
  returning `match` / `mismatch` / `notComputed`.

### Streaming decoder

- `StreamingFlacDecoder` accepts bytes via `addBytes()` / `close()`
  and emits `Stream<MetadataBlock>`, `Stream<FlacFrame>`, and
  `Stream<Uint8List>` (`pcmStream()`). `onStreamInfo` resolves as
  soon as STREAMINFO has been parsed.

### Conversion helpers

- `frameToInterleavedPcm(frame, outputBitsPerSample)` — standalone
  helper used by both the pull and push APIs.
- `writeWavBytes(…)` — produces a RIFF/WAVE byte buffer at 8/16/24/
  32-bit (8-bit output applies the unsigned WAV bias).
- `bin/flac2wav.dart` — command-line entry point installed via
  `dart run dart_flac:flac2wav`, with `--verify` option.
