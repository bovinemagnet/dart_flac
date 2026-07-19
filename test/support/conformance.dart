import 'dart:io';

import 'package:dart_flac/dart_flac.dart';

/// Root directory populated by `tool/fetch_conformance.sh`.
const conformanceDir = 'test/fixtures/conformance';

/// Present after any fetch: the first curated file.
bool get curatedFilesPresent =>
    File('$conformanceDir/subset/01 - blocksize 4096.flac').existsSync();

/// Present only after `--full`: a file outside the curated set, so its
/// existence means the whole testbench is available.
bool get fullSetPresent =>
    File('$conformanceDir/subset/02 - blocksize 4608.flac').existsSync();

/// Parses and fully decodes one file, returning the STREAMINFO MD5 verdict.
/// [Md5VerificationResult.match] proves a bit-exact decode of the whole
/// stream. Throws [FormatException] for streams the reader rejects.
Md5VerificationResult verifyFile(String path) =>
    FlacReader.fromFileSync(path).verifyMd5();
