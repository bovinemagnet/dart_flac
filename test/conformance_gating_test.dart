@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Checks how the conformance suites behave when their files are missing or
/// incomplete, by running them in a child `dart test` pointed at a fixtures
/// directory this test controls (FLAC_CONFORMANCE_DIR).
final _sha = RegExp(r'^SHA=(\w+)$', multiLine: true)
    .firstMatch(File('tool/fetch_conformance.sh').readAsStringSync())![1]!;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('conformance_gating_'));
  tearDown(() => dir.deleteSync(recursive: true));

  ProcessResult runSuite(String file,
          {bool optIn = false, bool required = false}) =>
      Process.runSync(
        Platform.resolvedExecutable,
        [
          'test',
          '-r',
          'expanded',
          if (optIn) ...['-P', 'conformance-full'],
          file,
        ],
        environment: {
          'FLAC_CONFORMANCE_DIR': dir.path,
          'FLAC_CONFORMANCE_REQUIRED': required ? 'true' : '',
        },
      );

  const curated = 'test/conformance_test.dart';
  const full = 'test/conformance_full_test.dart';

  test('curated suite skips when its files have not been fetched', () {
    final result = runSuite(curated);
    expect(result.exitCode, equals(0), reason: '${result.stdout}');
    expect(result.stdout, contains('All tests skipped.'));
  });

  test('full sweep skips when the testbench has not been fetched', () {
    final result = runSuite(full, optIn: true);
    expect(result.exitCode, equals(0), reason: '${result.stdout}');
    expect(result.stdout, contains('All tests skipped.'));
  });

  test('curated suite fails when files are missing and required', () {
    final result = runSuite(curated, required: true);
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(
        result.stdout, contains('curated conformance files not fetched [E]'));
  });

  test('full sweep fails when the testbench is missing and required', () {
    final result = runSuite(full, optIn: true, required: true);
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(result.stdout, contains('full testbench not fetched [E]'));
  });

  test('full sweep fails when the fetched testbench is incomplete', () {
    // A marker for the pinned SHA but no files, as after files were deleted
    // or a SHA bump without re-triage.
    File('${dir.path}/.full-$_sha').createSync(recursive: true);
    final result = runSuite(full, optIn: true);
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(result.stdout, contains('testbench is complete [E]'));
  });

  test('plain dart test does not run the full sweep', () {
    // The same incomplete testbench: running the sweep would fail.
    File('${dir.path}/.full-$_sha').createSync(recursive: true);
    final result = runSuite(full);
    expect(result.exitCode, equals(0), reason: '${result.stdout}');
    expect(result.stdout, contains('All tests skipped.'));
  });
}
