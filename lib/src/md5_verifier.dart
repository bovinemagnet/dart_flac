import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'frame/frame.dart';

/// Computes the MD5 digest of decoded PCM samples, matching the format the
/// FLAC reference encoder stores in STREAMINFO.md5.
///
/// The reference implementation hashes the *unencoded* interleaved audio
/// samples, each written as a little-endian signed integer at a byte-aligned
/// width determined by [bitsPerSample] (rounded up to the next multiple of 8).
/// Channels are interleaved per inter-channel sample.
Uint8List computePcmMd5(List<FlacFrame> frames, int bitsPerSample) {
  final bytesPerSample = (bitsPerSample + 7) ~/ 8;
  final mask =
      bytesPerSample == 4 ? 0xFFFFFFFF : (1 << (bytesPerSample * 8)) - 1;

  var totalSamples = 0;
  for (final f in frames) {
    totalSamples += f.blockSize * f.channelCount;
  }
  final bytes = Uint8List(totalSamples * bytesPerSample);
  var out = 0;

  for (final frame in frames) {
    final channels = frame.channelCount;
    final blockSize = frame.blockSize;
    for (var s = 0; s < blockSize; s++) {
      for (var ch = 0; ch < channels; ch++) {
        final value = frame.channelSamples[ch][s] & mask;
        for (var b = 0; b < bytesPerSample; b++) {
          bytes[out++] = (value >> (b * 8)) & 0xFF;
        }
      }
    }
  }

  return Uint8List.fromList(md5.convert(bytes).bytes);
}
