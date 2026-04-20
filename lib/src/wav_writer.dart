import 'dart:typed_data';

import 'frame/frame.dart';

/// Serialises decoded FLAC samples as a RIFF/WAVE byte buffer.
///
/// [frames] are the decoded audio frames, [sampleRate] and [channels] come
/// from STREAMINFO, and [bitsPerSample] is the FLAC stream's bit depth.
/// The WAV output uses a sample width rounded up to the nearest whole
/// byte: 1–8 → 8-bit unsigned, 9–16 → 16-bit signed LE, 17–24 → 24-bit
/// signed LE, 25–32 → 32-bit signed LE.
Uint8List writeWavBytes({
  required Iterable<FlacFrame> frames,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final outBps = ((bitsPerSample + 7) ~/ 8) * 8;
  final bytesPerSample = outBps ~/ 8;

  // Count samples so we can size a single contiguous buffer.
  // If the caller passed a List, this is O(n); if it's a lazy iterable,
  // we have to materialise once to know the size — accept that cost.
  final frameList = frames is List<FlacFrame> ? frames : frames.toList();
  var totalSamples = 0;
  for (final f in frameList) {
    totalSamples += f.blockSize * f.channelCount;
  }

  final dataSize = totalSamples * bytesPerSample;
  const headerSize = 44;
  final out = Uint8List(headerSize + dataSize);
  final bd = ByteData.sublistView(out);

  // RIFF chunk descriptor.
  _writeAscii(out, 0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  _writeAscii(out, 8, 'WAVE');

  // "fmt " sub-chunk.
  _writeAscii(out, 12, 'fmt ');
  bd.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  bd.setUint16(20, 1, Endian.little); // format code = PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  bd.setUint16(32, channels * bytesPerSample, Endian.little);
  bd.setUint16(34, outBps, Endian.little);

  // "data" sub-chunk header.
  _writeAscii(out, 36, 'data');
  bd.setUint32(40, dataSize, Endian.little);

  // Interleaved sample data.
  var o = headerSize;
  final mask = outBps == 32 ? 0xFFFFFFFF : (1 << outBps) - 1;
  for (final f in frameList) {
    final cs = f.channelSamples;
    for (var s = 0; s < f.blockSize; s++) {
      for (var ch = 0; ch < f.channelCount; ch++) {
        var v = cs[ch][s];
        if (outBps == 8) {
          // 8-bit WAV is unsigned PCM (bias of 128).
          out[o++] = (v + 128) & 0xFF;
        } else {
          v = v & mask;
          for (var b = 0; b < bytesPerSample; b++) {
            out[o++] = (v >> (b * 8)) & 0xFF;
          }
        }
      }
    }
  }
  return out;
}

void _writeAscii(Uint8List out, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    out[offset + i] = s.codeUnitAt(i);
  }
}
