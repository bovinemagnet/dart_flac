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
}
