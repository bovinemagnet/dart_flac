// Read a FLAC file, print its metadata and tags, and verify the MD5.
//
// Run:  dart run example/dart_flac_example.dart path/to/track.flac

import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart_flac_example.dart <file.flac>');
    exit(64);
  }

  final reader = await FlacReader.fromFile(args.single);
  final info = reader.streamInfo;

  print('Stream:   ${info.sampleRate} Hz, ${info.channels} ch, '
      '${info.bitsPerSample}-bit');
  print('Duration: ${info.duration.inMilliseconds / 1000.0} s '
      '(${info.totalSamples} samples)');
  print('MD5:      ${info.md5Hex}');

  // Vorbis tags (title, artist, album, …) if present.
  final vc = reader.vorbisComment;
  if (vc != null) {
    print('Tags:');
    if (vc.title != null) print('  title:  ${vc.title}');
    if (vc.artist != null) print('  artist: ${vc.artist}');
    if (vc.album != null) print('  album:  ${vc.album}');
  }

  // Embedded cover art (can be multiple pictures).
  for (final pic in reader.pictures) {
    print('Picture: ${pic.pictureType}, ${pic.mimeType}, '
        '${pic.pictureData.length} bytes');
  }

  // End-to-end integrity check: decode every sample and hash it.
  switch (reader.verifyMd5()) {
    case Md5VerificationResult.match:
      print('MD5 verification: OK');
    case Md5VerificationResult.mismatch:
      print('MD5 verification: MISMATCH (decoder produced wrong samples)');
      exitCode = 1;
    case Md5VerificationResult.notComputed:
      print('MD5 verification: not stored by encoder');
  }
}
