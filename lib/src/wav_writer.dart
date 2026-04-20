import 'dart:typed_data';

import 'frame/frame.dart';
import 'pcm_output.dart';

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

  final frameList = frames is List<FlacFrame> ? frames : frames.toList();
  final builder = BytesBuilder(copy: false);
  for (final f in frameList) {
    builder.add(frameToInterleavedPcm(f, outBps));
  }
  final signedPcm = builder.takeBytes();

  // 8-bit WAV is unsigned (bias of 128).
  final pcm = outBps == 8
      ? Uint8List.fromList(
          signedPcm.map((b) => (b.toSigned(8) + 128) & 0xFF).toList())
      : signedPcm;

  final dataSize = pcm.length;
  const headerSize = 44;
  final out = Uint8List(headerSize + dataSize);
  final bd = ByteData.sublistView(out);

  _writeAscii(out, 0, 'RIFF');
  bd.setUint32(4, 36 + dataSize, Endian.little);
  _writeAscii(out, 8, 'WAVE');

  _writeAscii(out, 12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little); // format code = PCM
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
  bd.setUint16(32, channels * bytesPerSample, Endian.little);
  bd.setUint16(34, outBps, Endian.little);

  _writeAscii(out, 36, 'data');
  bd.setUint32(40, dataSize, Endian.little);

  out.setRange(headerSize, headerSize + dataSize, pcm);
  return out;
}

void _writeAscii(Uint8List out, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    out[offset + i] = s.codeUnitAt(i);
  }
}
