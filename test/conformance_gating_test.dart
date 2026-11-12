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

  ProcessResult runSuites({bool required = false}) => Process.runSync(
        Platform.resolvedExecutable,
        [
          'test',
          '-r',
          'expanded',
          'test/conformance_test.dart',
          'test/conformance_full_test.dart',
        ],
        environment: {
          'FLAC_CONFORMANCE_DIR': dir.path,
          'FLAC_CONFORMANCE_REQUIRED': required ? 'true' : '',
        },
      );

  test('suites skip when the files have not been fetched', () {
    final result = runSuites();
    expect(result.exitCode, equals(0), reason: '${result.stdout}');
    expect(result.stdout, contains('All tests skipped.'));
  });

  test(
      'suites fail when files are missing and FLAC_CONFORMANCE_REQUIRED is set',
      () {
    final result = runSuites(required: true);
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(
        result.stdout,
        allOf(contains('curated conformance files not fetched [E]'),
            contains('full testbench not fetched [E]')));
  });

  test('full sweep fails when the fetched testbench is incomplete', () {
    // A marker for the pinned SHA but no files, as after files were deleted
    // or a SHA bump without re-triage.
    File('${dir.path}/.full-$_sha').createSync(recursive: true);
    final result = runSuites();
    expect(result.exitCode, isNot(0), reason: '${result.stdout}');
    expect(result.stdout, contains('testbench is complete [E]'));
  });
}
