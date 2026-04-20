# dart_flac examples

Four small programs showing the main entry points of the library. All
are pure Dart and run from the command line.

| File | Purpose |
|------|---------|
| [`dart_flac_example.dart`](dart_flac_example.dart) | Print stream info, Vorbis tags, pictures, and verify MD5. |
| [`streaming_playback.dart`](streaming_playback.dart) | Feed bytes in as they arrive (e.g. from a network socket) and emit PCM chunks ready for a player. |
| [`flac_to_wav.dart`](flac_to_wav.dart) | Convert a FLAC file to a WAV file programmatically. |
| `../bin/flac2wav.dart` | Command-line entry point installed as `dart run dart_flac:flac2wav`. |

Run any example directly once you have the package:

```sh
dart run example/dart_flac_example.dart track.flac
dart run example/streaming_playback.dart track.flac
dart run example/flac_to_wav.dart track.flac track.wav
```
