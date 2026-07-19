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

List<String> _flacFiles(String subdir) => Directory('$conformanceDir/$subdir')
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
