# Extended FLAC conformance tests (issue #21)

**Date:** 2026-07-19
**Author:** Paul Snow
**Status:** Approved design, awaiting implementation plan

## Goal

Test the decoder against real FLAC files — both an extended local fixture set
and the official IETF CELLAR decoder testbench
([ietf-wg-cellar/flac-test-files](https://github.com/ietf-wg-cellar/flac-test-files),
CC0) — without slowing down or complicating the default `dart test` run.

Correctness is verified end-to-end: every valid testbench file carries an MD5
of its decoded PCM in STREAMINFO, and `FlacReader.verifyMd5` already checks
decoded output against it. No reference PCM needs to be shipped for the
conformance tiers.

## Test tiers

### Tier 1 — local fast fixtures (default `dart test`)

Extend `test/fixtures/generate.sh` in its existing style (Python-generated PCM
piped through the reference `flac` CLI, committed `.flac` + `.pcm` pair, each
under ~10 KB):

| Fixture | Coverage gap filled |
|---|---|
| `stereo_20_44100` | 20-bit samples (unusual bit depth) |
| `surround_16_44100` | 6-channel / 5.1 (no current multichannel coverage) |
| `mono_32_48000` | 32-bit samples (flac ≥ 1.4) |

Each fixture gets end-to-end tests in `test/dart_flac_test.dart` following the
existing pattern: decode, byte-compare against the reference `.pcm`, and
`verifyMd5` must return `match`. These run on every `dart test` with zero
setup.

Variable blocksize is deliberately excluded from this tier — the `flac` CLI
cannot produce it. It is covered by the conformance tier (`subset/24`).

### Tier 2 — curated conformance set (`dart test -t conformance`)

A curated ten-file slice of the official testbench, ~12 MB total:

| File | Coverage |
|---|---|
| `subset/01 - blocksize 4096.flac` | Normal stereo, 44.1 kHz, 16-bit |
| `subset/23 - 8 bit per sample.flac` | 8-bit PCM |
| `subset/24 - variable blocksize file created with flake revision 264.flac` | Variable blocksize |
| `subset/28 - high resolution audio, default settings.flac` | 96 kHz / 24-bit |
| `subset/37 - 20 bit per sample.flac` | 20-bit PCM |
| `subset/41 - 6 channels (5.1).flac` | Multichannel |
| `subset/47 - only STREAMINFO.flac` | Minimal metadata |
| `subset/60 - mono audio.flac` | Mono |
| `uncommon/05 - 32bps audio.flac` | 32-bit integer samples |
| `faulty/10 - invalid vorbis comment metadata block.flac` | Clean rejection of malformed metadata |

- Files are fetched by `tool/fetch_conformance.sh` (see below) into
  `test/fixtures/conformance/`, which is **gitignored** — nothing is vendored
  into the repo or the published pub package.
- A new `test/conformance_test.dart` is tagged `conformance` (tag declared in
  a new `dart_test.yaml`). If the conformance directory is absent the tests
  skip with a message pointing at the fetch script, so plain `dart test`
  remains zero-setup.
- The manifest is a `const` Dart list in the test file (path, expected
  channels / sample rate / bit depth, valid vs faulty) — type-checked data
  instead of a YAML sidecar.
- **Valid files:** parse → assert STREAMINFO properties against the manifest →
  `decodeFrames()` → `verifyMd5` must return `match`.
- **Faulty files:** must fail by throwing `FlacException` — never a
  `RangeError`, hang, or silently wrong output.

### Tier 3 — full testbench sweep (`dart test -t conformance-full`)

A second group in the same test file, tagged `conformance-full`, that globs
whatever is present under the conformance directory:

- `subset/` (67 files) and `uncommon/` (11 files): parse, decode, `verifyMd5`
  must return `match` (or `notComputed` where the stream carries no MD5).
- `faulty/` (11 files): must fail cleanly with `FlacException`.

Known-unsupported behaviours discovered by the sweep (likely candidates:
`uncommon/01–04` mid-stream parameter changes, `uncommon/10–11` streams
starting without metadata) are recorded as explicit skip entries with a
reason and a linked issue — the sweep is not weakened to make them pass.

## Fetch script — `tool/fetch_conformance.sh`

Bash, matching the existing `tool/` script conventions.

- Pins a specific `flac-test-files` commit SHA in a variable at the top of
  the script; bumping the testbench is a deliberate one-line change.
- **Default mode:** downloads only the ten curated files individually from
  `raw.githubusercontent.com/ietf-wg-cellar/flac-test-files/<SHA>/...`
  (~12 MB). Idempotent — skips files already present.
- **`--full` mode:** downloads the pinned tarball
  (`codeload.github.com/.../tar.gz/<SHA>`, ~201 MB, ~296 MB extracted) and
  extracts `subset/`, `uncommon/` and `faulty/` into the same directory.

## CI

Download size was a stated concern; the split above resolves it:

- **`conformance` job in `ci.yml`** (every PR/push): restore
  `test/fixtures/conformance/` from `actions/cache` keyed on the pinned SHA;
  on miss, run the fetch script (12 MB, GitHub-to-runner, seconds). Then
  `dart test -t conformance`. Steady-state PRs download nothing.
- **`conformance-full.yml`** (`workflow_dispatch` only): fetch with `--full`
  (201 MB — acceptable for a manual job on a GitHub runner), then
  `dart test -t conformance-full`. Never runs on PRs.

## Out of scope

- Vendoring any testbench file into the repo.
- ffmpeg-generated fixtures (the issue suggested them; the repo already
  standardises on the reference `flac` CLI).
- Decoder changes. If the sweep exposes gaps, each becomes its own issue.

## Success criteria

1. `dart test` passes with no network access and covers the three new local
   fixtures.
2. After `tool/fetch_conformance.sh`, `dart test -t conformance` passes: all
   nine valid curated files decode with an MD5 match and the faulty file is
   rejected with `FlacException`.
3. After `tool/fetch_conformance.sh --full`, `dart test -t conformance-full`
   runs the whole testbench; every non-passing file is either a genuine
   decoder gap (filed as an issue and listed as a skip with reason) or a bug
   fixed under this work.
4. The `conformance` CI job passes on a PR, using the cache on the second run.
