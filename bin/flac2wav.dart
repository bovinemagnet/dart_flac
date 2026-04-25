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
import 'dart:typed_data';

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
          exit(2);
        }
        positional.add(a);
    }
  }

  if (positional.length != 2) {
    stderr.write(_usage);
    exit(2);
  }

  final inputPath = positional[0];
  final outputPath = positional[1];

  // Validate the file-independent options before touching the input
  // file, so a bad --bits / --start-sample / --duration-samples value
  // is reported as an argument error rather than masked by a missing-
  // file or malformed-FLAC error.
  _validateStaticOptions(
    bitsPerSample: outputBitsPerSample,
    startSample: startSample,
    durationSamples: durationSamples,
  );

  final reader = await FlacReader.fromFile(inputPath);
  final info = reader.streamInfo;
  final outBps = outputBitsPerSample ?? info.bitsPerSample;
  _validateAgainstStream(
    startSample: startSample,
    totalSamples: info.totalSamples,
  );

  final samplesToWrite = _samplesToWrite(
    startSample: startSample,
    durationSamples: durationSamples,
    totalSamples: info.totalSamples,
  );

  // The streaming MD5 verifier is only valid when this run iterates every
  // sample in the file, in order. Any `--start-sample` / `--duration-samples`
  // restriction means we'd be feeding it a subset of the stream's samples
  // and the digest would never match. In that case we fall back to a
  // second full-stream decode via `reader.verifyMd5()` — slower, but
  // correct.
  final teeMd5Eligible = verify && startSample == 0 && durationSamples == null;
  final md5Verifier = teeMd5Eligible ? Md5Verifier.forStreamInfo(info) : null;

  if (samplesToWrite == null) {
    // Total length unknown — buffer in memory and write the whole WAV at
    // once, since we cannot pre-compute or patch the RIFF header sizes.
    final frames = reader.decodeFramesFromSample(startSample);
    if (md5Verifier != null) {
      for (final frame in frames) {
        md5Verifier.addPcm(frameToInterleavedPcm(frame, info.bitsPerSample));
      }
    }
    final wav = writeWavBytes(
      frames: frames,
      sampleRate: info.sampleRate,
      channels: info.channels,
      bitsPerSample: outBps,
    );
    await _atomicWriteBytes(outputPath, wav);
  } else {
    await _streamWavToFile(
      reader: reader,
      outputPath: outputPath,
      startSample: startSample,
      samplesToWrite: samplesToWrite,
      sampleRate: info.sampleRate,
      channels: info.channels,
      outBitsPerSample: outBps,
      nativeBitsPerSample: info.bitsPerSample,
      md5Verifier: md5Verifier,
    );
  }

  stderr.writeln('flac2wav: wrote $outputPath '
      '(${info.channels}ch, ${info.sampleRate} Hz, $outBps-bit, '
      '${samplesToWrite ?? info.totalSamples} samples).');

  if (verify) {
    final Md5VerificationResult result;
    if (md5Verifier != null) {
      result = md5Verifier.finalize();
    } else if (teeMd5Eligible) {
      // forStreamInfo returned null — the signature in STREAMINFO is all
      // zeros, so the encoder never computed one.
      result = Md5VerificationResult.notComputed;
    } else {
      // Partial decode (start-sample / duration-samples). Fall back to a
      // full-stream re-decode so verification reflects the original file
      // rather than the slice we just wrote.
      result = reader.verifyMd5();
    }
    switch (result) {
      case Md5VerificationResult.match:
        stderr.writeln('flac2wav: MD5 verification OK.');
      case Md5VerificationResult.notComputed:
        stderr.writeln('flac2wav: MD5 not stored in STREAMINFO '
            '(encoder did not compute it).');
      case Md5VerificationResult.mismatch:
        stderr.writeln('flac2wav: MD5 MISMATCH - decoder produced '
            'different samples than the encoder.');
        exit(3);
    }
  }
}

/// Streams decoded frames to [outputPath] frame by frame, writing a
/// placeholder WAV header up front and patching the RIFF/data sizes once
/// the actual byte count is known.
///
/// Writes go to a sibling temp file and are only renamed over
/// [outputPath] after the header has been patched successfully. On any
/// mid-stream error the temp file is deleted and [outputPath] — if it
/// already existed — is left untouched.
Future<void> _streamWavToFile({
  required FlacReader reader,
  required String outputPath,
  required int startSample,
  required int samplesToWrite,
  required int sampleRate,
  required int channels,
  required int outBitsPerSample,
  required int nativeBitsPerSample,
  Md5Verifier? md5Verifier,
}) async {
  final tempPath = _tempPathFor(outputPath);
  final file = await File(tempPath).open(mode: FileMode.write);
  var actualDataBytes = 0;
  var ok = false;
  try {
    await file.writeFrom(writeWavHeaderBytes(
      dataSize: 0,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: outBitsPerSample,
    ));

    var remaining = samplesToWrite;
    if (remaining > 0) {
      for (final frame in reader.framesLazyFromSample(startSample)) {
        if (remaining == 0) break;
        final frameStart = _frameStartSample(reader, frame);
        final skip = startSample > frameStart ? startSample - frameStart : 0;
        final available = frame.blockSize - skip;
        if (available <= 0) continue;
        final take = remaining < available ? remaining : available;
        final pcm = frameToWavPcmBytes(
          frame,
          outBitsPerSample,
          skipSamples: skip,
          takeSamples: take,
        );
        await file.writeFrom(pcm);
        actualDataBytes += pcm.length;
        remaining -= take;

        // Tee the same frame's samples into the MD5 verifier at the
        // stream's *native* bit depth — that's what the FLAC reference
        // hashed, regardless of what bit depth we are writing to WAV.
        // Always feeding the whole frame is correct because the tee is
        // only enabled when startSample == 0 && durationSamples == null,
        // i.e. skip == 0 and take == frame.blockSize.
        if (md5Verifier != null) {
          md5Verifier.addPcm(frameToInterleavedPcm(frame, nativeBitsPerSample));
        }
      }
    }

    // Patch the RIFF chunk size (offset 4) and data subchunk size
    // (offset 40) with the bytes that were actually written. This keeps
    // the header honest if the loop produced fewer samples than expected
    // (e.g. truncated input or short tail frame).
    final riffSize = ByteData(4)
      ..setUint32(0, 36 + actualDataBytes, Endian.little);
    final dataSize = ByteData(4)..setUint32(0, actualDataBytes, Endian.little);
    await file.setPosition(4);
    await file.writeFrom(riffSize.buffer.asUint8List());
    await file.setPosition(40);
    await file.writeFrom(dataSize.buffer.asUint8List());
    ok = true;
  } finally {
    await file.close();
    if (ok) {
      await File(tempPath).rename(outputPath);
    } else {
      try {
        await File(tempPath).delete();
      } catch (_) {
        // Best-effort cleanup; ignore deletion errors so the original
        // exception is what propagates to the caller.
      }
    }
  }
}

/// Writes [bytes] to [outputPath] via a sibling temp file + rename, so a
/// failed write never destroys the pre-existing file at [outputPath].
Future<void> _atomicWriteBytes(String outputPath, List<int> bytes) async {
  final tempPath = _tempPathFor(outputPath);
  try {
    await File(tempPath).writeAsBytes(bytes, flush: true);
    await File(tempPath).rename(outputPath);
  } catch (_) {
    try {
      await File(tempPath).delete();
    } catch (_) {}
    rethrow;
  }
}

/// Sibling temp path, unique per invocation, so the rename stays on one
/// filesystem (atomic on POSIX via `rename(2)`; on Windows the rename
/// replaces the existing target via `MoveFileEx` with
/// `MOVEFILE_REPLACE_EXISTING`, without stricter atomicity guarantees).
/// The `pid`+timestamp suffix prevents two concurrent conversions to the
/// same [outputPath] from clobbering each other's temp file.
String _tempPathFor(String outputPath) {
  final micros = DateTime.now().microsecondsSinceEpoch;
  return '$outputPath.flac2wav.$pid.$micros.tmp';
}

int _parseRequiredInt(List<String> args, int index, String option) {
  if (index >= args.length) {
    stderr.writeln('flac2wav: missing value for $option');
    stderr.write(_usage);
    exit(2);
  }
  return _parseIntValue(args[index], option);
}

int _parseIntValue(String value, String option) {
  final parsed = int.tryParse(value);
  if (parsed == null) {
    stderr.writeln('flac2wav: $option must be an integer, got "$value"');
    stderr.write(_usage);
    exit(2);
  }
  return parsed;
}

/// File-independent option checks. Run before opening the input file so
/// that a bad argument value is reported as an argument error, not as a
/// downstream file/parse error.
///
/// [bitsPerSample] is the *user-supplied* `--bits` value (or `null` if
/// the flag was not passed). When the user did not supply `--bits` the
/// width comes from STREAMINFO, which is already constrained by the
/// FLAC parser, so no static check is required.
void _validateStaticOptions({
  required int? bitsPerSample,
  required int startSample,
  required int? durationSamples,
}) {
  if (bitsPerSample != null && ![8, 16, 24, 32].contains(bitsPerSample)) {
    stderr.writeln('flac2wav: --bits must be one of 8, 16, 24, or 32');
    exit(2);
  }
  if (startSample < 0) {
    stderr.writeln('flac2wav: --start-sample must be >= 0');
    exit(2);
  }
  if (durationSamples != null && durationSamples < 0) {
    stderr.writeln('flac2wav: --duration-samples must be >= 0');
    exit(2);
  }
}

/// Stream-dependent checks that need STREAMINFO to evaluate.
void _validateAgainstStream({
  required int startSample,
  required int totalSamples,
}) {
  if (totalSamples > 0 && startSample > totalSamples) {
    stderr.writeln('flac2wav: --start-sample is beyond end of stream');
    exit(2);
  }
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
