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
