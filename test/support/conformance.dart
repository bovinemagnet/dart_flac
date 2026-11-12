import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_flac/dart_flac.dart';
import 'package:test/test.dart';

/// Root directory populated by `tool/fetch_conformance.sh`.
const conformanceDir = 'test/fixtures/conformance';

/// Present after any fetch: the first curated file.
bool get curatedFilesPresent =>
    File('$conformanceDir/subset/01 - blocksize 4096.flac').existsSync();

/// Present only after `--full`: a file outside the curated set, so its
/// existence means the whole testbench is available.
bool get fullSetPresent =>
    File('$conformanceDir/subset/02 - blocksize 4608.flac').existsSync();

/// Parses one file and returns the STREAMINFO MD5 verdict.
/// [Md5VerificationResult.match] proves a bit-exact decode of the whole
/// stream. [Md5VerificationResult.notComputed] is returned without decoding
/// any frames; use [decodeEveryWay] to decode such files. Throws
/// [FormatException] for streams the reader rejects.
Md5VerificationResult verifyFile(String path) =>
    FlacReader.fromFileSync(path).verifyMd5();

/// What one decode path produced: the number of interleaved sample values
/// and the MD5 of those values, so paths can be compared without holding
/// every sample in memory.
typedef PcmFingerprint = ({int values, String md5});

/// Result of [decodeEveryWay]: frame and per-channel sample counts from the
/// lazy path, plus a [PcmFingerprint] for each public decode path.
typedef DecodeReport = ({
  int frames,
  int samplesPerChannel,
  Map<String, PcmFingerprint> fingerprints,
});

/// Decodes the file at [path] through `framesLazy()`,
/// `decodeInterleavedSamples()` and [StreamingFlacDecoder]. Every path must
/// decode the whole stream; their fingerprints should all be equal.
Future<DecodeReport> decodeEveryWay(String path) async {
  final bytes = File(path).readAsBytesSync();
  final reader = FlacReader.fromBytes(bytes);

  final lazy = _Fingerprinter();
  var frames = 0;
  var samplesPerChannel = 0;
  for (final frame in reader.framesLazy()) {
    frames++;
    samplesPerChannel += frame.blockSize;
    lazy.addFrame(frame);
  }

  final eager = _Fingerprinter()..add(reader.decodeInterleavedSamples());

  return (
    frames: frames,
    samplesPerChannel: samplesPerChannel,
    fingerprints: {
      'framesLazy': lazy.result,
      'decodeInterleavedSamples': eager.result,
      'StreamingFlacDecoder': await streamingFingerprint(bytes),
    },
  );
}

/// Fails unless every decode path in [report] produced identical samples.
void expectPathsAgree(DecodeReport report) {
  expect(report.fingerprints.values.toSet(), hasLength(1),
      reason: 'Decode paths disagree: ${report.fingerprints}');
}

/// Feeds [bytes] to a [StreamingFlacDecoder] in uneven chunks, so frames
/// straddle chunk boundaries, and fingerprints the decoded frames. Completes
/// with the first error the decoder reports, including a missing STREAMINFO.
Future<PcmFingerprint> streamingFingerprint(Uint8List bytes) async {
  // Odd-sized, roughly socket-read-sized chunks: much smaller chunks make
  // the decoder's buffer compaction slow on huge metadata blocks (#30).
  const chunkSize = 65521;
  final decoder = StreamingFlacDecoder();
  final fingerprinter = _Fingerprinter();
  // Listen to both before feeding bytes, so an error is never unhandled.
  final done = Future.wait(
      [decoder.frames.forEach(fingerprinter.addFrame), decoder.onStreamInfo]);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = i + chunkSize < bytes.length ? i + chunkSize : bytes.length;
    decoder.addBytes(Uint8List.sublistView(bytes, i, end));
  }
  decoder.close();
  await done;
  return fingerprinter.result;
}

class _Fingerprinter {
  final _digest = _DigestSink();
  late final _sink = md5.startChunkedConversion(_digest);
  var _values = 0;

  void addFrame(FlacFrame frame) {
    final channels = frame.channelCount;
    final interleaved = Int32List(frame.blockSize * channels);
    for (var ch = 0; ch < channels; ch++) {
      final samples = frame.channelSamples[ch];
      for (var s = 0; s < frame.blockSize; s++) {
        interleaved[s * channels + ch] = samples[s];
      }
    }
    add(interleaved);
  }

  void add(Int32List values) {
    _values += values.length;
    _sink.add(
        values.buffer.asUint8List(values.offsetInBytes, values.lengthInBytes));
  }

  PcmFingerprint get result {
    _sink.close();
    return (values: _values, md5: _digest.value.toString());
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
