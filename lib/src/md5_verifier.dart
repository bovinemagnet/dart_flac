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
Uint8List computePcmMd5(List<FlacFrame> frames, int bitsPerSample) {
  final builder = BytesBuilder(copy: false);
  for (final frame in frames) {
    builder.add(frameToInterleavedPcm(frame, bitsPerSample));
  }
  return Uint8List.fromList(md5.convert(builder.takeBytes()).bytes);
}
