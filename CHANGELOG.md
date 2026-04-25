# Changelog

## 0.0.4 — 2026-04-25

- Published archive shrunk from 60 KB to 38 KB by excluding `test/`
  (including the binary `.flac` fixtures) and `tool/` (coverage and
  issue-management scripts) via `.pubignore`. No library behaviour
  change; consumers simply get a smaller download.
- CI now pins the Dart SDK to `3.11.5`, explicitly installs Chrome for
  the browser smoke test, and uploads `coverage/lcov.info` as a
  workflow artefact on every run. No consumer-visible change; tightens
  the development feedback loop.

## 0.0.3 — 2026-04-25

- Add GitHub Actions CI for formatting, analysis, VM tests, browser smoke
  tests, and `dart pub publish --dry-run`.
- Add streaming WAV header/chunk helpers (`writeWavHeaderBytes`,
  `frameToWavPcmBytes`) and make `flac2wav` write PCM incrementally for
  streams with known total samples.
- Add CLI flags for output bit depth, start sample, duration, and explicit
  MD5 verification control.
- `flac2wav` now halts immediately on invalid arguments instead of
  falling through to decode, so a bad `--bits` value can no longer
  silently overwrite a valid output file with a partial decode.
- `flac2wav` writes atomically: output goes to a sibling temp file that
  is renamed over the destination on success. On a mid-decode failure
  the temp is deleted and any pre-existing file at the destination is
  left untouched. The streaming path also patches the RIFF/data chunk
  sizes at close, so the header is honest about the bytes actually
  written (truncated inputs, short tail frames, etc.).
- Add coverage tooling and benchmark JSON/baseline comparison support.
- Add malformed-input and WAV helper tests, plus CLI subprocess tests
  covering streaming/bytes equivalence, validation halting, and
  pre-existing output survival across decode errors.

## 0.0.2 — 2026-04-24

- Add `FlacReader.frontCoverPicture`, `backCoverPicture`, and
  `pictureByType(int)` convenience accessors for the common picture
  lookups. `pictureByType` takes a `PictureType` int code and returns
  the first matching block, or `null`.
- Add a browser smoke test (`test/web_smoke_test.dart`, `@TestOn('browser')`)
  that exercises `decodeFlacBytesToPcm` under `dart2js`. Run with
  `dart test -p chrome`.
- README: new "Community device results" section with an empty
  submission table and a recipe for contributing real-device benchmark
  numbers. `benchmark/format_community_row.dart` provides a canonical
  row formatter that submitters can copy into a Flutter integration
  test.

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

### Multi-valued metadata accessors

- `FlacReader.picturesAll` (alias of `pictures`) — every PICTURE block
  in the stream. FLAC legally permits multiple pictures (front/back
  cover, booklet, artist).
- `FlacReader.cueSheetsAll` — every CUESHEET block. The spec limits
  this to at most one, but real-world files occasionally contain more;
  the singular `cueSheet` still returns the first match.
- `FlacReader.vorbisCommentsAll` — every VORBIS_COMMENT block, with
  the singular `vorbisComment` kept for the common case.

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
- `decodeFlacFileToPcm(path, {outputBitsPerSample = 16})` /
  `decodeFlacBytesToPcm(bytes, {outputBitsPerSample = 16})` —
  top-level, isolate-safe one-shot decoders. Take only a path /
  bytes, return only `Uint8List`, intended for `Isolate.run` call
  sites.
- `bin/flac2wav.dart` — command-line entry point installed via
  `dart run dart_flac:flac2wav`, with `--verify` option.

### Platform support

- Compiles and runs on the Dart VM, AOT, Flutter, and the web.
- 64-bit FLAC fields (SEEKTABLE sample numbers / stream offsets,
  CUESHEET offsets and lead-in samples) are exposed as `Int64` from
  `package:fixnum` so they keep full precision under `dart compile js`
  and Flutter web, where native `int` is limited to 2^53.

### Benchmarks

- `benchmark/decode_benchmark.dart` — subprocess-per-operation harness
  that reports decode throughput and peak RSS for the three decode
  shapes. Desktop baseline numbers documented in README: ~230×
  realtime AOT on a 2024 laptop, with streaming (`pcmChunks`) using
  ~7× less memory than the full-buffer path on a 3-minute track.
