# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A pure-Dart implementation of a FLAC (Free Lossless Audio Codec) reader/decoder. No Flutter, no native bindings — the package parses metadata blocks and decodes audio frames entirely in Dart via bit-level reads over a `Uint8List`.

Dart SDK: `^3.0.0`. The only dependencies are `lints` and `test` (dev only).

## Commands

```sh
dart pub get                          # fetch dependencies
dart analyze                          # lint / static analysis (uses package:lints/recommended)
dart test                             # run the full test suite
dart test test/dart_flac_test.dart    # run a single test file
dart test --name 'reads Rice-coded'   # run a single test by name substring
dart format .                         # format the codebase
```

There is no build step — this is a pub package, not an executable. `pubspec.lock` is gitignored.

## Architecture

The public API surface is deliberately thin: `lib/dart_flac.dart` re-exports a single user-facing class (`FlacReader`) plus the metadata/frame types that its accessors return. Everything else lives under `lib/src/` and is an implementation detail.

### Decoding pipeline

1. **`FlacReader.fromBytes` / `.fromFile`** (`lib/src/flac_reader.dart`) validates the `fLaC` marker, then walks the metadata block chain via `_parseAllBlocks`, stopping at the first block with `is_last=1`. The byte offset immediately after the last metadata block is stored as `audioDataOffset` — audio frames are not decoded until `decodeFrames()` is called.
2. **Metadata dispatch** happens in `_parseBlock` (a `switch` on the `BlockType` int). Unknown/reserved block types are preserved as `UnknownMetadataBlock` rather than throwing, so forward-compatibility is the default. Each block type has its own file under `lib/src/metadata/` with a `parse(isLast, length, data)` factory.
3. **Frame decoding** is driven by `FrameParser` in `lib/src/frame/frame.dart`, which repeatedly reads frame headers (with sync-code + CRC-8 verification) and delegates per-channel decoding to `SubframeDecoder` in `lib/src/frame/subframe.dart`. Subframes come in four flavours (CONSTANT / VERBATIM / FIXED / LPC) dispatched by the 6-bit type code, and the outer frame applies stereo decorrelation (left/side, right/side, mid/side) after all subframes are decoded.
4. **`BitReader`** (`lib/src/bit_reader.dart`) is the bit-level primitive shared by both metadata and frame decoders. It supports unsigned/signed N-bit reads, unary codes, Rice codes, UTF-8 coded integers (for frame/sample numbers), and byte-boundary alignment. Many FLAC fields cross byte boundaries — always prefer `BitReader` over manual shift/mask arithmetic on raw bytes.
5. **`crc.dart`** provides CRC-8 (frame header) and CRC-16 (frame footer) used to validate frame integrity.

### Key invariants when adding features

- The first metadata block in a valid FLAC stream is always `STREAMINFO` — `_validateStreamInfo` enforces this, and downstream code (e.g. `decodeFrames` reading `sampleRateFromStreamInfo`) assumes it.
- `FrameHeader.sampleRate` and `bitsPerSample` may use a "get from STREAMINFO" encoding — the parser must be constructed with those values available.
- When adding a new metadata block type, expose it through `FlacReader` as a typed getter using `whereType<T>()` (see how `vorbisComment` / `seekTable` are done), and re-export the type from `lib/dart_flac.dart`.
- Stereo decorrelation is applied *after* per-channel subframe decoding; keep that boundary when refactoring.

### Tests

`test/dart_flac_test.dart` is the single test file. It builds minimal FLAC byte buffers inline (see `_minimalFlac` and the `_buildFlacWithBlock` / `_buildStreamInfoBytes` helpers) rather than shipping binary fixtures. If you add a new metadata block parser, follow the same pattern — construct the bytes in the test so the expected layout is visible alongside the assertion.
