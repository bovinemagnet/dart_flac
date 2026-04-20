// Stream-decode FLAC as bytes arrive — the shape you want when pulling
// audio from a socket, a chunked HTTP response, or any other byte source.
//
// This example reads a local file in small chunks to simulate network
// arrival, but any Stream<List<int>> works the same way: wire it into
// [StreamingFlacDecoder.addBytes].
//
// To actually play the audio you feed [decoder.pcmStream()] to your
// player of choice. The package itself does no I/O or audio output — it
// only turns compressed FLAC bytes into PCM bytes. See the commented
// `flutter_sound` integration below for a concrete example.
//
// Run:  dart run example/streaming_playback.dart path/to/track.flac

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_flac/dart_flac.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: streaming_playback.dart <file.flac>');
    exit(64);
  }

  final decoder = StreamingFlacDecoder();

  // 1. Wait for STREAMINFO so we know how to configure the audio sink.
  decoder.onStreamInfo.then((info) {
    stderr.writeln('Got STREAMINFO: ${info.sampleRate} Hz, '
        '${info.channels} ch, ${info.bitsPerSample}-bit');
    // ──────────────────────────────────────────────────────────────────
    // Example wire-up with flutter_sound (commented out — this example
    // stays pure Dart with no native deps so it can run on the CLI):
    //
    //   final player = FlutterSoundPlayer();
    //   await player.openPlayer();
    //   await player.startPlayerFromStream(
    //     codec: Codec.pcm16,
    //     sampleRate: info.sampleRate,
    //     numChannels: info.channels,
    //   );
    //   decoder.pcmStream(outputBitsPerSample: 16)
    //       .listen((chunk) => player.foodSink?.add(FoodData(chunk)));
    // ──────────────────────────────────────────────────────────────────
  });

  // 2. Subscribe to the PCM byte stream. Each event is a small, ready-to-
  //    play buffer of interleaved little-endian signed samples.
  var totalBytes = 0;
  final pcmSub = decoder.pcmStream().listen((chunk) {
    totalBytes += chunk.length;
    // In a real app: hand `chunk` to your player here.
  });

  // 3. Feed bytes as they arrive. Chunk sizes are arbitrary — the decoder
  //    buffers internally until each frame is complete.
  final file = File(args.single);
  await for (final chunk in file.openRead()) {
    decoder.addBytes(Uint8List.fromList(chunk));
  }
  decoder.close();
  await pcmSub.asFuture<void>();

  stderr.writeln('Streamed $totalBytes bytes of PCM.');
}
