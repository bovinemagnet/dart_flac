import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'frame/frame.dart';
import 'metadata/stream_info.dart';
import 'pcm_output.dart';

/// Result of verifying decoded PCM against the MD5 signature stored in
/// the STREAMINFO block.
enum Md5VerificationResult {
  /// The MD5 of the decoded samples matched the signature in STREAMINFO.
  match,

  /// The MD5 of the decoded samples did not match.
  mismatch,

  /// The STREAMINFO signature is all zeros — the encoder did not compute
  /// one, so verification is not possible.
  notComputed,
}

/// Streaming MD5 verifier for FLAC PCM samples.
///
/// Feed the verifier interleaved, little-endian, signed PCM bytes at the
/// stream's *native* bit depth (the value of [StreamInfoBlock.bitsPerSample],
/// rounded up to the nearest whole byte) as you decode frames, then call
/// [finalize] to compare against the signature stored in STREAMINFO.
///
/// This avoids the second-pass full decode that the convenience
/// [FlacReader.verifyMd5] does. It is the right tool when you are already
/// iterating frames for some other purpose (writing a WAV, feeding a
/// playback sink, etc.) and want to verify integrity without paying for
/// a second decode.
///
/// Example:
///
/// ```dart
/// final verifier = Md5Verifier.forStreamInfo(reader.streamInfo);
/// for (final frame in reader.framesLazy()) {
///   verifier?.addPcm(frameToInterleavedPcm(frame, reader.streamInfo.bitsPerSample));
///   // ... write the frame somewhere else too ...
/// }
/// final result = verifier?.finalize() ?? Md5VerificationResult.notComputed;
/// ```
class Md5Verifier {
  final List<int> _expected;
  final ByteConversionSink _hashSink;
  final _DigestSink _digestSink;
  bool _closed = false;

  Md5Verifier._(this._expected, this._hashSink, this._digestSink);

  /// Creates a verifier seeded from [info]'s STREAMINFO MD5 signature.
  ///
  /// Returns `null` when the signature is all zeros — the encoder did not
  /// compute one, so verification is not possible. Callers should treat
  /// `null` as equivalent to [Md5VerificationResult.notComputed].
  static Md5Verifier? forStreamInfo(StreamInfoBlock info) {
    if (info.md5.every((b) => b == 0)) return null;
    final digestSink = _DigestSink();
    final hashSink = md5.startChunkedConversion(digestSink);
    return Md5Verifier._(
      List<int>.unmodifiable(info.md5),
      hashSink,
      digestSink,
    );
  }

  /// Feeds a chunk of native-bit-depth interleaved PCM bytes into the
  /// running MD5.
  ///
  /// [pcm] must be the bytes produced by [frameToInterleavedPcm] at the
  /// stream's native bit depth — using a different output bit depth
  /// produces a different digest and verification will report
  /// [Md5VerificationResult.mismatch].
  ///
  /// Throws [StateError] if called after [finalize].
  void addPcm(List<int> pcm) {
    if (_closed) {
      throw StateError('Md5Verifier.addPcm called after finalize');
    }
    _hashSink.add(pcm);
  }

  /// Closes the running MD5 and compares it against the STREAMINFO
  /// signature.
  ///
  /// Returns [Md5VerificationResult.match] when the digest matches,
  /// [Md5VerificationResult.mismatch] otherwise. Throws [StateError] if
  /// called more than once.
  Md5VerificationResult finalize() {
    if (_closed) {
      throw StateError('Md5Verifier.finalize called twice');
    }
    _closed = true;
    _hashSink.close();
    final computed = _digestSink.digest!.bytes;
    for (var i = 0; i < 16; i++) {
      if (computed[i] != _expected[i]) {
        return Md5VerificationResult.mismatch;
      }
    }
    return Md5VerificationResult.match;
  }
}

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
