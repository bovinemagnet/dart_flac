# dart_flac

A pure-Dart FLAC (Free Lossless Audio Codec) decoder. No native
dependencies, no FFI, no platform-specific code — it reads FLAC files
or byte streams and gives you back PCM samples that you can hand to any
audio sink.

## Features

- Full metadata parsing: STREAMINFO, PADDING, APPLICATION, SEEKTABLE,
  VORBIS_COMMENT, CUESHEET, PICTURE (and graceful handling of unknown
  block types).
- Complete frame decoding: CONSTANT, VERBATIM, FIXED (orders 0–4), and
  LPC (orders 1–32) subframes; both residual coding methods
  (PARTITIONED_RICE / PARTITIONED_RICE2) including the escape partition;
  all three joint-stereo modes (left/side, right/side, mid/side).
- CRC-8 and CRC-16 frame validation, plus end-to-end MD5 verification
  against the STREAMINFO signature.
- Real-world tolerance: skips leading ID3v2 tags; optional resync on
  corrupted frames.
- Random access: `byteOffsetForSample` / `decodeFramesFromSample` use
  SEEKTABLE when present, fall back to a frame-header walk otherwise.
- **Two streaming APIs** for audio playback consumers:
  - **Pull** — `FlacReader.pcmChunks()` returns an `Iterable<Uint8List>`
    that decodes one frame per pull.
  - **Push** — `StreamingFlacDecoder` accepts bytes via `addBytes()`
    and emits a `Stream<Uint8List>` of PCM chunks. Works on top of
    chunked HTTP responses, sockets, or any other `Stream<List<int>>`.
- `writeWavBytes()` helper and `dart run dart_flac:flac2wav` CLI for
  FLAC→WAV conversion.

## Install

```yaml
dependencies:
  dart_flac: ^0.0.1
```

## Quick start

### Read a file and inspect metadata

```dart
import 'package:dart_flac/dart_flac.dart';

final reader = await FlacReader.fromFile('track.flac');
print(reader.streamInfo); // sample rate, channels, bps, duration
print(reader.vorbisComment?.title);

// End-to-end correctness check.
assert(reader.verifyMd5() == Md5VerificationResult.match);
```

### Decode and feed a PCM-accepting player (pull)

```dart
final reader = await FlacReader.fromFile('track.flac');
final info = reader.streamInfo;
await player.start(
  sampleRate: info.sampleRate,
  channels: info.channels,
  bitsPerSample: 16,
);
for (final chunk in reader.pcmChunks(outputBitsPerSample: 16)) {
  player.feed(chunk);  // chunk is interleaved signed LE PCM
}
```

### Decode from a network stream (push)

```dart
final decoder = StreamingFlacDecoder();

// Configure the player as soon as STREAMINFO arrives.
decoder.onStreamInfo.then((info) {
  player.start(
    sampleRate: info.sampleRate,
    channels: info.channels,
    bitsPerSample: 16,
  );
});

decoder.pcmStream(outputBitsPerSample: 16).listen(player.feed);

await for (final chunk in httpResponse.body) {
  decoder.addBytes(chunk);
}
decoder.close();
```

### Seek to a sample and decode from there

```dart
final reader = await FlacReader.fromFile('track.flac');
final thirtySeconds = reader.streamInfo.sampleRate * 30;
for (final frame in reader.decodeFramesFromSample(thirtySeconds)) {
  // …
}
```

### Decode inside an isolate (background thread)

When you want decoding off the UI thread — e.g. analysing a track while
the user scrolls a library — use the isolate-safe top-level helper. It
takes only a path and returns only bytes, so nothing stateful crosses
the isolate boundary:

```dart
import 'dart:isolate';
import 'package:dart_flac/dart_flac.dart';

final pcm = await Isolate.run(
  () => decodeFlacFileToPcm('track.flac', outputBitsPerSample: 16),
);
```

A byte-based companion — `decodeFlacBytesToPcm(flacBytes)` — works the
same way and runs on web, where `dart:io` isn't available.

### Convert FLAC to WAV

```dart
final reader = await FlacReader.fromFile('track.flac');
final wav = writeWavBytes(
  frames: reader.decodeFrames(),
  sampleRate: reader.streamInfo.sampleRate,
  channels: reader.streamInfo.channels,
  bitsPerSample: reader.streamInfo.bitsPerSample,
);
await File('track.wav').writeAsBytes(wav);
```

Or via the installed CLI:

```sh
dart run dart_flac:flac2wav --verify track.flac track.wav
```

## Examples

See [`example/`](example/) for runnable programs covering the full API
surface.

## Platforms

Pure Dart, no FFI, no conditional compilation. Runs on the Dart VM
(CLI, server), AOT, Flutter (mobile and desktop), and the **web**
(`dart compile js`, Flutter web). On web, use `FlacReader.fromBytes`
or `StreamingFlacDecoder` with bytes from a fetch/HTTP response or a
`<input type="file">` upload — `FlacReader.fromFile` throws
`UnsupportedError` on web because `dart:io` isn't available there.

Spec-defined 64-bit fields (`SeekPoint.sampleNumber`, `streamOffset`,
`CueSheetTrack.trackOffset`, `CueSheetTrackIndex.offset`,
`CueSheetBlock.leadInSamples`) are exposed as [`Int64`][fixnum] from
`package:fixnum` rather than `int`, so they keep full precision on
the web (where Dart's native `int` is a JavaScript `Number` limited
to 2^53). Call `.toInt()` when you need a plain `int`.

[fixnum]: https://pub.dev/packages/fixnum

## Performance

Benchmark harness at [`benchmark/decode_benchmark.dart`](benchmark/decode_benchmark.dart).
Each operation runs in a fresh subprocess so `ProcessInfo.maxRss` is a
clean high-water mark. Fixture is a reproducible 3-minute stereo 16-bit
44100 Hz FLAC with sine waves + low-amplitude noise (generated via
`benchmark/generate_fixture.sh 180`) — the noise defeats the
CONSTANT-subframe fast path and forces the encoder to pick LPC, which
is the hot path in real-world music.

### Desktop baseline (AOT)

Intel Core Ultra 7 155U, Linux, Dart 3.11.5, `dart compile exe`:

| Operation                  | Median (ms) | × realtime | Peak RSS (MB) |
|----------------------------|-------------|------------|---------------|
| `decodeInterleavedSamples` |         787 |        229 |           243 |
| `pcmChunks` (lazy, 16-bit) |         749 |        240 |            32 |
| `decodeFlacFileToPcm`      |         859 |        210 |           121 |

Reference: the native `flac` CLI decodes the same fixture in ~150 ms
(~1200× realtime), so dart_flac is ~5× slower than C, which is the
upper end of the "2–5× native" range typical for pure-Dart codecs.

### Takeaways

- **Streaming (`pcmChunks`) is the right shape for long tracks.** The
  full-buffer path keeps the decoded PCM in a giant `Int32List`
  (180 s × 44100 × 2 ch × 4 B ≈ 120 MB), so RSS scales with audio
  duration. The streaming path releases each frame's buffer once the
  caller has consumed it — peak RSS stays ~constant at roughly
  `encoded_file + one frame`. At a 60-minute album, the full-buffer
  approach would need ~2.4 GB of RAM for PCM alone and will OOM on
  most mid-tier Android devices. Streaming stays bounded.
- **Throughput is CPU-bound, not I/O-bound.** On Android, single-
  threaded CPU is typically 3–5× slower than a laptop x86-64 core;
  extrapolating, expect ~50–80× realtime on a mid-tier 2023+ device.
  A 60-minute album should decode in roughly 45–75 s on a Snapdragon
  7 Gen 1 class chip. Run the benchmark on your target hardware for
  actual numbers — see below.
- **JIT mode is ~25% slower than AOT.** Always benchmark in release
  mode (`dart compile exe`, or Flutter's `--release`), not `dart run`.

### Reproducing on Android

Two options:

1. **Flutter integration test** — drop the library into a Flutter app,
   copy `benchmark/decode_benchmark.dart`'s worker logic into an
   `integration_test/` test, run with
   `flutter test integration_test/decode_benchmark_test.dart --release`
   on a connected device.
2. **Standalone binary** via `flutter build apk --release` with an
   in-app "Run benchmark" button that calls `decodeFlacFileToPcm` on
   a bundled asset and renders the results.

In either case the timing code and the memory probe
(`ProcessInfo.maxRss` on native, `Memory.getSize` via platform channel
for a more accurate Android-PSS reading) are the same as the desktop
harness.

### Community device results

Real-device numbers contributed by users. Each cell is
`× realtime / peak memory (MB)` for a 3-minute stereo 16-bit 44100 Hz
fixture. Open a PR adding your row if your hardware isn't listed — use
`benchmark/format_community_row.dart` to produce a row in the canonical
format so cells line up with the ones below.

| Device / CPU           | OS / Dart            | Mode | `decodeInterleavedSamples` | `pcmChunks` | `decodeFlacFileToPcm` |
|------------------------|----------------------|------|----------------------------|-------------|-----------------------|
| _(no submissions yet)_ |                      |      |                            |             |                       |

How to contribute a row:

1. Run the benchmark on your device — either the desktop CLI
   (`dart run benchmark/decode_benchmark.dart`) or the Flutter
   integration-test harness sketched above.
2. Feed the medians into `formatCommunityRow(...)` from
   `benchmark/format_community_row.dart` and print the result.
3. Paste the printed line into the table above and open a PR.

## Non-goals

- **Audio playback.** This library emits PCM; it does not drive a
  sound card. Pair it with `flutter_sound`, `flutter_soloud`,
  `dart:ffi` + PortAudio / SDL / miniaudio, `AudioContext` from
  `package:web`, or any other PCM-accepting sink.
- **Encoding.** Decoder only.
- **Ogg-FLAC container.** Only native FLAC (`fLaC` marker) streams are
  parsed.

## License

See [`LICENSE`](LICENSE).
