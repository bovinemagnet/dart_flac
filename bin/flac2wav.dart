// Command-line FLAC → WAV converter.
//
// Usage:
//   dart run dart_flac:flac2wav [options] <input.flac> <output.wav>
//
// Flags:
//   --verify                 Compare decoded PCM MD5 against STREAMINFO.
//   --no-md5                 Disable MD5 verification if supplied by a wrapper.
//   --bits <8|16|24|32>      Output WAV sample width.
//   --start-sample <n>       Start conversion at sample n.
//   --duration-samples <n>   Convert at most n samples per channel.
//   -h, --help               Show this help message.
import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

const _usage = '''
flac2wav: decode a FLAC file into a WAV file.

Usage:
  flac2wav [options] <input.flac> <output.wav>

Options:
  --verify                 Verify decoded PCM against STREAMINFO MD5.
  --no-md5                 Disable MD5 verification if supplied by a wrapper.
  --bits <8|16|24|32>      Output WAV sample width. Defaults to stream depth.
  --start-sample <n>       Start conversion at sample n. Defaults to 0.
  --duration-samples <n>   Convert at most n samples per channel.
  -h, --help               Show this message and exit.
''';

Future<void> main(List<String> rawArgs) async {
  var verify = false;
  int? outputBitsPerSample;
  var startSample = 0;
  int? durationSamples;
  final positional = <String>[];
  for (var i = 0; i < rawArgs.length; i++) {
    final a = rawArgs[i];
    switch (a) {
      case '-h':
      case '--help':
        stdout.write(_usage);
        return;
      case '--verify':
        verify = true;
      case '--no-md5':
        verify = false;
      case '--bits':
        outputBitsPerSample = _parseRequiredInt(rawArgs, ++i, '--bits');
      case '--start-sample':
        startSample = _parseRequiredInt(rawArgs, ++i, '--start-sample');
      case '--duration-samples':
        durationSamples = _parseRequiredInt(rawArgs, ++i, '--duration-samples');
      default:
        if (a.startsWith('--bits=')) {
          outputBitsPerSample =
              _parseIntValue(a.substring('--bits='.length), '--bits');
          continue;
        }
        if (a.startsWith('--start-sample=')) {
          startSample = _parseIntValue(
              a.substring('--start-sample='.length), '--start-sample');
          continue;
        }
        if (a.startsWith('--duration-samples=')) {
          durationSamples = _parseIntValue(
              a.substring('--duration-samples='.length), '--duration-samples');
          continue;
        }
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
  final outBps = outputBitsPerSample ?? info.bitsPerSample;
  _validateOptions(
    bitsPerSample: outBps,
    startSample: startSample,
    durationSamples: durationSamples,
    totalSamples: info.totalSamples,
  );

  final samplesToWrite = _samplesToWrite(
    startSample: startSample,
    durationSamples: durationSamples,
    totalSamples: info.totalSamples,
  );
  final knownSamplesToWrite = samplesToWrite;
  final outBytesPerSample = ((outBps + 7) ~/ 8);
  final dataSize = knownSamplesToWrite == null
      ? null
      : knownSamplesToWrite * info.channels * outBytesPerSample;

  if (dataSize == null) {
    final frames = reader.decodeFramesFromSample(startSample);
    final wav = writeWavBytes(
      frames: frames,
      sampleRate: info.sampleRate,
      channels: info.channels,
      bitsPerSample: outBps,
    );
    await File(outputPath).writeAsBytes(wav);
  } else {
    final sink = File(outputPath).openWrite();
    sink.add(writeWavHeaderBytes(
      dataSize: dataSize,
      sampleRate: info.sampleRate,
      channels: info.channels,
      bitsPerSample: outBps,
    ));

    var remaining = knownSamplesToWrite!;
    if (remaining > 0) {
      for (final frame in reader.framesLazyFromSample(startSample)) {
        if (remaining == 0) break;
        final frameStart = _frameStartSample(reader, frame);
        final skip = startSample > frameStart ? startSample - frameStart : 0;
        final available = frame.blockSize - skip;
        if (available <= 0) continue;
        final take = remaining < available ? remaining : available;
        sink.add(frameToWavPcmBytes(
          frame,
          outBps,
          skipSamples: skip,
          takeSamples: take,
        ));
        remaining -= take;
      }
    }
    await sink.close();
  }

  stderr.writeln('flac2wav: wrote $outputPath '
      '(${info.channels}ch, ${info.sampleRate} Hz, $outBps-bit, '
      '${samplesToWrite ?? info.totalSamples} samples).');

  if (verify) {
    final result = reader.verifyMd5();
    switch (result) {
      case Md5VerificationResult.match:
        stderr.writeln('flac2wav: MD5 verification OK.');
      case Md5VerificationResult.notComputed:
        stderr.writeln('flac2wav: MD5 not stored in STREAMINFO '
            '(encoder did not compute it).');
      case Md5VerificationResult.mismatch:
        stderr.writeln('flac2wav: MD5 MISMATCH - decoder produced '
            'different samples than the encoder.');
        exitCode = 3;
        return;
    }
  }
}

int _parseRequiredInt(List<String> args, int index, String option) {
  if (index >= args.length) {
    stderr.writeln('flac2wav: missing value for $option');
    stderr.write(_usage);
    exitCode = 2;
    return 0;
  }
  return _parseIntValue(args[index], option);
}

int _parseIntValue(String value, String option) {
  final parsed = int.tryParse(value);
  if (parsed == null) {
    stderr.writeln('flac2wav: $option must be an integer, got "$value"');
    stderr.write(_usage);
    exitCode = 2;
    return 0;
  }
  return parsed;
}

void _validateOptions({
  required int bitsPerSample,
  required int startSample,
  required int? durationSamples,
  required int totalSamples,
}) {
  if (![8, 16, 24, 32].contains(bitsPerSample)) {
    stderr.writeln('flac2wav: --bits must be one of 8, 16, 24, or 32');
    exitCode = 2;
    return;
  }
  if (startSample < 0) {
    stderr.writeln('flac2wav: --start-sample must be >= 0');
    exitCode = 2;
    return;
  }
  if (durationSamples != null && durationSamples < 0) {
    stderr.writeln('flac2wav: --duration-samples must be >= 0');
    exitCode = 2;
    return;
  }
  if (totalSamples > 0 && startSample > totalSamples) {
    stderr.writeln('flac2wav: --start-sample is beyond end of stream');
    exitCode = 2;
    return;
  }
  if (exitCode != 0) exit(exitCode);
}

int? _samplesToWrite({
  required int startSample,
  required int? durationSamples,
  required int totalSamples,
}) {
  if (totalSamples <= 0) return durationSamples;
  final available = totalSamples - startSample;
  if (durationSamples == null) return available;
  return durationSamples < available ? durationSamples : available;
}

int _frameStartSample(FlacReader reader, FlacFrame frame) {
  if (frame.header.blockingStrategy == BlockingStrategy.variableBlocksize) {
    return frame.header.number;
  }
  final info = reader.streamInfo;
  final fixedBlockSize = info.minBlockSize == info.maxBlockSize
      ? info.maxBlockSize
      : frame.blockSize;
  return frame.header.number * fixedBlockSize;
}
