// Decode benchmark for dart_flac.
//
// Measures decode latency and peak resident-set size for three call
// shapes:
//   - decodeInterleavedSamples (full in-memory buffer, Int32 samples)
//   - pcmChunks (streaming, one PCM Uint8List per decoded frame)
//   - decodeFlacFileToPcm (isolate-safe one-shot helper, 16-bit LE PCM)
//
// Each benchmark runs in a fresh subprocess so ProcessInfo.maxRss is a
// clean high-water mark for that one operation and doesn't carry over
// between runs. Output is a markdown-friendly table on stdout.
//
// Usage:
//   dart run benchmark/decode_benchmark.dart [path/to/file.flac]
//
// If no path is given, falls back to benchmark/fixtures/bench.flac
// (run benchmark/generate_fixture.sh first to produce it).
//
// Android / iOS:
//   The same code can be driven from a Flutter integration test on a
//   real device. See README.md "Performance" for a harness outline.

import 'dart:convert';
import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

const _defaultPath = 'benchmark/fixtures/bench.flac';
const _iterations = 5;

Future<void> main(List<String> args) async {
  // Worker mode: `--worker <op> <path>`. Runs one decode, prints JSON
  // with the elapsed-microseconds and peak-RSS readings, then exits.
  if (args.isNotEmpty && args.first == '--worker') {
    await _runWorker(args[1], args[2]);
    return;
  }

  final path = args.isNotEmpty ? args.first : _defaultPath;
  if (!File(path).existsSync()) {
    stderr.writeln('Benchmark fixture not found at "$path".');
    stderr.writeln('Run `./benchmark/generate_fixture.sh` or pass a path.');
    exitCode = 2;
    return;
  }

  final reader = FlacReader.fromFileSync(path);
  final info = reader.streamInfo;
  final audioSeconds = info.totalSamples / info.sampleRate;
  final pcm16Bytes = info.totalSamples * info.channels * 2;

  print('dart_flac benchmark');
  print('-------------------');
  print('Fixture : $path');
  print('Audio   : ${info.sampleRate} Hz, ${info.channels}-ch, '
      '${info.bitsPerSample}-bit, '
      '${audioSeconds.toStringAsFixed(1)}s '
      '(${_mb(pcm16Bytes)} MB @ 16-bit)');
  print('Runtime : Dart ${Platform.version.split(' ').first}, '
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('Repeats : $_iterations per operation, median reported');
  print('');

  const operations = ['full', 'streaming', 'oneshot'];
  final labels = {
    'full': 'decodeInterleavedSamples',
    'streaming': 'pcmChunks (lazy, 16-bit)',
    'oneshot': 'decodeFlacFileToPcm',
  };

  print('| Operation                  | Median (ms) | × realtime | Peak RSS (MB) |');
  print('|----------------------------|-------------|------------|---------------|');
  for (final op in operations) {
    final results = <_Result>[];
    for (var i = 0; i < _iterations; i++) {
      results.add(await _spawnWorker(op, path));
    }
    results.sort((a, b) => a.micros.compareTo(b.micros));
    final medianMicros = results[results.length ~/ 2].micros;
    final medianMs = medianMicros / 1000.0;
    final peakRssBytes =
        results.map((r) => r.peakRssBytes).reduce((a, b) => a > b ? a : b);
    final realtime = audioSeconds / (medianMs / 1000.0);
    print('| ${labels[op]!.padRight(26)} '
        '| ${medianMs.toStringAsFixed(1).padLeft(11)} '
        '| ${realtime.toStringAsFixed(1).padLeft(10)} '
        '| ${_mb(peakRssBytes).padLeft(13)} |');
  }
}

class _Result {
  final int micros;
  final int peakRssBytes;
  _Result(this.micros, this.peakRssBytes);
}

Future<_Result> _spawnWorker(String op, String path) async {
  final scriptPath = Platform.script.toFilePath();
  final runningAsAot = !scriptPath.endsWith('.dart');
  final exe = runningAsAot ? Platform.resolvedExecutable : Platform.executable;
  final args = runningAsAot
      ? ['--worker', op, path]
      : [scriptPath, '--worker', op, path];

  final result = await Process.run(exe, args);
  if (result.exitCode != 0) {
    stderr.writeln('Worker failed for $op: ${result.stderr}');
    exit(3);
  }
  final line = (result.stdout as String).trim().split('\n').last;
  final json = jsonDecode(line) as Map<String, dynamic>;
  return _Result(json['micros'] as int, json['peakRss'] as int);
}

Future<void> _runWorker(String op, String path) async {
  final sw = Stopwatch()..start();
  switch (op) {
    case 'full':
      final r = FlacReader.fromFileSync(path);
      // ignore: unused_local_variable
      final samples = r.decodeInterleavedSamples();
    case 'streaming':
      final r = FlacReader.fromFileSync(path);
      var total = 0;
      for (final c in r.pcmChunks(outputBitsPerSample: 16)) {
        total += c.length;
      }
      // Prevent dead-code elimination.
      if (total < 0) stderr.writeln(total);
    case 'oneshot':
      await decodeFlacFileToPcm(path);
    default:
      stderr.writeln('Unknown op: $op');
      exitCode = 4;
      return;
  }
  sw.stop();
  stdout.writeln(jsonEncode({
    'micros': sw.elapsedMicroseconds,
    'peakRss': ProcessInfo.maxRss,
  }));
}

String _mb(int bytes) => (bytes / 1024 / 1024).toStringAsFixed(1);
