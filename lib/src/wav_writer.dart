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
  final frameList = frames is List<FlacFrame> ? frames : frames.toList();
  final builder = BytesBuilder(copy: false);
  for (final f in frameList) {
    builder.add(frameToWavPcmBytes(f, outBps));
  }
  final pcm = builder.takeBytes();

  final dataSize = pcm.length;
  final header = writeWavHeaderBytes(
    dataSize: dataSize,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: outBps,
  );
  final out = Uint8List(header.length + dataSize);
  out.setRange(0, header.length, header);
  out.setRange(header.length, header.length + dataSize, pcm);
  return out;
}

/// Returns a 44-byte RIFF/WAVE PCM header for a following PCM payload.
///
/// Use this with [frameToWavPcmBytes] when writing a WAV file incrementally.
/// [dataSize] is the number of PCM payload bytes that will follow.
Uint8List writeWavHeaderBytes({
  required int dataSize,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
}) {
  final outBps = ((bitsPerSample + 7) ~/ 8) * 8;
  final bytesPerSample = outBps ~/ 8;
  const headerSize = 44;
  final out = Uint8List(headerSize);
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

  return out;
}

/// Converts [frame] to WAV-compatible PCM bytes.
///
/// FLAC samples are emitted as signed PCM. WAV stores 8-bit PCM as unsigned,
/// so this helper applies the required 128 bias for 8-bit output. [skipSamples]
/// and [takeSamples] operate on inter-channel samples, not individual channel
/// values.
Uint8List frameToWavPcmBytes(
  FlacFrame frame,
  int outputBitsPerSample, {
  int skipSamples = 0,
  int? takeSamples,
}) {
  if (skipSamples < 0) {
    throw RangeError.value(skipSamples, 'skipSamples', 'must be >= 0');
  }
  if (takeSamples != null && takeSamples < 0) {
    throw RangeError.value(takeSamples, 'takeSamples', 'must be >= 0');
  }

  final outBps = ((outputBitsPerSample + 7) ~/ 8) * 8;
  final bytesPerSampleFrame = frame.channelCount * (outBps ~/ 8);
  final startSample = skipSamples.clamp(0, frame.blockSize).toInt();
  final endSample = takeSamples == null
      ? frame.blockSize
      : (startSample + takeSamples).clamp(startSample, frame.blockSize).toInt();

  final signedPcm = frameToInterleavedPcm(frame, outBps);
  final start = startSample * bytesPerSampleFrame;
  final end = endSample * bytesPerSampleFrame;
  final pcm = Uint8List.sublistView(signedPcm, start, end);

  if (outBps != 8) return pcm;
  return Uint8List.fromList(
    pcm.map((b) => (b.toSigned(8) + 128) & 0xFF).toList(),
  );
}

void _writeAscii(Uint8List out, int offset, String s) {
  for (var i = 0; i < s.length; i++) {
    out[offset + i] = s.codeUnitAt(i);
  }
}
