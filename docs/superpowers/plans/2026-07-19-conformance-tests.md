# Extended FLAC Conformance Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Test the decoder against real FLAC files: three new local fixtures on every `dart test`, the curated official CELLAR testbench slice behind a `conformance` tag (CI on every PR), and the full 296 MB testbench behind a `conformance-full` tag (manual CI workflow).

**Architecture:** Local fixtures extend the existing `test/fixtures/generate.sh` pattern (Python PCM → `flac` CLI → committed `.flac` + `.pcm` pair). Official files are never committed: `tool/fetch_conformance.sh` downloads them (pinned commit SHA) into gitignored `test/fixtures/conformance/`, and tagged test files self-skip when the files are absent. Correctness is proven by `FlacReader.verifyMd5` against the MD5 baked into each file's STREAMINFO — no reference PCM needed for official files.

**Tech Stack:** Dart `^3.0.0`, `package:test`, bash, `flac` CLI (1.5.0 verified locally), `python3`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-07-19-conformance-tests-design.md`

## Global Constraints

- Dependencies: dev-only `lints`, `test`, `coverage` — add nothing new.
- Decoder error contract is core `FormatException`. There is no custom exception type; never invent one.
- Pinned testbench commit: `aa7b0c6cf32994c106ae517a08134c28a96ff5b2` (repo `ietf-wg-cellar/flac-test-files`, CC0).
- `test/fixtures/conformance/` is gitignored; no official file is ever committed or published to pub.
- The `flac` CLI accepts only 8/16/24/32-bit raw input, so the 20-bit fixture is fed as a `WAVE_FORMAT_EXTENSIBLE` WAV with `wValidBitsPerSample = 20`.
- Pre-existing fixture files under `test/fixtures/` must not churn: after regenerating, `git restore` any pre-existing pair the script rewrote.
- Reference `.pcm` byte layout must match the test helper `_samplesToLePcm` (`test/dart_flac_test.dart:2039`): value masked to `ceil(bits/8)*8` bits (sign-extended two's complement), packed little-endian — for 20-bit that means `v & 0xFFFFFF` in 3 bytes, NOT `v & 0xFFFFF`.
- Run `dart format .` before each commit; CI enforces `--set-exit-if-changed`.
- British spelling in comments and docs. No AI references in commits; no co-author lines.

**Probed baseline (2026-07-19, commit `aa7b0c6`, decoder at branch point):** the decoder already passes the entire testbench. All 64 `subset/` files → `verifyMd5` = `match`. `uncommon/01–04` → decode, `notComputed` (no MD5 in STREAMINFO); `uncommon/05–09` → `match`; `uncommon/10–11` → `FormatException` (no `fLaC` marker — capability boundary). `faulty/06,07,10,11` → `FormatException`; `faulty/01,02,04,05,08,09` → decode with `match`; `faulty/03` (wrong bit depth) → decode with `mismatch`. The sweep locks in exactly this baseline.

---

### Task 1: Local fixtures — 20-bit stereo, 5.1 surround, 32-bit mono

**Files:**
- Modify: `test/fixtures/generate.sh` (append three fixture sections before the final `ls` line)
- Create (generated, committed): `test/fixtures/stereo_20_44100.flac` + `.pcm`, `test/fixtures/surround_16_44100.flac` + `.pcm`, `test/fixtures/mono_32_48000.flac` + `.pcm`
- Modify: `test/dart_flac_test.dart` (three new groups after the `Fixture: mono 16-bit noise` group, which ends near line 1320)

**Interfaces:**
- Consumes: existing test helpers `_samplesToLePcm(Int32List, int)` and the fixture-group pattern at `test/dart_flac_test.dart:1212`.
- Produces: six committed fixture files used only by these tests.

- [ ] **Step 1: Write the failing tests**

Add to `test/dart_flac_test.dart`, immediately after the `Fixture: mono 16-bit noise (VERBATIM subframes)` group closes (follow the exact style of the groups at lines 1212–1294):

```dart
group('Fixture: stereo 20-bit 44100 Hz', () {
  late FlacReader reader;
  late Uint8List expectedPcm;

  setUp(() {
    reader = FlacReader.fromFileSync('test/fixtures/stereo_20_44100.flac');
    expectedPcm = File('test/fixtures/stereo_20_44100.pcm').readAsBytesSync();
  });

  test('STREAMINFO', () {
    expect(reader.streamInfo.sampleRate, equals(44100));
    expect(reader.streamInfo.channels, equals(2));
    expect(reader.streamInfo.bitsPerSample, equals(20));
    expect(reader.streamInfo.totalSamples, equals(256));
  });

  test('decoded PCM matches encoder input', () {
    final samples = reader.decodeInterleavedSamples();
    expect(samples.length, equals(512)); // 256 × 2 channels
    final decodedPcm = _samplesToLePcm(samples, 20);
    expect(decodedPcm, equals(expectedPcm));
  });

  test('MD5 verification passes', () {
    expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
  });
});

group('Fixture: 5.1 surround 16-bit 44100 Hz', () {
  late FlacReader reader;
  late Uint8List expectedPcm;

  setUp(() {
    reader = FlacReader.fromFileSync('test/fixtures/surround_16_44100.flac');
    expectedPcm = File('test/fixtures/surround_16_44100.pcm').readAsBytesSync();
  });

  test('STREAMINFO', () {
    expect(reader.streamInfo.sampleRate, equals(44100));
    expect(reader.streamInfo.channels, equals(6));
    expect(reader.streamInfo.bitsPerSample, equals(16));
    expect(reader.streamInfo.totalSamples, equals(256));
  });

  test('decoded PCM matches encoder input', () {
    final samples = reader.decodeInterleavedSamples();
    expect(samples.length, equals(1536)); // 256 × 6 channels
    final decodedPcm = _samplesToLePcm(samples, 16);
    expect(decodedPcm, equals(expectedPcm));
  });

  test('MD5 verification passes', () {
    expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
  });
});

group('Fixture: mono 32-bit 48000 Hz', () {
  late FlacReader reader;
  late Uint8List expectedPcm;

  setUp(() {
    reader = FlacReader.fromFileSync('test/fixtures/mono_32_48000.flac');
    expectedPcm = File('test/fixtures/mono_32_48000.pcm').readAsBytesSync();
  });

  test('STREAMINFO', () {
    expect(reader.streamInfo.sampleRate, equals(48000));
    expect(reader.streamInfo.channels, equals(1));
    expect(reader.streamInfo.bitsPerSample, equals(32));
    expect(reader.streamInfo.totalSamples, equals(256));
  });

  test('decoded PCM matches encoder input', () {
    final samples = reader.decodeInterleavedSamples();
    expect(samples.length, equals(256));
    final decodedPcm = _samplesToLePcm(samples, 32);
    expect(decodedPcm, equals(expectedPcm));
  });

  test('MD5 verification passes', () {
    expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
  });
});
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `dart test test/dart_flac_test.dart --name 'Fixture: stereo 20-bit'`
Expected: FAIL — `PathNotFoundException` / cannot open `test/fixtures/stereo_20_44100.flac` (fixture not generated yet).

- [ ] **Step 3: Extend the generator**

Append to `test/fixtures/generate.sh`, before the final `ls -la *.flac *.pcm` line:

```bash
# ---------------------------------------------------------------------------
# Fixture 5: stereo, 20-bit, 44100 Hz. 256 samples.
# The flac CLI only accepts 8/16/24/32-bit raw input, so a
# WAVE_FORMAT_EXTENSIBLE WAV with wValidBitsPerSample=20 is generated as the
# encoder input (samples left-justified in a 24-bit container). The committed
# .pcm reference holds the right-justified 20-bit values in 24-bit two's
# complement, 3 bytes little-endian — the decoder's output convention.
# Exercises: 20-bit bps, non-byte-aligned depth, MD5 at 20 bits.
# ---------------------------------------------------------------------------
python3 - <<'PY'
import struct, math
sr = 44100
pcm = bytearray()
wav = bytearray()
for i in range(256):
    l = int(400000 * math.sin(2 * math.pi * 440 * i / sr))
    r = int(200000 * math.sin(2 * math.pi * 660 * i / sr))
    for v in (l, r):
        pcm += (v & 0xFFFFFF).to_bytes(3, 'little')
        wav += ((v << 4) & 0xFFFFFF).to_bytes(3, 'little')
fmt = struct.pack('<HHIIHH', 0xFFFE, 2, sr, sr * 6, 6, 24)
fmt += struct.pack('<HHI', 22, 20, 0x3)  # cbSize, valid bits, channel mask
fmt += b'\x01\x00\x00\x00\x00\x00\x10\x00\x80\x00\x00\xaa\x00\x38\x9b\x71'
data = bytes(wav)
riff = (b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt
        + b'data' + struct.pack('<I', len(data)) + data)
open('stereo_20_44100.wav', 'wb').write(b'RIFF' + struct.pack('<I', len(riff)) + riff)
open('stereo_20_44100.pcm', 'wb').write(bytes(pcm))
PY

flac --silent --force --no-preserve-modtime --verify \
     -o stereo_20_44100.flac stereo_20_44100.wav
rm stereo_20_44100.wav

# ---------------------------------------------------------------------------
# Fixture 6: 5.1 surround (6 channels), 16-bit, 44100 Hz. 256 samples, a
# different sine per channel. Exercises: independent-channel decoding with
# channel count > 2, MD5 over six interleaved channels.
# ---------------------------------------------------------------------------
python3 - <<'PY' > surround_16_44100.pcm
import struct, math, sys
sr = 44100
for i in range(256):
    for ch in range(6):
        v = int(8000 * math.sin(2 * math.pi * (220 * (ch + 1)) * i / sr))
        sys.stdout.buffer.write(struct.pack('<h', v))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=6 --bps=16 --sample-rate=44100 \
     --force-raw-format \
     -o surround_16_44100.flac surround_16_44100.pcm

# ---------------------------------------------------------------------------
# Fixture 7: mono, 32-bit, 48000 Hz. 256 samples. Requires flac >= 1.4.
# Exercises: 32-bit bps (the format's maximum), MD5 at 4 bytes per sample.
# ---------------------------------------------------------------------------
python3 - <<'PY' > mono_32_48000.pcm
import struct, math, sys
sr = 48000
for i in range(256):
    v = int(1_000_000_000 * math.sin(2 * math.pi * 440 * i / sr))
    sys.stdout.buffer.write(struct.pack('<i', v))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=1 --bps=32 --sample-rate=48000 \
     --force-raw-format \
     -o mono_32_48000.flac mono_32_48000.pcm
```

- [ ] **Step 4: Generate, and restore any churn to pre-existing fixtures**

Run: `./test/fixtures/generate.sh`
Expected: final `ls` lists 7 `.flac` + 7 `.pcm` files, no errors (`--verify` makes flac itself round-trip-check each encode).

Then run: `git status --porcelain test/fixtures/`
The script regenerates the four pre-existing pairs too; if any of `stereo_16_44100.*`, `mono_8_16000.*`, `stereo_24_96000.*`, `noise_16_44100.*` show as modified, restore them:

Run: `git restore test/fixtures/stereo_16_44100.flac test/fixtures/stereo_16_44100.pcm test/fixtures/mono_8_16000.flac test/fixtures/mono_8_16000.pcm test/fixtures/stereo_24_96000.flac test/fixtures/stereo_24_96000.pcm test/fixtures/noise_16_44100.flac test/fixtures/noise_16_44100.pcm`

- [ ] **Step 5: Run the new tests to verify they pass**

Run: `dart test test/dart_flac_test.dart --name 'Fixture:'`
Expected: PASS — all fixture groups including the three new ones (12 new tests).

- [ ] **Step 6: Run the full suite**

Run: `dart test`
Expected: PASS, no failures.

- [ ] **Step 7: Format and commit**

```bash
dart format .
git add test/fixtures/generate.sh test/fixtures/stereo_20_44100.flac test/fixtures/stereo_20_44100.pcm test/fixtures/surround_16_44100.flac test/fixtures/surround_16_44100.pcm test/fixtures/mono_32_48000.flac test/fixtures/mono_32_48000.pcm test/dart_flac_test.dart
git commit -m "Add 20-bit, 5.1 surround, and 32-bit local test fixtures"
```

---

### Task 2: Conformance fetch script, gitignore entry, test tags

**Files:**
- Create: `tool/fetch_conformance.sh` (executable)
- Modify: `.gitignore` (append entry)
- Create: `dart_test.yaml` (repo root)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `tool/fetch_conformance.sh` (no args → curated ten files; `--full` → whole testbench) populating `test/fixtures/conformance/{subset,uncommon,faulty}/` with the official filenames (spaces preserved). Tags `conformance` and `conformance-full` declared for Tasks 3–5.

- [ ] **Step 1: Write the fetch script**

Create `tool/fetch_conformance.sh`:

```bash
#!/usr/bin/env bash
# Fetch FLAC decoder conformance files from the IETF CELLAR testbench
# (https://github.com/ietf-wg-cellar/flac-test-files, CC0).
#
# Default: download the ten curated files used by `dart test -t conformance`
#          (~12 MB, fetched individually).
# --full:  download the complete testbench tarball (~201 MB download,
#          ~296 MB extracted) used by `dart test -t conformance-full`.
#
# Files land in test/fixtures/conformance/ (gitignored). Idempotent: files
# already present are not downloaded again. Run from anywhere; the script
# resolves paths relative to the repository root.

set -euo pipefail
cd "$(dirname "$0")/.."

# Bump deliberately: also update the actions/cache key in
# .github/workflows/ci.yml and re-triage test/conformance_full_test.dart.
SHA=aa7b0c6cf32994c106ae517a08134c28a96ff5b2
DEST=test/fixtures/conformance

CURATED=(
  "subset/01 - blocksize 4096.flac"
  "subset/23 - 8 bit per sample.flac"
  "subset/24 - variable blocksize file created with flake revision 264.flac"
  "subset/28 - high resolution audio, default settings.flac"
  "subset/37 - 20 bit per sample.flac"
  "subset/41 - 6 channels (5.1).flac"
  "subset/47 - only STREAMINFO.flac"
  "subset/60 - mono audio.flac"
  "uncommon/05 - 32bps audio.flac"
  "faulty/10 - invalid vorbis comment metadata block.flac"
)

if [[ "${1:-}" == "--full" ]]; then
  marker="$DEST/.full-$SHA"
  if [[ -f "$marker" ]]; then
    echo "Full testbench already present ($SHA)."
    exit 0
  fi
  mkdir -p "$DEST"
  echo "Downloading full testbench tarball (~201 MB)..."
  curl -fsSL "https://codeload.github.com/ietf-wg-cellar/flac-test-files/tar.gz/$SHA" \
    | tar -xz -C "$DEST" --strip-components=1
  touch "$marker"
  echo "Extracted full testbench to $DEST."
else
  for path in "${CURATED[@]}"; do
    out="$DEST/$path"
    [[ -f "$out" ]] && continue
    mkdir -p "$(dirname "$out")"
    url="https://raw.githubusercontent.com/ietf-wg-cellar/flac-test-files/$SHA/${path// /%20}"
    echo "Fetching $path"
    curl -fsSL -o "$out" "$url"
  done
  echo "Curated conformance files present in $DEST."
fi
```

Run: `chmod +x tool/fetch_conformance.sh`

- [ ] **Step 2: Gitignore the download directory**

Append to `.gitignore`:

```
# Official CELLAR conformance files (fetched by tool/fetch_conformance.sh)
test/fixtures/conformance/
```

- [ ] **Step 3: Declare the test tags**

Create `dart_test.yaml`:

```yaml
tags:
  # Needs the curated CELLAR files: tool/fetch_conformance.sh (~12 MB).
  # Tests self-skip when the files are absent.
  conformance:
  # Needs the complete testbench: tool/fetch_conformance.sh --full (~201 MB).
  conformance-full:
```

- [ ] **Step 4: Verify the curated fetch**

Run: `./tool/fetch_conformance.sh`
Expected: ten "Fetching …" lines, then "Curated conformance files present…".

Run: `find test/fixtures/conformance -name '*.flac' | wc -l`
Expected: `10`

Run: `./tool/fetch_conformance.sh`
Expected: instant, no "Fetching" lines (idempotent).

Run: `git status --porcelain`
Expected: `test/fixtures/conformance/` does NOT appear (gitignore works). Changed files shown: `.gitignore`, `dart_test.yaml`, `tool/fetch_conformance.sh` only.

- [ ] **Step 5: Verify existing suite is unaffected**

Run: `dart test`
Expected: PASS (the tags exist but nothing uses them yet).

- [ ] **Step 6: Commit**

```bash
git add tool/fetch_conformance.sh .gitignore dart_test.yaml
git commit -m "Add fetch script and test tags for CELLAR conformance files"
```

---

### Task 3: Curated conformance tests

**Files:**
- Create: `test/support/conformance.dart`
- Create: `test/conformance_test.dart`

**Interfaces:**
- Consumes: `test/fixtures/conformance/` layout and filenames from Task 2's script; public API `FlacReader.fromFileSync(String)`, `reader.streamInfo.{channels,sampleRate,bitsPerSample}`, `reader.verifyMd5()` returning `Md5VerificationResult` (`match` / `mismatch` / `notComputed`).
- Produces: `test/support/conformance.dart` exposing `const String conformanceDir`, `bool get curatedFilesPresent`, `bool get fullSetPresent`, and `Md5VerificationResult verifyFile(String path)` — Task 4 imports all of these.

- [ ] **Step 1: Write the shared support helper**

Create `test/support/conformance.dart`:

```dart
import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

/// Root directory populated by `tool/fetch_conformance.sh`.
const conformanceDir = 'test/fixtures/conformance';

/// Present after any fetch: the first curated file.
bool get curatedFilesPresent =>
    File('$conformanceDir/subset/01 - blocksize 4096.flac').existsSync();

/// Present only after `--full`: a file outside the curated set, so its
/// existence means the whole testbench is available.
bool get fullSetPresent =>
    File('$conformanceDir/subset/02 - blocksize 4608.flac').existsSync();

/// Parses and fully decodes one file, returning the STREAMINFO MD5 verdict.
/// [Md5VerificationResult.match] proves a bit-exact decode of the whole
/// stream. Throws [FormatException] for streams the reader rejects.
Md5VerificationResult verifyFile(String path) =>
    FlacReader.fromFileSync(path).verifyMd5();
```

- [ ] **Step 2: Write the curated test file**

Create `test/conformance_test.dart`:

```dart
@Tags(['conformance'])
library;

import 'package:dart_flac/dart_flac.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

/// Curated slice of the CELLAR testbench (see
/// docs/superpowers/specs/2026-07-19-conformance-tests-design.md).
/// STREAMINFO expectations were read from the files with `metaflac`.
class _ValidCase {
  const _ValidCase(
    this.path, {
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
  });

  final String path;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
}

const _validCases = [
  _ValidCase('subset/01 - blocksize 4096.flac',
      channels: 2, sampleRate: 44100, bitsPerSample: 16),
  _ValidCase('subset/23 - 8 bit per sample.flac',
      channels: 2, sampleRate: 44100, bitsPerSample: 8),
  _ValidCase(
      'subset/24 - variable blocksize file created with flake revision 264.flac',
      channels: 2,
      sampleRate: 44100,
      bitsPerSample: 16),
  _ValidCase('subset/28 - high resolution audio, default settings.flac',
      channels: 2, sampleRate: 96000, bitsPerSample: 24),
  _ValidCase('subset/37 - 20 bit per sample.flac',
      channels: 2, sampleRate: 96000, bitsPerSample: 20),
  _ValidCase('subset/41 - 6 channels (5.1).flac',
      channels: 6, sampleRate: 44100, bitsPerSample: 16),
  _ValidCase('subset/47 - only STREAMINFO.flac',
      channels: 2, sampleRate: 48000, bitsPerSample: 16),
  _ValidCase('subset/60 - mono audio.flac',
      channels: 1, sampleRate: 44100, bitsPerSample: 16),
  _ValidCase('uncommon/05 - 32bps audio.flac',
      channels: 2, sampleRate: 44100, bitsPerSample: 32),
];

const _faultyFile = 'faulty/10 - invalid vorbis comment metadata block.flac';

void main() {
  if (!curatedFilesPresent) {
    test('curated conformance files not fetched', () {},
        skip: 'Run tool/fetch_conformance.sh to download the curated CELLAR '
            'testbench files (~12 MB).');
    return;
  }

  group('CELLAR curated conformance set', () {
    for (final c in _validCases) {
      group(c.path, () {
        test('STREAMINFO matches manifest', () {
          final reader = FlacReader.fromFileSync('$conformanceDir/${c.path}');
          expect(reader.streamInfo.channels, equals(c.channels));
          expect(reader.streamInfo.sampleRate, equals(c.sampleRate));
          expect(reader.streamInfo.bitsPerSample, equals(c.bitsPerSample));
        });

        test('decodes with MD5 match', () {
          expect(verifyFile('$conformanceDir/${c.path}'),
              equals(Md5VerificationResult.match));
        });
      });
    }

    test('invalid vorbis comment block is rejected with FormatException', () {
      expect(() => FlacReader.fromFileSync('$conformanceDir/$_faultyFile'),
          throwsFormatException);
    });
  });
}
```

- [ ] **Step 3: Verify the skip path (files absent)**

Run: `mv test/fixtures/conformance /tmp/conformance-stash && dart test test/conformance_test.dart; mv /tmp/conformance-stash test/fixtures/conformance`
Expected: the run in the middle reports 1 test skipped ("curated conformance files not fetched"), 0 failures — plain `dart test` stays green with nothing fetched.

- [ ] **Step 4: Run the curated tests against real files**

Run: `dart test -t conformance`
Expected: PASS — 19 tests (9 × STREAMINFO + 9 × MD5 + 1 faulty rejection), 0 skipped.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add test/support/conformance.dart test/conformance_test.dart
git commit -m "Add curated CELLAR conformance tests behind conformance tag"
```

---

### Task 4: Full testbench sweep

**Files:**
- Create: `test/conformance_full_test.dart`

**Interfaces:**
- Consumes: `conformanceDir`, `fullSetPresent`, `verifyFile` from `test/support/conformance.dart` (Task 3); full testbench layout from Task 2's `--full` mode.
- Produces: nothing consumed later.

- [ ] **Step 1: Write the sweep test file**

Create `test/conformance_full_test.dart`:

```dart
@Tags(['conformance-full'])
library;

import 'dart:io';

import 'package:dart_flac/dart_flac.dart';
import 'package:test/test.dart';

import 'support/conformance.dart';

/// Baseline behaviour probed on 2026-07-19 against testbench commit aa7b0c6:
/// the decoder passes the entire testbench. These tests lock that in — any
/// deviation (new failure OR new leniency) is a visible behaviour change.

/// Rejected by design: the reader requires the stream to start with the
/// `fLaC` marker.
const _expectedRejects = {
  'uncommon/10 - file starting at frame header.flac',
  'uncommon/11 - file starting with unparsable data.flac',
};

/// Streams whose parameters change mid-stream carry no STREAMINFO MD5.
const _noMd5 = {
  'uncommon/01 - changing samplerate.flac',
  'uncommon/02 - increasing number of channels.flac',
  'uncommon/03 - decreasing number of channels.flac',
  'uncommon/04 - changing bitdepth.flac',
};

/// Exact expected outcome per faulty file: 'reject' means FormatException,
/// otherwise the Md5VerificationResult name. Files 01/02/04/05/08/09 carry
/// faults only in STREAMINFO consistency fields the decoder tolerates;
/// 03 decodes at the frame's real bit depth, surfaced as an MD5 mismatch.
const _faultyBaseline = {
  '01 - wrong max blocksize.flac': 'match',
  '02 - wrong maximum framesize.flac': 'match',
  '03 - wrong bit depth.flac': 'mismatch',
  '04 - wrong number of channels.flac': 'match',
  '05 - wrong total number of samples.flac': 'match',
  '06 - missing streaminfo metadata block.flac': 'reject',
  '07 - other metadata blocks preceding streaminfo metadata block.flac':
      'reject',
  '08 - blocksize 65536.flac': 'match',
  '09 - blocksize 1.flac': 'match',
  '10 - invalid vorbis comment metadata block.flac': 'reject',
  '11 - incorrect metadata block length.flac': 'reject',
};

List<String> _flacFiles(String subdir) =>
    Directory('$conformanceDir/$subdir')
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((name) => name.endsWith('.flac'))
        .toList()
      ..sort();

void main() {
  if (!fullSetPresent) {
    test('full testbench not fetched', () {},
        skip: 'Run tool/fetch_conformance.sh --full to download the complete '
            'CELLAR testbench (~201 MB).');
    return;
  }

  group('CELLAR sweep: subset', () {
    for (final name in _flacFiles('subset')) {
      test(name, () {
        expect(verifyFile('$conformanceDir/subset/$name'),
            equals(Md5VerificationResult.match));
      });
    }
  });

  group('CELLAR sweep: uncommon', () {
    for (final name in _flacFiles('uncommon')) {
      test(name, () {
        if (_expectedRejects.contains('uncommon/$name')) {
          expect(() => verifyFile('$conformanceDir/uncommon/$name'),
              throwsFormatException);
        } else {
          final expected = _noMd5.contains('uncommon/$name')
              ? Md5VerificationResult.notComputed
              : Md5VerificationResult.match;
          expect(
              verifyFile('$conformanceDir/uncommon/$name'), equals(expected));
        }
      });
    }
  });

  group('CELLAR sweep: faulty', () {
    for (final name in _flacFiles('faulty')) {
      test(name, () {
        final expected = _faultyBaseline[name];
        expect(expected, isNotNull,
            reason: 'New faulty file needs a baseline entry: $name');
        if (expected == 'reject') {
          expect(() => verifyFile('$conformanceDir/faulty/$name'),
              throwsFormatException);
        } else {
          expect(verifyFile('$conformanceDir/faulty/$name').name,
              equals(expected));
        }
      });
    }
  });
}
```

- [ ] **Step 2: Verify the skip path (full set absent)**

The working tree currently has only the ten curated files, so:

Run: `dart test test/conformance_full_test.dart`
Expected: 1 skipped ("full testbench not fetched"), 0 failures.

- [ ] **Step 3: Fetch the full testbench**

Run: `./tool/fetch_conformance.sh --full`
Expected: tarball download (~201 MB) then "Extracted full testbench…". Verify: `find test/fixtures/conformance -name '*.flac' | wc -l` → `86` (64 subset + 11 uncommon + 11 faulty).

- [ ] **Step 4: Run the sweep**

Run: `dart test -t conformance-full`
Expected: PASS — 86 tests (64 subset + 11 uncommon + 11 faulty), matching the probed baseline exactly. Takes a couple of minutes (296 MB of audio).

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add test/conformance_full_test.dart
git commit -m "Add full CELLAR testbench sweep behind conformance-full tag"
```

---

### Task 5: CI wiring

**Files:**
- Modify: `.github/workflows/ci.yml` (append a `conformance` job after the existing `test` job)
- Create: `.github/workflows/conformance-full.yml`

**Interfaces:**
- Consumes: `tool/fetch_conformance.sh` (Task 2), tags `conformance` / `conformance-full` (Tasks 3–4).
- Produces: nothing consumed later.

- [ ] **Step 1: Add the conformance job to ci.yml**

Append to `.github/workflows/ci.yml` (same indentation level as the existing `test:` job; keep the SDK pinned to the same version, `3.11.5`):

```yaml
  conformance:
    runs-on: ubuntu-latest

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up Dart
        uses: dart-lang/setup-dart@v1
        with:
          # Keep in lockstep with the `test` job's pin.
          sdk: 3.11.5

      - name: Install dependencies
        run: dart pub get

      - name: Cache curated CELLAR files
        uses: actions/cache@v4
        with:
          path: test/fixtures/conformance
          # Keep in lockstep with SHA in tool/fetch_conformance.sh.
          key: cellar-curated-aa7b0c6cf32994c106ae517a08134c28a96ff5b2

      - name: Fetch curated CELLAR files
        # No-op on cache hit (the script skips files already present).
        run: ./tool/fetch_conformance.sh

      - name: Conformance tests
        run: dart test -t conformance
```

- [ ] **Step 2: Create the manual full-sweep workflow**

Create `.github/workflows/conformance-full.yml`:

```yaml
name: Conformance (full testbench)

# Manual only: downloads the complete ~201 MB CELLAR testbench and runs the
# whole-testbench sweep. Trigger from the Actions tab when validating decoder
# changes or bumping the pinned testbench SHA.
on:
  workflow_dispatch:

jobs:
  conformance-full:
    runs-on: ubuntu-latest

    steps:
      - name: Check out repository
        uses: actions/checkout@v4

      - name: Set up Dart
        uses: dart-lang/setup-dart@v1
        with:
          # Keep in lockstep with ci.yml's pin.
          sdk: 3.11.5

      - name: Install dependencies
        run: dart pub get

      - name: Fetch full CELLAR testbench
        run: ./tool/fetch_conformance.sh --full

      - name: Full testbench sweep
        run: dart test -t conformance-full
```

- [ ] **Step 3: Validate workflow syntax locally**

Run: `dart pub get >/dev/null; python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/workflows/conformance-full.yml')); print('YAML OK')"`
Expected: `YAML OK` (if PyYAML is unavailable, `gh workflow list` after push is the fallback check).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml .github/workflows/conformance-full.yml
git commit -m "Run curated conformance tests in CI; add manual full-sweep workflow"
```

---

### Task 6: Documentation and final verification

**Files:**
- Modify: `README.md` (Development section, after the fixture-regeneration paragraph ending at line 176)
- Modify: `CLAUDE.md` (Commands section) — add the two conformance commands

**Interfaces:**
- Consumes: everything above.
- Produces: final verified branch.

- [ ] **Step 1: Document the conformance tiers in README.md**

Insert after the paragraph ending "…stays visible next to the assertions." (README.md:176):

```markdown
Conformance tests against the official [IETF CELLAR FLAC testbench](https://github.com/ietf-wg-cellar/flac-test-files)
(CC0) are tagged and self-skip unless the files have been fetched:

```sh
./tool/fetch_conformance.sh            # curated set (~12 MB)
dart test -t conformance

./tool/fetch_conformance.sh --full     # complete testbench (~201 MB)
dart test -t conformance-full
```

The curated set runs in CI on every pull request; the full sweep is a
manually triggered workflow (Actions → "Conformance (full testbench)").
Downloads land in `test/fixtures/conformance/`, which is gitignored.
```

(Note: nested code fences — use four backticks for the outer fence when inserting, or match the file's existing style; README currently uses plain triple-backtick blocks, so insert the prose and the `sh` block as siblings, not nested.)

- [ ] **Step 2: Add the commands to CLAUDE.md**

In the Commands block of `CLAUDE.md`, after the `dart test --name 'reads Rice-coded'` line, add:

```sh
./tool/fetch_conformance.sh           # fetch curated CELLAR conformance files (~12 MB)
dart test -t conformance              # conformance tests (self-skip if not fetched)
./tool/fetch_conformance.sh --full    # fetch complete testbench (~201 MB)
dart test -t conformance-full         # whole-testbench sweep
```

- [ ] **Step 3: Full local verification**

Run each and confirm:

```sh
dart format --set-exit-if-changed .   # no changes
dart analyze                          # no issues
dart test                             # all pass (conformance tests run too if files are still present locally)
dart test -t conformance              # 19 pass
dart test -t conformance-full         # 86 pass
dart pub publish --dry-run            # package validates; conformance files NOT in the archive
```

For the publish dry-run, check the printed file list does not contain `test/fixtures/conformance`.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "Document conformance test tiers"
```

- [ ] **Step 5: Push and open PR**

```bash
git push -u origin issue-21-conformance-tests
gh pr create --title "Extended conformance tests using official CELLAR FLAC files" --body "$(cat <<'EOF'
Closes #21.

- Three new local fixtures on every `dart test`: 20-bit stereo, 5.1 surround, 32-bit mono.
- Curated 10-file slice of the official IETF CELLAR testbench behind `dart test -t conformance` (fetched by `tool/fetch_conformance.sh`, ~12 MB, gitignored, cached in CI, runs on every PR).
- Whole-testbench sweep (86 files) behind `dart test -t conformance-full`, run via a manual workflow.
- Probed baseline: the decoder already passes the entire testbench (all subset + uncommon files MD5-verified; faulty files rejected with clean `FormatException` or tolerated with the fault surfaced). The sweep locks that baseline in.

Design: docs/superpowers/specs/2026-07-19-conformance-tests-design.md
EOF
)"
```

Expected: PR opens; the new `conformance` CI job appears alongside `test` and passes (first run downloads 12 MB, later runs hit the cache).
