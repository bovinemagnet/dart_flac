// Browser smoke test: proves dart_flac compiles under dart2js/dart2wasm
// and `decodeFlacBytesToPcm` works end-to-end in a browser.
//
// Run locally with:  dart test -p chrome test/web_smoke_test.dart
//
// The fixture is the same inline `_minimalFlac` byte buffer used by the
// native test suite — duplicated here so this file has no `dart:io` or
// filesystem dependency.
@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:dart_flac/dart_flac.dart';
import 'package:test/test.dart';

import 'support/synthetic_frames.dart';

/// Minimal valid FLAC (see test/dart_flac_test.dart for the annotated
/// byte layout). Two frames of 4 stereo 16-bit samples each.
final Uint8List _minimalFlac = Uint8List.fromList([
  // "fLaC" marker
  0x66, 0x4c, 0x61, 0x43,
  // STREAMINFO header: is_last=1, type=0, length=34
  0x80, 0x00, 0x00, 0x22,
  // STREAMINFO data: 44100 Hz, 2 ch, 16-bit, 8 total samples, md5=0
  0x00, 0x04, 0x00, 0x04,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x0a, 0xc4, 0x42, 0xf0,
  0x00, 0x00, 0x00, 0x08,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  // Frame 0: leftSide stereo, constant subframes → left=1000, right=-500
  0xff, 0xf8, 0x69, 0x88, 0x00, 0x03, 0x1f,
  0x00, 0x03, 0xe8, 0x00, 0x02, 0xee, 0x00, 0xca, 0xa8,
  // Frame 1: two independent constant subframes → left=0, right=0
  0xff, 0xf8, 0x69, 0x18, 0x01, 0x03, 0xa3,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x58, 0x5e,
]);

void main() {
  test('FlacReader.fromBytes parses metadata in a browser', () {
    final reader = FlacReader.fromBytes(_minimalFlac);
    expect(reader.streamInfo.sampleRate, equals(44100));
    expect(reader.streamInfo.channels, equals(2));
    expect(reader.streamInfo.bitsPerSample, equals(16));
  });

  test('decodeFlacBytesToPcm returns 16-bit LE PCM in a browser', () {
    final pcm = decodeFlacBytesToPcm(_minimalFlac);
    // 8 samples × 2 channels × 2 bytes (16-bit) = 32.
    expect(pcm.length, equals(32));
    // First sample pair = (1000, -500) as int16 LE = E8 03, 0C FE.
    expect(pcm[0], equals(0xE8));
    expect(pcm[1], equals(0x03));
    expect(pcm[2], equals(0x0C));
    expect(pcm[3], equals(0xFE));
  });

  // The tests below exercise decoder arithmetic outside the range that
  // JavaScript bitwise operators can represent (dart2js canonicalises
  // bitwise results to unsigned 32-bit, so the danger zone is values at
  // or above 2^32, or below -2^31). The VM handles these natively; they
  // only fail when compiled to JavaScript.

  test('mid/side decorrelation is exact for large negative samples', () {
    // right < -2^30 makes the doubled value in the side reconstruction
    // cross -2^31, where a JavaScript arithmetic shift wraps.
    final left = 0;
    final right = -(pow2(30) + 1);
    final mid = -(pow2(29) + 1); // (left + right) >> 1, floored
    final side = left - right;
    final bytes = buildFlacFromStreamInfoAndFrames(
      sampleRate: 44100,
      channels: 2,
      bitsPerSample: 32,
      totalSamples: 4,
      frames: [buildConstantMidSideFrame32(mid: mid, side: side, blockSize: 4)],
    );
    final frame = FlacReader.fromBytes(bytes).decodeFrames().single;
    expect(frame.channelSamples[0], everyElement(equals(left)));
    expect(frame.channelSamples[1], everyElement(equals(right)));
  });

  test('LPC prediction is exact when the accumulator crosses -2^31', () {
    // warm-up -(2^30)-1, coefficient 2, shift 1: every predicted sample is
    // (2 * previous) >> 1 = previous, but the intermediate sum is below
    // -2^31 where a JavaScript arithmetic shift wraps.
    final warmUp = -(pow2(30) + 1);
    final bytes = buildFlacFromStreamInfoAndFrames(
      sampleRate: 44100,
      channels: 1,
      bitsPerSample: 32,
      totalSamples: 4,
      frames: [
        buildLpcMonoFrame32(
            warmUp: warmUp, coefficient: 2, shift: 1, blockSize: 4),
      ],
    );
    final frame = FlacReader.fromBytes(bytes).decodeFrames().single;
    expect(frame.channelSamples[0], everyElement(equals(warmUp)));
  });

  test('Rice2 side-channel residuals beyond 2^32 decode exactly', () {
    // A 33-bit side sample zigzag-encodes to 2^32 + 10, past the unsigned
    // 32-bit ceiling of JavaScript bitwise operators.
    final left = pow2(31) - 1;
    final side = pow2(31) + 5;
    final bytes = buildFlacFromStreamInfoAndFrames(
      sampleRate: 44100,
      channels: 2,
      bitsPerSample: 32,
      totalSamples: 2,
      frames: [
        buildLeftSideRice2Frame32(
            left: left, sideValues: [side, 0], riceParam: 30),
      ],
    );
    final frame = FlacReader.fromBytes(bytes).decodeFrames().single;
    expect(frame.channelSamples[0], equals([left, left]));
    expect(frame.channelSamples[1], equals([left - side, left]));
  });

  test('PICTURE dimensions with the high bit set parse as unsigned', () {
    final bytes = buildFlacWithPicture(width: 0x90000000, height: 1);
    final reader = FlacReader.fromBytes(bytes);
    expect(reader.pictures.single.width, equals(0x90000000));
    expect(reader.pictures.single.height, equals(1));
  });
}
