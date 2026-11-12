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

/// Streams whose parameters change mid-stream carry no STREAMINFO MD5, so
/// verifyMd5() never decodes them. Expected frame and per-channel sample
/// counts, recorded against testbench commit aa7b0c6.
const _noMd5 = {
  'uncommon/01 - changing samplerate.flac': (frames: 136, samples: 555747),
  'uncommon/02 - increasing number of channels.flac': (
    frames: 156,
    samples: 638856
  ),
  'uncommon/03 - decreasing number of channels.flac': (
    frames: 92,
    samples: 375226
  ),
  'uncommon/04 - changing bitdepth.flac': (frames: 121, samples: 495232),
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

/// Number of .flac files per directory at the pinned testbench commit.
const _expectedFileCounts = {'subset': 64, 'uncommon': 11, 'faulty': 11};

/// Sorted .flac file names in [subdir]; empty if the directory is missing,
/// so an incomplete testbench fails 'testbench is complete' rather than
/// breaking test registration.
List<String> _flacFiles(String subdir) {
  final dir = Directory('$conformanceDir/$subdir');
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((name) => name.endsWith('.flac'))
      .toList()
    ..sort();
}

void main() {
  if (!fullSetPresent) {
    filesNotFetched(
        'full testbench not fetched',
        'Run tool/fetch_conformance.sh --full to download the complete '
            'CELLAR testbench (~201 MB).');
    return;
  }

  // The sweep is built from the files on disk, so a missing file would
  // silently shrink it. Pin the exact contents instead; a SHA bump that
  // changes them must re-triage the baselines above.
  test('testbench is complete', () {
    for (final MapEntry(key: subdir, value: count)
        in _expectedFileCounts.entries) {
      expect(_flacFiles(subdir), hasLength(count),
          reason: 'Unexpected number of files in $subdir/. Re-run '
              'tool/fetch_conformance.sh --full, or re-triage the baselines '
              'after a SHA bump.');
    }
    final baselinePaths = [
      ..._expectedRejects,
      ..._noMd5.keys,
      for (final name in _faultyBaseline.keys) 'faulty/$name',
    ];
    for (final path in baselinePaths) {
      expect(File('$conformanceDir/$path').existsSync(), isTrue,
          reason: 'Baseline entry has no file: $path');
    }
  });

  group('CELLAR sweep: subset', () {
    for (final name in _flacFiles('subset')) {
      test(name, () async {
        final path = '$conformanceDir/subset/$name';
        expect(verifyFile(path), equals(Md5VerificationResult.match));
        expectPathsAgree(await decodeEveryWay(path));
      });
    }
  });

  group('CELLAR sweep: uncommon', () {
    for (final name in _flacFiles('uncommon')) {
      test(name, () async {
        final path = '$conformanceDir/uncommon/$name';
        if (_expectedRejects.contains('uncommon/$name')) {
          expect(() => verifyFile(path), throwsFormatException);
          return;
        }
        final counts = _noMd5['uncommon/$name'];
        expect(
            verifyFile(path),
            equals(counts == null
                ? Md5VerificationResult.match
                : Md5VerificationResult.notComputed));
        final report = await decodeEveryWay(path);
        expectPathsAgree(report);
        if (counts != null) {
          expect(report.frames, equals(counts.frames));
          expect(report.samplesPerChannel, equals(counts.samples));
        }
      });
    }
  });

  group('CELLAR sweep: faulty', () {
    for (final name in _flacFiles('faulty')) {
      test(name, () async {
        final path = '$conformanceDir/faulty/$name';
        final expected = _faultyBaseline[name];
        expect(expected, isNotNull,
            reason: 'New faulty file needs a baseline entry: $name');
        if (expected == 'reject') {
          expect(() => verifyFile(path), throwsFormatException);
          // The streaming decoder has no up-front validation: it may decode
          // the stream, but any failure must be a FormatException.
          try {
            await streamingFingerprint(File(path).readAsBytesSync());
          } on FormatException {
            // Rejected cleanly.
          }
        } else {
          expect(verifyFile(path).name, equals(expected));
          expectPathsAgree(await decodeEveryWay(path));
        }
      });
    }
  });
}
