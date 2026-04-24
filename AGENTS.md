# Repository Guidelines

## Project Structure & Module Organization

`dart_flac` is a pure-Dart FLAC decoder package. The public API is exported from `lib/dart_flac.dart`; implementation code lives under `lib/src/`. Core decoding is split across `flac_reader.dart`, `streaming_decoder.dart`, `bit_reader.dart`, `crc.dart`, `frame/`, and `metadata/`. CLI code is in `bin/flac2wav.dart`. Runnable usage examples are in `example/`, benchmarks are in `benchmark/`, and tests plus binary fixtures are in `test/`.

## Build, Test, and Development Commands

- `dart pub get` installs package dependencies.
- `dart analyze` runs static analysis using `package:lints/recommended`.
- `dart test` runs the full VM test suite.
- `dart test test/dart_flac_test.dart` runs the main native test file.
- `dart test -p chrome test/web_smoke_test.dart` verifies browser compatibility.
- `./tool/coverage.sh` writes `coverage/lcov.info`.
- `dart format .` formats all Dart sources.
- `dart run dart_flac:flac2wav --verify input.flac output.wav` exercises the CLI converter.
- `dart run benchmark/decode_benchmark.dart --json-out benchmark/latest.json` runs decode benchmarks after generating required benchmark fixtures.

## Coding Style & Naming Conventions

Use standard Dart formatting: two-space indentation, trailing commas where they improve formatter output, and `lowerCamelCase` for variables, functions, and getters. Use `UpperCamelCase` for types and enum-like classes. Keep library exports intentional in `lib/dart_flac.dart`; implementation details should remain under `lib/src/`. Prefer `BitReader` for FLAC bit fields instead of ad hoc byte shifting.

## Testing Guidelines

Tests use `package:test`. Name tests by observable behavior, for example `fromBytes rejects non-FLAC data` or `decodeFlacBytesToPcm returns 16-bit LE PCM in a browser`. Prefer small inline byte fixtures for parser behavior so layouts are visible near assertions. Use files in `test/fixtures/` for realistic decode coverage. Add browser tests when changing APIs that must work without `dart:io`.

## Commit & Pull Request Guidelines

Recent commits use concise imperative subjects such as `Add decode benchmark harness...` and `Expose multi-valued metadata-block accessors`. Keep subjects focused and mention releases explicitly when applicable. Pull requests should describe the user-visible change, list test commands run, link related issues, and call out compatibility impacts for VM, web, CLI, or public API exports.

## Agent-Specific Notes

Before editing decoder internals, read nearby tests and preserve FLAC invariants: `STREAMINFO` must be first, unknown metadata blocks should remain tolerated, and stereo decorrelation happens after subframe decoding.
