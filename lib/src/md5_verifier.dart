import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'frame/frame.dart';
import 'pcm_output.dart';

/// Computes the MD5 digest of decoded PCM samples, matching the format the
/// FLAC reference encoder stores in STREAMINFO.md5.
///
/// The reference implementation hashes the *unencoded* interleaved audio
/// samples, each written as a little-endian signed integer at a byte-aligned
/// width determined by [bitsPerSample] (rounded up to the next multiple of 8).
/// Channels are interleaved per inter-channel sample.
Uint8List computePcmMd5(Iterable<FlacFrame> frames, int bitsPerSample) {
  final digestSink = _DigestSink();
  final sink = md5.startChunkedConversion(digestSink);
  for (final frame in frames) {
    sink.add(frameToInterleavedPcm(frame, bitsPerSample));
  }
  sink.close();
  return Uint8List.fromList(digestSink.digest!.bytes);
}

class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
