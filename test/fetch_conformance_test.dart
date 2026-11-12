@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:test/test.dart';

/// Tests for tool/fetch_conformance.sh. Each test runs a copy of the script
/// inside a temporary directory (the script resolves paths from its own
/// location), with a stub `curl` on PATH that records its arguments and
/// fakes the downloads, so neither the network nor the real fixtures are
/// touched.
final _script = File('tool/fetch_conformance.sh').readAsStringSync();

final _sha = RegExp(r'^SHA=(\w+)$', multiLine: true).firstMatch(_script)![1]!;

final _curated = RegExp(r'"([^"]+\.flac)"')
    .allMatches(
        RegExp(r'CURATED=\((.*?)\n\)', dotAll: true).firstMatch(_script)![1]!)
    .map((m) => m[1]!)
    .toList();

const _stubCurl = r'''#!/usr/bin/env bash
echo "$*" >> "$CURL_LOG"
out=
for ((i = 1; i <= $#; i++)); do
  if [[ "${!i}" == -o ]]; then j=$((i + 1)); out="${!j}"; fi
done
url="${!#}"
if [[ "$url" == *codeload* ]]; then
  tar -czf "${out:-/dev/stdout}" -C "$STUB_TARBALL_ROOT" flac-test-files
else
  echo "fetched $url" > "$out"
fi
''';

void main() {
  late Directory root;
  late String dest;

  ProcessResult fetch([List<String> args = const []]) => Process.runSync(
        'bash',
        ['${root.path}/tool/fetch_conformance.sh', ...args],
        environment: {
          'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
          'CURL_LOG': '${root.path}/curl.log',
          'STUB_TARBALL_ROOT': '${root.path}/upstream',
        },
      );

  List<String> curlCalls() {
    final log = File('${root.path}/curl.log');
    if (!log.existsSync()) return [];
    final calls = log.readAsLinesSync();
    log.deleteSync();
    return calls;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fetch_conformance_');
    dest = '${root.path}/test/fixtures/conformance';
    File('${root.path}/tool/fetch_conformance.sh')
      ..createSync(recursive: true)
      ..writeAsStringSync(_script);
    final curl = File('${root.path}/bin/curl')
      ..createSync(recursive: true)
      ..writeAsStringSync(_stubCurl);
    Process.runSync('chmod', ['+x', curl.path]);
    File('${root.path}/upstream/flac-test-files/subset/a.flac')
      ..createSync(recursive: true)
      ..writeAsStringSync('upstream');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('rejects an unknown argument without downloading', () {
    final result = fetch(['--ful']);
    expect(result.exitCode, isNot(0));
    expect(result.stderr, contains('Usage'));
    expect(curlCalls(), isEmpty);
  });

  test('curated fetch retries transient download failures', () {
    expect(fetch().exitCode, equals(0), reason: 'fetch failed');
    final calls = curlCalls();
    expect(calls, hasLength(_curated.length));
    expect(calls, everyElement(contains('--retry')));
  });

  test('full fetch retries transient download failures', () {
    expect(fetch(['--full']).exitCode, equals(0), reason: 'fetch failed');
    expect(curlCalls(), [contains('--retry')]);
    expect(File('$dest/subset/a.flac').readAsStringSync(), equals('upstream'));
  });

  test('curated fetch is a no-op once the pinned revision is present', () {
    expect(fetch().exitCode, equals(0), reason: 'first fetch failed');
    curlCalls();
    expect(fetch().exitCode, equals(0), reason: 'second fetch failed');
    expect(curlCalls(), isEmpty);
  });

  test('curated fetch replaces files fetched at another revision', () {
    for (final path in _curated) {
      File('$dest/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync('stale');
    }
    File('$dest/.curated-0000000').createSync();

    expect(fetch().exitCode, equals(0), reason: 'fetch failed');
    expect(curlCalls(), hasLength(_curated.length));
    for (final path in _curated) {
      expect(File('$dest/$path').readAsStringSync(), isNot('stale'),
          reason: path);
    }
    expect(File('$dest/.curated-$_sha').existsSync(), isTrue);
    expect(File('$dest/.curated-0000000').existsSync(), isFalse);
  });

  test('curated fetch downloads a file missing at the pinned revision', () {
    expect(fetch().exitCode, equals(0), reason: 'first fetch failed');
    curlCalls();
    File('$dest/${_curated.last}').deleteSync();

    expect(fetch().exitCode, equals(0), reason: 'second fetch failed');
    expect(curlCalls(), hasLength(1));
    expect(File('$dest/${_curated.last}').existsSync(), isTrue);
  });
}
