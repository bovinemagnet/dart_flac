// Convert a FLAC file to a WAV file using `writeWavBytes`.
//
// For a ready-to-use CLI, see `bin/flac2wav.dart` which is installed as
// an executable via pub (`dart run dart_flac:flac2wav …`). This example
// shows how to do the same thing from your own code.
//
// Run:  dart run example/flac_to_wav.dart input.flac output.wav

import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: flac_to_wav.dart <input.flac> <output.wav>');
    exit(64);
  }

  final reader = await FlacReader.fromFile(args[0]);
  final info = reader.streamInfo;

  final wav = writeWavBytes(
    frames: reader.decodeFrames(),
    sampleRate: info.sampleRate,
    channels: info.channels,
    bitsPerSample: info.bitsPerSample,
  );

  await File(args[1]).writeAsBytes(wav);
  stderr.writeln('Wrote ${args[1]} (${wav.length} bytes).');
}
