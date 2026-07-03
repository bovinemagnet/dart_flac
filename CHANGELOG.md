# Changelog

## Unreleased

- Fix 32-bit stream decoding. `BitReader.readSignedBits` never
  sign-extended 32-bit reads, and the side channel of a stereo-decorrelated
  32-bit frame is coded at 33 bits — one wider than the reader allowed and
  the `Int32List` sample buffer could hold. Negative 32-bit samples now
  decode correctly, and left/side, right/side, and mid/side 32-bit frames
  reconstruct without truncating the side channel. Subframe sample buffers
  fall back to a plain `List<int>` only for the 33-bit side-channel case;
  all other widths keep the `Int32List` fast path, and the public
  `FlacFrame.channelSamples` type is unchanged.
- Fix a crash on escaped residual partitions that declare a 0-bit sample
  size. RFC 9639 permits such partitions (every residual in the partition
  is 0); the decoder now produces the zeros instead of throwing.
- `decodeFrames(recoverFromCorruption: true)` now recovers from truncated
  frames as documented. The tolerant parser previously caught only
  `FormatException`, but the bit reader signals end-of-data with a
  `StateError`, so a truncated file aborted the whole decode. Both are now
  caught, reported through `onCorruption`, and decoding resumes at the
  next frame sync code.
- Accept 7-byte UTF-8 coded numbers in frame headers. Sample numbers in
  variable-blocksize streams are up to 36 bits, which encode as a 7-byte
  `0xFE` sequence; the reader previously rejected it as invalid, so
  frames beyond sample 2³¹ (roughly 13.5 hours at 44.1 kHz) failed to
  decode.
- Fix MD5 verification for bit depths that are not a multiple of 8.
  The digest was computed over playback-shifted PCM, but the FLAC
  reference encoder hashes each sample as-is in `ceil(bps/8)`
  little-endian bytes, so `verifyMd5` reported a false mismatch on valid
  12- and 20-bit files. A new `frameToMd5Pcm` function provides the
  reference packing (identical to `frameToInterleavedPcm` for
  byte-aligned depths); `computePcmMd5`, `flac2wav --verify`, and the
  `Md5Verifier` documentation now use it.
- `StreamingFlacDecoder` no longer wedges on a corrupt frame. A frame
  that failed to parse (e.g. CRC mismatch) threw synchronously out of
  `addBytes` and left the decoder stuck re-throwing at the same offset.
  Corrupt frames are now reported as error events on the `frames`
  stream, and decoding resumes at the next frame sync code.

## 0.0.6 — 2026-05-17

- Narrow the public API. `package:dart_flac/dart_flac.dart` previously
  did wholesale `export 'src/frame/frame.dart'` and
  `export 'src/frame/subframe.dart'`, which leaked every
  public-by-default symbol in those files into the package surface.
  The frame export is now `show`-filtered to exactly the four types
  that have a documented place in the public API: `BlockingStrategy`,
  `ChannelAssignment`, `FlacFrame`, and `FrameHeader`. The
  `subframe.dart` re-export is dropped entirely.
- As a result, `FrameParser` (the bit-stream parser, which takes a
  non-public `BitReader`), `SubframeType`, and `SubframeDecoder` are no
  longer re-exported from `package:dart_flac/dart_flac.dart`. These
  were never documented as public API — they are internal helpers used
  only by the decoder itself. This is breaking only for code that
  imported those symbols by accident; the package is pre-1.0, so this
  is the right time to tighten the surface to the "deliberately thin
  API" goal.

## 0.0.5 — 2026-04-25

- Add `Md5Verifier` (`lib/src/md5_verifier.dart`), a streaming MD5
  verifier seeded from STREAMINFO. Feed it native-bit-depth interleaved
  PCM bytes via `addPcm`, then call `finalize()` to get a
  `Md5VerificationResult`. Lets callers verify file integrity in the
  same pass they decode for some other purpose.
- `flac2wav --verify` now does one decode pass instead of two on a
  full-stream conversion: the WAV write loop tees one
  `frameToInterleavedPcm` per frame into the streaming verifier, and
  the post-write step just calls `finalize()`. For partial decodes
  (`--start-sample` / `--duration-samples`) the CLI still falls back
  to `reader.verifyMd5()` so a sliced extract is verified against the
  original file's MD5, not the slice's own digest.
- `flac2wav` now validates `--bits`, `--start-sample`, and
  `--duration-samples` *before* opening the input file. Previously a
  bad argument could be masked by a downstream file/parse error,
  reporting the wrong problem to the user.
- `Md5VerificationResult` is now defined in `md5_verifier.dart`
  (re-exported from `package:dart_flac/dart_flac.dart` at the same
  name; the public-API import path is unchanged). Direct imports of
  `package:dart_flac/src/flac_reader.dart` will need updating, but
  `src/` paths are not part of the public API.

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
