// Command-line FLAC → WAV converter.
//
// Usage:
//   dart run dart_flac:flac2wav [--verify] <input.flac> <output.wav>
//
// Flags:
//   --verify   After decoding, compare the MD5 of the decoded PCM against
//              the STREAMINFO signature. Print the result to stderr and
//              exit non-zero on mismatch.
//   -h, --help Show this help message.
import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

const _usage = '''
flac2wav: decode a FLAC file into a WAV file.

Usage:
  flac2wav [--verify] <input.flac> <output.wav>

Options:
  --verify     Verify decoded PCM against the STREAMINFO MD5 signature.
  -h, --help   Show this message and exit.
''';

Future<void> main(List<String> rawArgs) async {
  var verify = false;
  final positional = <String>[];
  for (final a in rawArgs) {
    switch (a) {
      case '-h':
      case '--help':
        stdout.write(_usage);
        return;
      case '--verify':
        verify = true;
      default:
        if (a.startsWith('-')) {
          stderr.writeln('flac2wav: unknown option "$a"');
          stderr.write(_usage);
          exitCode = 2;
          return;
        }
        positional.add(a);
    }
  }

  if (positional.length != 2) {
    stderr.write(_usage);
    exitCode = 2;
    return;
  }

  final inputPath = positional[0];
  final outputPath = positional[1];

  final reader = await FlacReader.fromFile(inputPath);
  final info = reader.streamInfo;
  final frames = reader.decodeFrames();
  final wav = writeWavBytes(
    frames: frames,
    sampleRate: info.sampleRate,
    channels: info.channels,
    bitsPerSample: info.bitsPerSample,
  );
  await File(outputPath).writeAsBytes(wav);

  stderr.writeln('flac2wav: wrote $outputPath '
      '(${info.channels}ch, ${info.sampleRate} Hz, ${info.bitsPerSample}-bit, '
      '${info.totalSamples} samples).');

  if (verify) {
    final result = reader.verifyMd5();
    switch (result) {
      case Md5VerificationResult.match:
        stderr.writeln('flac2wav: MD5 verification OK.');
      case Md5VerificationResult.notComputed:
        stderr.writeln('flac2wav: MD5 not stored in STREAMINFO '
            '(encoder did not compute it).');
      case Md5VerificationResult.mismatch:
        stderr.writeln('flac2wav: MD5 MISMATCH – decoder produced '
            'different samples than the encoder.');
        exitCode = 3;
        return;
    }
  }
}
