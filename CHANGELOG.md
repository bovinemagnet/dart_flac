# Changelog

## 0.2.0

### New features

- **PCM output helpers**:
  - `FlacReader.pcmChunks({outputBitsPerSample})` — lazy
    `Iterable<Uint8List>` of interleaved LE signed samples, one chunk
    per frame.
  - `StreamingFlacDecoder.pcmStream({outputBitsPerSample})` — the
    equivalent `Stream<Uint8List>` for push-based consumers.
  - `frameToInterleavedPcm(frame, outputBitsPerSample)` — the
    underlying standalone helper.
- **`StreamingFlacDecoder`** — push-based decoder that accepts bytes
  via `addBytes()` / `close()` and emits `Stream<MetadataBlock>` and
  `Stream<FlacFrame>`. Tolerates a leading ID3v2 tag.
- **`FlacReader.framesLazy()`** — `Iterable<FlacFrame>` that decodes
  one frame per pull.
- **Random access**: `FlacReader.byteOffsetForSample()` and
  `decodeFramesFromSample()` using the SEEKTABLE block with a
  frame-header walk fallback.
- **MD5 verification**: `FlacReader.verifyMd5()` returns
  `Md5VerificationResult.{match, mismatch, notComputed}`.
- **Real-world tolerance**: the reader now skips leading ID3v2 tags,
  and `decodeFrames(recoverFromCorruption: true, onCorruption: …)`
  scans forward for the next valid frame sync on CRC failure.
- **WAV writer**: `writeWavBytes(frames:, sampleRate:, channels:,
  bitsPerSample:)` returns a RIFF/WAVE buffer ready to write to disk.
- **CLI**: `dart run dart_flac:flac2wav [--verify] input.flac
  output.wav`.

### Dependencies

- Added runtime dep on `package:crypto ^3.0.0` for MD5 hashing.

## 0.1.0

- Initial release. Full metadata parsing, frame and subframe decoding
  (CONSTANT / VERBATIM / FIXED / LPC), Rice residuals, joint-stereo
  decorrelation, CRC validation.
