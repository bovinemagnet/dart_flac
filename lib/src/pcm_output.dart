import 'dart:typed_data';

import 'frame/frame.dart';

/// Converts a decoded [FlacFrame] to interleaved, little-endian, signed PCM
/// bytes — the format expected by virtually every low-level audio sink.
///
/// [outputBitsPerSample] is the width of each sample in the output buffer.
/// It is rounded up to the nearest whole byte, so the legal values are 8,
/// 16, 24, and 32 bits (values in between are promoted). When the frame's
/// own bit depth differs from [outputBitsPerSample], samples are arithmetic-
/// shifted to fit (left-shifted when widening, right-shifted when narrowing).
///
/// For 16-bit playback — the most common case — pass 16 regardless of the
/// stream's native depth, and the decoder will truncate 24- or 32-bit
/// sources to the top 16 bits.
Uint8List frameToInterleavedPcm(FlacFrame frame, int outputBitsPerSample) {
  final outBytes = ((outputBitsPerSample + 7) ~/ 8);
  final nativeBits = frame.header.bitsPerSample;
  final shift = outBytes * 8 - nativeBits;

  final blockSize = frame.blockSize;
  final channels = frame.channelCount;
  final out = Uint8List(blockSize * channels * outBytes);
  final mask = outBytes == 4 ? 0xFFFFFFFF : (1 << (outBytes * 8)) - 1;

  var o = 0;
  final channelSamples = frame.channelSamples;
  for (var s = 0; s < blockSize; s++) {
    for (var c = 0; c < channels; c++) {
      var v = channelSamples[c][s];
      if (shift > 0) {
        v = v << shift;
      } else if (shift < 0) {
        v = v >> -shift;
      }
      v = v & mask;
      for (var b = 0; b < outBytes; b++) {
        out[o++] = (v >> (b * 8)) & 0xFF;
      }
    }
  }
  return out;
}
