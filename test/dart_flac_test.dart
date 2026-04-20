import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dart_flac/dart_flac.dart';
import 'package:dart_flac/src/bit_reader.dart';
import 'package:dart_flac/src/crc.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Minimal valid FLAC file used in tests.
//
// Constructed by hand (verified via independent Python script):
//   - fLaC marker
//   - STREAMINFO block (last, 34 bytes): 44100 Hz, stereo, 16-bit, 8 samples
//   - Frame 0 (left/side stereo, 4 samples): left=1000, right=-500
//   - Frame 1 (2 independent channels, 4 samples): left=0, right=0
// ---------------------------------------------------------------------------
final Uint8List _minimalFlac = Uint8List.fromList([
  // "fLaC" marker
  0x66, 0x4c, 0x61, 0x43,
  // STREAMINFO header: is_last=1, type=0, length=34
  0x80, 0x00, 0x00, 0x22,
  // STREAMINFO data (34 bytes):
  //   min_block_size=4, max_block_size=4
  //   min_frame_size=0, max_frame_size=0
  //   sample_rate=44100, channels=2, bps=16, total_samples=8
  //   MD5 = all zeros
  0x00, 0x04, 0x00, 0x04,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x0a, 0xc4, 0x42, 0xf0,
  0x00, 0x00, 0x00, 0x08,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  // Frame 0 (leftSide stereo, blockSize=4):
  //   ch0=constant(1000), ch1=constant(1500)
  //   After decorrelation: left=1000, right=1000-1500=-500
  0xff, 0xf8, 0x69, 0x88, 0x00, 0x03, 0x1f,
  0x00, 0x03, 0xe8, 0x00, 0x02, 0xee, 0x00, 0xca, 0xa8,
  // Frame 1 (2 independent channels, blockSize=4):
  //   ch0=constant(0), ch1=constant(0)
  0xff, 0xf8, 0x69, 0x18, 0x01, 0x03, 0xa3,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x58, 0x5e,
]);

void main() {
  group('FlacReader', () {
    test('fromBytes rejects non-FLAC data', () {
      final bad = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      expect(() => FlacReader.fromBytes(bad), throwsFormatException);
    });

    test('fromBytes parses a valid FLAC file', () {
      expect(() => FlacReader.fromBytes(_minimalFlac), returnsNormally);
    });

    test('audioDataOffset is correct', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      // 4 (marker) + 4 (block header) + 34 (STREAMINFO) = 42
      expect(reader.audioDataOffset, equals(42));
    });
  });

  group('StreamInfoBlock', () {
    late StreamInfoBlock info;

    setUp(() {
      info = FlacReader.fromBytes(_minimalFlac).streamInfo;
    });

    test('sample rate', () => expect(info.sampleRate, equals(44100)));
    test('channels', () => expect(info.channels, equals(2)));
    test('bits per sample', () => expect(info.bitsPerSample, equals(16)));
    test('total samples', () => expect(info.totalSamples, equals(8)));
    test('min block size', () => expect(info.minBlockSize, equals(4)));
    test('max block size', () => expect(info.maxBlockSize, equals(4)));
    test('duration', () {
      final expected = Duration(
          microseconds: (8 * 1000000 ~/ 44100));
      expect(info.duration, equals(expected));
    });
    test('md5 is zeroed', () {
      expect(info.md5, everyElement(equals(0)));
      expect(info.md5Hex, equals('0' * 32));
    });
    test('blockType is STREAMINFO', () {
      expect(info.blockType, equals(BlockType.streamInfo));
    });
  });

  group('MetadataBlock parsing', () {
    test('only STREAMINFO is present in minimal file', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.metadataBlocks.length, equals(1));
      expect(reader.metadataBlocks.first, isA<StreamInfoBlock>());
    });

    test('vorbisComment is null when not present', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.vorbisComment, isNull);
    });

    test('seekTable is null when not present', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.seekTable, isNull);
    });

    test('pictures list is empty when not present', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.pictures, isEmpty);
    });
  });

  group('Frame decoding', () {
    late FlacReader reader;

    setUp(() {
      reader = FlacReader.fromBytes(_minimalFlac);
    });

    test('decodes two frames', () {
      final frames = reader.decodeFrames();
      expect(frames.length, equals(2));
    });

    test('frame 0 has correct header', () {
      final frame = reader.decodeFrames().first;
      expect(frame.header.blockSize, equals(4));
      expect(frame.header.sampleRate, equals(44100));
      expect(frame.header.channelCount, equals(2));
      expect(frame.header.bitsPerSample, equals(16));
    });

    test('frame 0 channel 0 samples are all 1000', () {
      final frame = reader.decodeFrames().first;
      expect(frame.channelSamples[0], everyElement(equals(1000)));
    });

    test('frame 0 channel 1 samples are all -500 (after decorrelation)', () {
      final frame = reader.decodeFrames().first;
      expect(frame.channelSamples[1], everyElement(equals(-500)));
    });

    test('frame 1 samples are all 0', () {
      final frame = reader.decodeFrames()[1];
      expect(frame.channelSamples[0], everyElement(equals(0)));
      expect(frame.channelSamples[1], everyElement(equals(0)));
    });

    test('decodeInterleavedSamples has correct length', () {
      final samples = reader.decodeInterleavedSamples();
      // 2 frames × 4 samples × 2 channels = 16
      expect(samples.length, equals(16));
    });

    test('decodeInterleavedSamples interleaves correctly', () {
      final samples = reader.decodeInterleavedSamples();
      // Frame 0: [left=1000, right=-500] × 4 then Frame 1: [0, 0] × 4
      for (var i = 0; i < 8; i += 2) {
        expect(samples[i], equals(1000), reason: 'index $i should be left=1000');
        expect(samples[i + 1], equals(-500),
            reason: 'index ${i + 1} should be right=-500');
      }
      for (var i = 8; i < 16; i++) {
        expect(samples[i], equals(0), reason: 'index $i should be 0');
      }
    });
  });

  group('VorbisCommentBlock', () {
    // Build a tiny FLAC with a VORBIS_COMMENT block.
    Uint8List buildWithVorbisComment() {
      // VORBIS_COMMENT bytes:
      // vendor: "test" (4 bytes), 2 comments: "TITLE=Hello", "ARTIST=World"
      const vendor = 'test encoder';
      const comments = ['TITLE=Hello', 'ARTIST=World'];

      final vendorBytes = vendor.codeUnits;
      final commentBytes = [
        for (final c in comments) c.codeUnits,
      ];

      // Build the block data.
      final data = <int>[];
      // Vendor length (LE 32-bit)
      data.addAll([
        vendorBytes.length & 0xFF,
        (vendorBytes.length >> 8) & 0xFF,
        0,
        0,
      ]);
      data.addAll(vendorBytes);
      // Comment count (LE 32-bit)
      data.addAll([comments.length, 0, 0, 0]);
      for (final cb in commentBytes) {
        data.addAll([cb.length & 0xFF, (cb.length >> 8) & 0xFF, 0, 0]);
        data.addAll(cb);
      }

      // Build STREAMINFO block (not last).
      final si = _buildStreamInfoBytes();
      final siHeader = [0x00, 0x00, 0x00, 0x22]; // is_last=0, type=0, len=34

      // VORBIS_COMMENT block header: is_last=1, type=4.
      final vcHeader = [
        (0x80 | BlockType.vorbisComment),
        (data.length >> 16) & 0xFF,
        (data.length >> 8) & 0xFF,
        data.length & 0xFF,
      ];

      return Uint8List.fromList([
        0x66, 0x4c, 0x61, 0x43, // fLaC
        ...siHeader, ...si,
        ...vcHeader, ...data,
      ]);
    }

    late VorbisCommentBlock vc;

    setUp(() {
      final bytes = buildWithVorbisComment();
      final reader = FlacReader.fromBytes(bytes);
      vc = reader.vorbisComment!;
    });

    test('vendor string', () => expect(vc.vendor, equals('test encoder')));
    test('comment count', () => expect(vc.comments.length, equals(2)));
    test('title tag', () => expect(vc.title, equals('Hello')));
    test('artist tag', () => expect(vc.artist, equals('World')));
    test('missing tag returns null', () => expect(vc.tag('ALBUM'), isNull));
    test('case-insensitive tag lookup', () {
      expect(vc.tag('title'), equals('Hello'));
      expect(vc.tag('Title'), equals('Hello'));
    });
  });

  group('PaddingBlock', () {
    test('parsed correctly', () {
      final bytes = _buildFlacWithBlock(
          BlockType.padding, true, Uint8List(64));
      final reader = FlacReader.fromBytes(bytes);
      final padding = reader.paddingBlocks;
      expect(padding.length, equals(1));
      expect(padding.first.length, equals(64));
    });
  });

  group('SeekTableBlock', () {
    test('parsed correctly with one seek point', () {
      // Build a single seek point: 18 bytes
      final seekData = Uint8List(18);
      // sampleNumber = 0 (8 bytes BE)
      // streamOffset = 0 (8 bytes BE)
      // frameSamples = 4 (2 bytes BE)
      seekData[16] = 0;
      seekData[17] = 4;

      final bytes = _buildFlacWithBlock(
          BlockType.seekTable, true, seekData);
      final reader = FlacReader.fromBytes(bytes);
      expect(reader.seekTable, isNotNull);
      expect(reader.seekTable!.seekPoints.length, equals(1));
      expect(reader.seekTable!.seekPoints.first.frameSamples, equals(4));
      expect(reader.seekTable!.seekPoints.first.isPlaceholder, isFalse);
    });

    test('placeholder point detected without relying on 64-bit literals', () {
      // sample_number = all 0xFF → placeholder marker. Must be detectable
      // on the web, where Dart int is a JS Number and 0xFFFFFFFFFFFFFFFF
      // cannot be represented exactly.
      final seekData = Uint8List(18);
      for (var i = 0; i < 8; i++) {
        seekData[i] = 0xFF;
      }
      final bytes = _buildFlacWithBlock(
          BlockType.seekTable, true, seekData);
      final reader = FlacReader.fromBytes(bytes);
      final pt = reader.seekTable!.seekPoints.single;
      expect(pt.isPlaceholder, isTrue);
    });
  });

  group('ApplicationBlock', () {
    test('parsed correctly', () {
      // Application ID: 0x41494646 ("AIFF")
      final appData = Uint8List.fromList([
        0x41, 0x49, 0x46, 0x46, // "AIFF"
        0xDE, 0xAD, 0xBE, 0xEF, // application data
      ]);
      final bytes =
          _buildFlacWithBlock(BlockType.application, true, appData);
      final reader = FlacReader.fromBytes(bytes);
      final appBlocks = reader.applicationBlocks;
      expect(appBlocks.length, equals(1));
      expect(appBlocks.first.applicationId, equals(0x41494646));
      expect(appBlocks.first.applicationIdString, equals('AIFF'));
      expect(appBlocks.first.applicationData.length, equals(4));
    });
  });

  group('PictureBlock', () {
    test('parsed correctly', () {
      // Minimal picture block with a 1-byte placeholder image.
      final mimeType = 'image/jpeg'.codeUnits;
      final description = ''.codeUnits;
      final imageData = [0xFF]; // 1-byte fake image

      final picData = <int>[];
      // picture type (BE 32-bit): 3 = cover front
      picData.addAll([0, 0, 0, 3]);
      // MIME type length + bytes
      picData.addAll([0, 0, 0, mimeType.length]);
      picData.addAll(mimeType);
      // description length + bytes
      picData.addAll([0, 0, 0, description.length]);
      picData.addAll(description);
      // width, height, color depth, colors used (all 0)
      picData.addAll([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      // data length + data
      picData.addAll([0, 0, 0, imageData.length]);
      picData.addAll(imageData);

      final bytes = _buildFlacWithBlock(
          BlockType.picture, true, Uint8List.fromList(picData));
      final reader = FlacReader.fromBytes(bytes);
      expect(reader.pictures.length, equals(1));
      final pic = reader.pictures.first;
      expect(pic.pictureType, equals(PictureType.coverFront));
      expect(pic.mimeType, equals('image/jpeg'));
      expect(pic.description, equals(''));
      expect(pic.pictureData.length, equals(1));
    });
  });

  group('BitReader', () {
    test('reads individual bits', () {
      final r = BitReader(Uint8List.fromList([0xA5])); // 10100101
      expect(r.readBit(), equals(1));
      expect(r.readBit(), equals(0));
      expect(r.readBit(), equals(1));
      expect(r.readBit(), equals(0));
      expect(r.readBit(), equals(0));
      expect(r.readBit(), equals(1));
      expect(r.readBit(), equals(0));
      expect(r.readBit(), equals(1));
    });

    test('reads multi-byte unsigned value', () {
      final r = BitReader(Uint8List.fromList([0x12, 0x34]));
      expect(r.readBits(16), equals(0x1234));
    });

    test('reads signed negative value', () {
      // 0xFF in 8 bits as signed = -1
      final r = BitReader(Uint8List.fromList([0xFF]));
      expect(r.readSignedBits(8), equals(-1));
    });

    test('reads signed positive value', () {
      // 0x7F in 8 bits = 127
      final r = BitReader(Uint8List.fromList([0x7F]));
      expect(r.readSignedBits(8), equals(127));
    });

    test('reads unary code', () {
      // 00001 → unary = 4
      final r = BitReader(Uint8List.fromList([0x08])); // 0b00001000
      expect(r.readUnary(), equals(4));
    });

    test('reads Rice-coded value', () {
      // Rice(2): value = 3 → zigzag = 6 = 0b110
      // unary(6>>2=1) + binary(6 & 3 = 2, 2 bits) = 0 1 10 = 0b0110
      // Stored: 01 10 xxxx
      // Let's verify with value=3, k=2:
      // uval = 3*2 = 6, msbs = 6>>2 = 1, lsbs = 6 & 3 = 2
      // write: 0b0 1 10 → 0b0110_0000 padded
      // decode: read_unary=1 (one 0, then stop bit 1), read_bits(2)=2
      // uval = (1<<2)|2 = 6, decode: 6>>1=3, -(6&1)=0 → 3 ^ 0 = 3
      final r = BitReader(Uint8List.fromList([0x60])); // 0b01100000
      expect(r.readRice(2), equals(3));
    });

    test('readBytes requires alignment', () {
      final r = BitReader(Uint8List.fromList([0xFF, 0x00]));
      r.readBit(); // now misaligned
      expect(() => r.readBytes(1), throwsStateError);
    });

    test('readByte reads correctly', () {
      final r = BitReader(Uint8List.fromList([0xAB, 0xCD]));
      expect(r.readByte(), equals(0xAB));
      expect(r.readByte(), equals(0xCD));
    });

    test('skipToByteBoundary aligns the reader', () {
      final r = BitReader(Uint8List.fromList([0xFF, 0x42]));
      r.readBits(3);
      r.skipToByteBoundary();
      expect(r.isByteAligned, isTrue);
      expect(r.readByte(), equals(0x42));
    });

    test('UTF-8 coded number: single byte', () {
      final r = BitReader(Uint8List.fromList([0x00]));
      expect(r.readUtf8CodedNumber(), equals(0));
    });

    test('UTF-8 coded number: two-byte sequence (frame number 128)', () {
      // 128 in UTF-8: 0xC2 0x80
      final r = BitReader(Uint8List.fromList([0xC2, 0x80]));
      expect(r.readUtf8CodedNumber(), equals(128));
    });
  });

  group('CRC utilities', () {
    test('crc8 of empty data is 0', () {
      expect(crc8([]), equals(0));
    });

    test('crc8 known value', () {
      // CRC-8 of [0xff, 0xf8, 0x69, 0x88, 0x00, 0x03] = 0x1f
      expect(crc8([0xff, 0xf8, 0x69, 0x88, 0x00, 0x03]), equals(0x1f));
    });

    test('crc16 of empty data is 0', () {
      expect(crc16([]), equals(0));
    });

    test('crc16 known value for frame 0', () {
      // CRC-16 of frame 0 body (all bytes except the last 2) = 0xcaa8
      final frameBody = [
        0xff, 0xf8, 0x69, 0x88, 0x00, 0x03, 0x1f,
        0x00, 0x03, 0xe8, 0x00, 0x02, 0xee, 0x00
      ];
      expect(crc16(frameBody), equals(0xcaa8));
    });
  });

  group('UnknownMetadataBlock', () {
    test('unrecognised block type preserved as UnknownMetadataBlock', () {
      // Type 127 is "invalid" per spec but should be handled gracefully.
      final unknownData = Uint8List.fromList([0xDE, 0xAD]);
      final bytes =
          _buildFlacWithBlock(127, true, unknownData);
      final reader = FlacReader.fromBytes(bytes);
      final unknown = reader.metadataBlocks
          .whereType<UnknownMetadataBlock>()
          .toList();
      expect(unknown.length, equals(1));
      expect(unknown.first.blockType, equals(127));
      expect(unknown.first.rawData, equals(unknownData));
    });
  });

  group('MD5 verification', () {
    // Expected decoded PCM for _minimalFlac:
    //   Frame 0: 4 samples of [left=1000, right=-500]
    //   Frame 1: 4 samples of [left=0, right=0]
    // Written as 16-bit LE signed and interleaved: 32 bytes.
    final expectedPcm = Uint8List.fromList([
      // 4 × (1000, -500) as two int16 LE each
      0xE8, 0x03, 0x0C, 0xFE,
      0xE8, 0x03, 0x0C, 0xFE,
      0xE8, 0x03, 0x0C, 0xFE,
      0xE8, 0x03, 0x0C, 0xFE,
      // 4 × (0, 0)
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0,
    ]);
    final expectedMd5 = Uint8List.fromList(md5.convert(expectedPcm).bytes);

    test('returns match when signature equals computed MD5', () {
      final bytes = _minimalFlacWithMd5(expectedMd5);
      final reader = FlacReader.fromBytes(bytes);
      expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
    });

    test('returns notComputed when signature is all zeros', () {
      // _minimalFlac already has md5 = all zeros.
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.verifyMd5(), equals(Md5VerificationResult.notComputed));
    });

    test('returns mismatch when signature is wrong', () {
      final bogus = Uint8List.fromList(List.filled(16, 0xAA));
      final bytes = _minimalFlacWithMd5(bogus);
      final reader = FlacReader.fromBytes(bytes);
      expect(reader.verifyMd5(), equals(Md5VerificationResult.mismatch));
    });
  });

  group('ID3v2 tolerance', () {
    test('parses a FLAC file preceded by an ID3v2 tag', () {
      // 10-byte ID3v2 header + 20 bytes of dummy tag body.
      const tagBody = 20;
      final id3 = <int>[
        0x49, 0x44, 0x33, // "ID3"
        0x03, 0x00, // version 3.0
        0x00, // flags (no footer)
        // synchsafe size of 20:
        0x00, 0x00, 0x00, 0x14,
      ];
      final buf = Uint8List.fromList([
        ...id3,
        ...List.filled(tagBody, 0x00),
        ..._minimalFlac,
      ]);
      final reader = FlacReader.fromBytes(buf);
      expect(reader.streamInfo.sampleRate, equals(44100));
      // audioDataOffset is measured from the start of the buffer we handed in,
      // so it must account for the skipped ID3v2 prefix.
      expect(reader.audioDataOffset, equals(10 + tagBody + 42));
    });

    test('rejects a buffer that has neither ID3v2 nor fLaC marker', () {
      final bad = Uint8List.fromList(List.filled(16, 0));
      expect(() => FlacReader.fromBytes(bad), throwsFormatException);
    });
  });

  group('Frame resync', () {
    test('strict decode throws on a corrupted frame', () {
      final corrupted = Uint8List.fromList(_minimalFlac);
      // Flip a byte inside the first frame body, after the sync/CRC-8.
      // Byte at offset 51 is in the middle of frame 0's subframe data.
      corrupted[51] ^= 0xFF;
      final reader = FlacReader.fromBytes(corrupted);
      expect(() => reader.decodeFrames(), throwsFormatException);
    });

    test('tolerant decode skips the bad frame and reports it', () {
      final corrupted = Uint8List.fromList(_minimalFlac);
      corrupted[51] ^= 0xFF;
      final reader = FlacReader.fromBytes(corrupted);
      final errors = <int>[];
      final frames = reader.decodeFrames(
        recoverFromCorruption: true,
        onCorruption: (offset, _) => errors.add(offset),
      );
      // With one frame dropped, we expect 0 or 1 surviving frame (depends on
      // whether the tolerant scanner locks onto frame 1's sync). Either way,
      // the error callback must fire at least once.
      expect(errors, isNotEmpty);
      expect(frames.length, lessThan(2));
    });
  });

  group('Seek by sample', () {
    test('byteOffsetForSample(0) points at the first frame', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(reader.byteOffsetForSample(0), equals(reader.audioDataOffset));
    });

    test('byteOffsetForSample crosses into the second frame', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      // Frame 0 has 4 samples → sample 4 is the first sample of frame 1.
      final frameOneOffset = reader.byteOffsetForSample(4);
      expect(frameOneOffset, greaterThan(reader.audioDataOffset));
      // Decoding from that offset should yield frame 1 only.
      final tail = reader.decodeFramesFromSample(4);
      expect(tail.length, equals(1));
      expect(tail.first.channelSamples[0], everyElement(equals(0)));
    });

    test('byteOffsetForSample beyond end throws RangeError', () {
      final reader = FlacReader.fromBytes(_minimalFlac);
      expect(() => reader.byteOffsetForSample(8), throwsRangeError);
      expect(() => reader.byteOffsetForSample(-1), throwsRangeError);
    });
  });

  // -------------------------------------------------------------------------
  // End-to-end decode tests using real .flac fixtures produced by the
  // reference `flac` CLI. These exercise LPC, FIXED, Rice, joint-stereo
  // decorrelation, pre-coded sample-rate/block-size/bps codes, and MD5
  // verification across multiple bit depths — paths that the hand-built
  // CONSTANT-subframe fixtures cannot reach.
  //
  // To regenerate: ./test/fixtures/generate.sh (needs python3 + flac CLI).
  // -------------------------------------------------------------------------
  group('Fixture: stereo 16-bit 44100 Hz', () {
    late FlacReader reader;
    late Uint8List expectedPcm;

    setUp(() {
      reader = FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      expectedPcm =
          File('test/fixtures/stereo_16_44100.pcm').readAsBytesSync();
    });

    test('STREAMINFO', () {
      expect(reader.streamInfo.sampleRate, equals(44100));
      expect(reader.streamInfo.channels, equals(2));
      expect(reader.streamInfo.bitsPerSample, equals(16));
      expect(reader.streamInfo.totalSamples, equals(512));
    });

    test('decoded PCM matches encoder input', () {
      final samples = reader.decodeInterleavedSamples();
      expect(samples.length, equals(1024)); // 512 × 2 channels
      final decodedPcm = _samplesToLePcm(samples, 16);
      expect(decodedPcm, equals(expectedPcm));
    });

    test('MD5 verification passes', () {
      expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
    });
  });

  group('Fixture: mono 8-bit 16000 Hz', () {
    late FlacReader reader;
    late Uint8List expectedPcm;

    setUp(() {
      reader = FlacReader.fromFileSync('test/fixtures/mono_8_16000.flac');
      expectedPcm =
          File('test/fixtures/mono_8_16000.pcm').readAsBytesSync();
    });

    test('STREAMINFO', () {
      expect(reader.streamInfo.sampleRate, equals(16000));
      expect(reader.streamInfo.channels, equals(1));
      expect(reader.streamInfo.bitsPerSample, equals(8));
      expect(reader.streamInfo.totalSamples, equals(256));
    });

    test('decoded PCM matches encoder input', () {
      final samples = reader.decodeInterleavedSamples();
      expect(samples.length, equals(256));
      final decodedPcm = _samplesToLePcm(samples, 8);
      expect(decodedPcm, equals(expectedPcm));
    });

    test('MD5 verification passes', () {
      expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
    });
  });

  group('Fixture: stereo 24-bit 96000 Hz', () {
    late FlacReader reader;
    late Uint8List expectedPcm;

    setUp(() {
      reader = FlacReader.fromFileSync('test/fixtures/stereo_24_96000.flac');
      expectedPcm =
          File('test/fixtures/stereo_24_96000.pcm').readAsBytesSync();
    });

    test('STREAMINFO', () {
      expect(reader.streamInfo.sampleRate, equals(96000));
      expect(reader.streamInfo.channels, equals(2));
      expect(reader.streamInfo.bitsPerSample, equals(24));
      expect(reader.streamInfo.totalSamples, equals(256));
    });

    test('decoded PCM matches encoder input', () {
      final samples = reader.decodeInterleavedSamples();
      expect(samples.length, equals(512)); // 256 × 2 channels
      final decodedPcm = _samplesToLePcm(samples, 24);
      expect(decodedPcm, equals(expectedPcm));
    });

    test('MD5 verification passes', () {
      expect(reader.verifyMd5(), equals(Md5VerificationResult.match));
    });
  });

  // -------------------------------------------------------------------------
  // Hand-built fixtures for the remaining features. These use only CONSTANT
  // subframes so the byte layout is small and easy to reason about.
  // -------------------------------------------------------------------------
  group('Decorrelation: rightSide', () {
    test('decoder reconstructs independent left/right', () {
      // Frame encodes ch0=side(-300), ch1=right(700) with channel assignment 9.
      // Decorrelation: left = side + right = 400, right = 700.
      final bytes = _buildFlacFromStreamInfoAndFrames(
        sampleRate: 44100,
        channels: 2,
        bitsPerSample: 16,
        totalSamples: 4,
        frames: [
          _buildConstantStereoFrame(
            channelAssignment: 9, // rightSide
            ch0Value: -300, // side
            ch1Value: 700, // right
            blockSize: 4,
            bitsPerSample: 16,
            sampleRate: 44100,
          ),
        ],
      );
      final reader = FlacReader.fromBytes(bytes);
      final frame = reader.decodeFrames().single;
      expect(frame.channelSamples[0], everyElement(equals(400)),
          reason: 'left = side + right');
      expect(frame.channelSamples[1], everyElement(equals(700)));
    });
  });

  group('Decorrelation: midSide', () {
    test('decoder reconstructs independent left/right from mid/side', () {
      // ch0=mid, ch1=side. For left=500, right=300: side = 200, mid = 400.
      final bytes = _buildFlacFromStreamInfoAndFrames(
        sampleRate: 44100,
        channels: 2,
        bitsPerSample: 16,
        totalSamples: 4,
        frames: [
          _buildConstantStereoFrame(
            channelAssignment: 10, // midSide
            ch0Value: 400, // mid
            ch1Value: 200, // side
            blockSize: 4,
            bitsPerSample: 16,
            sampleRate: 44100,
          ),
        ],
      );
      final reader = FlacReader.fromBytes(bytes);
      final frame = reader.decodeFrames().single;
      expect(frame.channelSamples[0], everyElement(equals(500)));
      expect(frame.channelSamples[1], everyElement(equals(300)));
    });
  });

  group('Seek with SEEKTABLE hint', () {
    test('uses seek-table offset matching linear-scan result', () {
      // Use the real stereo_16_44100 fixture which has multiple frames.
      // Seek to the middle of the file and verify the returned offset is
      // a valid frame start (sync code) and that decoded samples from
      // that offset agree with the tail of the full decode.
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final full = reader.decodeInterleavedSamples();

      // Pick a sample inside the stream (sample 256, midway).
      final offset = reader.byteOffsetForSample(256);
      // Offset must land on a frame sync code (0xFF 0xF8..0xFB).
      // We can't access _data directly, but we can re-parse from that offset.
      final tail = reader.decodeFramesFromSample(256);
      final tailPcm = <int>[];
      for (final f in tail) {
        for (var s = 0; s < f.blockSize; s++) {
          for (var c = 0; c < f.channelCount; c++) {
            tailPcm.add(f.channelSamples[c][s]);
          }
        }
      }
      // The tail must be a contiguous suffix of the full decode.
      final start = full.length - tailPcm.length;
      expect(start, greaterThanOrEqualTo(0));
      for (var i = 0; i < tailPcm.length; i++) {
        expect(full[start + i], equals(tailPcm[i]),
            reason: 'mismatch at tail index $i');
      }
      expect(offset, greaterThan(reader.audioDataOffset));
    });
  });

  group('CueSheet', () {
    test('parses catalog number, lead-in, tracks, and indices', () {
      // Build a CUESHEET block with 1 track + 1 index, plus the mandatory
      // lead-out track (track number 170 for CD).
      final cs = <int>[];
      // Media catalog number: 128 ASCII bytes, right-padded with 0.
      final catalog = '1234567890123'.codeUnits;
      cs.addAll(catalog);
      cs.addAll(List.filled(128 - catalog.length, 0));
      // Lead-in samples (64-bit BE) = 88200 (2 seconds @ 44100).
      cs.addAll(_u64be(88200));
      // is-CD flag (bit 7) + 7 reserved bits, then 258 reserved bytes.
      cs.add(0x80);
      cs.addAll(List.filled(258, 0));
      // Number of tracks = 2 (track 1 + lead-out).
      cs.add(2);

      // Track 1: offset=0, number=1, ISRC=12 bytes, flags=0, 13 reserved, 1 index.
      cs.addAll(_u64be(0));
      cs.add(1);
      final isrc = 'US-S1Z-00-001'.codeUnits.take(12).toList();
      cs.addAll(isrc);
      cs.addAll(List.filled(12 - isrc.length, 0));
      cs.add(0); // flags
      cs.addAll(List.filled(13, 0)); // reserved
      cs.add(1); // index count
      // Index 1: offset=0, number=1, 3 reserved.
      cs.addAll(_u64be(0));
      cs.add(1);
      cs.addAll(List.filled(3, 0));

      // Lead-out track: offset=256, number=170 (CD lead-out), 12 ISRC, flags, 13 reserved, 0 indices.
      cs.addAll(_u64be(256));
      cs.add(170);
      cs.addAll(List.filled(12, 0));
      cs.add(0);
      cs.addAll(List.filled(13, 0));
      cs.add(0);

      final bytes = _buildFlacWithBlock(
          BlockType.cueSheet, true, Uint8List.fromList(cs));
      final reader = FlacReader.fromBytes(bytes);
      final cuesheet = reader.cueSheet;
      expect(cuesheet, isNotNull);
      expect(cuesheet!.leadInSamples, equals(88200));
      expect(cuesheet.isCD, isTrue);
      expect(cuesheet.tracks.length, equals(2));
      expect(cuesheet.tracks[0].trackNumber, equals(1));
      expect(cuesheet.tracks[0].isrc.startsWith('US-S1Z-00'), isTrue);
      expect(cuesheet.tracks[0].indices.length, equals(1));
      expect(cuesheet.tracks[1].trackNumber, equals(170));
    });
  });

  group('Wasted bits', () {
    test('decoder left-shifts samples by wasted-bit count', () {
      // Build a CONSTANT subframe with wasted-bits = 3. The encoded value
      // should be left-shifted by 3 after decoding.
      // Effective bits = 16 - 3 = 13. Encode raw value = 100.
      // Decoded sample should be 100 << 3 = 800.
      final frame = _buildConstantMonoFrameWithWastedBits(
        rawValue: 100,
        wastedBits: 3,
        blockSize: 4,
        bitsPerSample: 16,
        sampleRate: 44100,
      );
      final bytes = _buildFlacFromStreamInfoAndFrames(
        sampleRate: 44100,
        channels: 1,
        bitsPerSample: 16,
        totalSamples: 4,
        frames: [frame],
      );
      final reader = FlacReader.fromBytes(bytes);
      final decoded = reader.decodeFrames().single;
      expect(decoded.channelSamples[0], everyElement(equals(800)));
    });
  });

  group('ID3v2 with footer flag', () {
    test('skips both the header and the footer', () {
      const tagBody = 10;
      final id3 = <int>[
        0x49, 0x44, 0x33,
        0x04, 0x00, // version 4
        0x10, // footer-present flag (bit 4)
        0x00, 0x00, 0x00, 0x0A, // synchsafe size = 10
      ];
      final buf = Uint8List.fromList([
        ...id3,
        ...List.filled(tagBody, 0),
        ...List.filled(10, 0), // 10-byte footer
        ..._minimalFlac,
      ]);
      final reader = FlacReader.fromBytes(buf);
      expect(reader.streamInfo.sampleRate, equals(44100));
      expect(reader.audioDataOffset, equals(10 + tagBody + 10 + 42));
    });
  });

  group('framesLazy', () {
    test('yields the same frames as decodeFrames', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final lazy = reader.framesLazy().toList();
      final eager = reader.decodeFrames();
      expect(lazy.length, equals(eager.length));
      for (var i = 0; i < lazy.length; i++) {
        expect(lazy[i].blockSize, equals(eager[i].blockSize));
        expect(lazy[i].channelSamples[0], equals(eager[i].channelSamples[0]));
        expect(lazy[i].channelSamples[1], equals(eager[i].channelSamples[1]));
      }
    });

    test('can stop after the first frame', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final first = reader.framesLazy().first;
      expect(first.blockSize, equals(128));
    });

    test('take(n) only decodes n frames', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final two = reader.framesLazy().take(2).toList();
      expect(two.length, equals(2));
    });
  });

  group('StreamingFlacDecoder', () {
    test('byte-by-byte ingest produces identical frames to batch decode',
        () async {
      final bytes =
          File('test/fixtures/stereo_16_44100.flac').readAsBytesSync();
      final reference = FlacReader.fromBytes(bytes).decodeFrames();

      final decoder = StreamingFlacDecoder();
      final collected = <FlacFrame>[];
      final sub = decoder.frames.listen(collected.add);

      // Feed in small variably-sized chunks to exercise the buffering.
      for (var i = 0; i < bytes.length; i += 37) {
        final end = (i + 37).clamp(0, bytes.length);
        decoder.addBytes(Uint8List.sublistView(bytes, i, end));
      }
      decoder.close();
      await sub.asFuture<void>();

      expect(collected.length, equals(reference.length));
      for (var f = 0; f < reference.length; f++) {
        expect(collected[f].blockSize, equals(reference[f].blockSize));
        for (var c = 0; c < reference[f].channelCount; c++) {
          expect(collected[f].channelSamples[c],
              equals(reference[f].channelSamples[c]),
              reason: 'frame $f channel $c sample mismatch');
        }
      }
    });

    test('emits STREAMINFO via onStreamInfo before frames', () async {
      final bytes =
          File('test/fixtures/stereo_16_44100.flac').readAsBytesSync();
      final decoder = StreamingFlacDecoder();
      final info = decoder.onStreamInfo;
      // Feed just the metadata region (everything up to the first frame).
      final reader = FlacReader.fromBytes(bytes);
      decoder.addBytes(
          Uint8List.sublistView(bytes, 0, reader.audioDataOffset));
      final streamInfo = await info;
      expect(streamInfo.sampleRate, equals(44100));
      expect(streamInfo.channels, equals(2));
      decoder.close();
    });

    test('tolerates leading ID3v2 tag fed in pieces', () async {
      final flac = _minimalFlac;
      final id3 = <int>[
        0x49, 0x44, 0x33, 0x03, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x05, // synchsafe size 5
        0, 0, 0, 0, 0, // 5-byte body
      ];
      final combined = Uint8List.fromList([...id3, ...flac]);

      final decoder = StreamingFlacDecoder();
      final frames = <FlacFrame>[];
      final sub = decoder.frames.listen(frames.add);

      // Feed one byte at a time — worst case for the buffering logic.
      for (final b in combined) {
        decoder.addBytes(Uint8List.fromList([b]));
      }
      decoder.close();
      await sub.asFuture<void>();

      final info = await decoder.onStreamInfo;
      expect(info.sampleRate, equals(44100));
      expect(frames.length, equals(2));
    });
  });

  group('pcmChunks', () {
    test('concatenated chunks equal the encoder input PCM', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final expected =
          File('test/fixtures/stereo_16_44100.pcm').readAsBytesSync();
      final builder = BytesBuilder(copy: false);
      for (final chunk in reader.pcmChunks()) {
        builder.add(chunk);
      }
      expect(builder.takeBytes(), equals(expected));
    });

    test('is lazy – take(1) only decodes one frame', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final first = reader.pcmChunks().first;
      // First frame at blocksize 128, stereo 16-bit = 512 bytes.
      expect(first.length, equals(128 * 2 * 2));
    });

    test('outputBitsPerSample override truncates a 24-bit source to 16-bit',
        () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_24_96000.flac');
      final builder = BytesBuilder(copy: false);
      for (final chunk in reader.pcmChunks(outputBitsPerSample: 16)) {
        builder.add(chunk);
      }
      final truncated = builder.takeBytes();
      // 256 samples × 2 channels × 2 bytes = 1024.
      expect(truncated.length, equals(256 * 2 * 2));
    });
  });

  group('StreamingFlacDecoder.pcmStream', () {
    test('delivers the same bytes as FlacReader.pcmChunks', () async {
      final flacBytes =
          File('test/fixtures/stereo_16_44100.flac').readAsBytesSync();
      final reader = FlacReader.fromBytes(flacBytes);
      final expected = BytesBuilder(copy: false);
      for (final c in reader.pcmChunks()) {
        expected.add(c);
      }

      final decoder = StreamingFlacDecoder();
      final gotBuilder = BytesBuilder(copy: false);
      final sub = decoder
          .pcmStream(outputBitsPerSample: reader.streamInfo.bitsPerSample)
          .listen(gotBuilder.add);

      for (var i = 0; i < flacBytes.length; i += 256) {
        final end = (i + 256).clamp(0, flacBytes.length);
        decoder.addBytes(Uint8List.sublistView(flacBytes, i, end));
      }
      decoder.close();
      await sub.asFuture<void>();

      expect(gotBuilder.takeBytes(), equals(expected.takeBytes()));
    });
  });

  group('writeWavBytes', () {
    test('produces a RIFF/WAVE buffer whose PCM equals the encoder input',
        () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/stereo_16_44100.flac');
      final originalPcm =
          File('test/fixtures/stereo_16_44100.pcm').readAsBytesSync();

      final wav = writeWavBytes(
        frames: reader.decodeFrames(),
        sampleRate: reader.streamInfo.sampleRate,
        channels: reader.streamInfo.channels,
        bitsPerSample: reader.streamInfo.bitsPerSample,
      );

      // Header checks.
      expect(wav.length, equals(44 + originalPcm.length));
      expect(String.fromCharCodes(wav.sublist(0, 4)), equals('RIFF'));
      expect(String.fromCharCodes(wav.sublist(8, 12)), equals('WAVE'));
      expect(String.fromCharCodes(wav.sublist(12, 16)), equals('fmt '));
      // Payload equals the original PCM byte for byte.
      expect(wav.sublist(44), equals(originalPcm));
    });

    test('8-bit WAV applies the unsigned bias', () {
      final reader =
          FlacReader.fromFileSync('test/fixtures/mono_8_16000.flac');
      final originalSignedPcm =
          File('test/fixtures/mono_8_16000.pcm').readAsBytesSync();

      final wav = writeWavBytes(
        frames: reader.decodeFrames(),
        sampleRate: reader.streamInfo.sampleRate,
        channels: reader.streamInfo.channels,
        bitsPerSample: reader.streamInfo.bitsPerSample,
      );

      // WAV body should be the signed PCM shifted by +128.
      final body = wav.sublist(44);
      expect(body.length, equals(originalSignedPcm.length));
      for (var i = 0; i < body.length; i++) {
        final signed = originalSignedPcm[i].toSigned(8);
        expect(body[i], equals((signed + 128) & 0xFF));
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers for fixture-based and hand-built frame tests.
// ---------------------------------------------------------------------------

/// Encodes interleaved PCM [samples] as little-endian signed bytes at
/// [bitsPerSample] (rounded up to the next whole byte).
Uint8List _samplesToLePcm(Int32List samples, int bitsPerSample) {
  final bytesPerSample = (bitsPerSample + 7) ~/ 8;
  final mask = bytesPerSample == 4 ? 0xFFFFFFFF : (1 << (bytesPerSample * 8)) - 1;
  final out = Uint8List(samples.length * bytesPerSample);
  var o = 0;
  for (final s in samples) {
    final v = s & mask;
    for (var b = 0; b < bytesPerSample; b++) {
      out[o++] = (v >> (b * 8)) & 0xFF;
    }
  }
  return out;
}

/// Returns an 8-byte big-endian representation of [v] as a list of ints.
List<int> _u64be(int v) {
  final out = List<int>.filled(8, 0);
  for (var i = 7; i >= 0; i--) {
    out[i] = v & 0xFF;
    v >>= 8;
  }
  return out;
}

/// Wraps frame-body bytes in a STREAMINFO-only FLAC container.
Uint8List _buildFlacFromStreamInfoAndFrames({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int totalSamples,
  required List<List<int>> frames,
}) {
  final si = _encodeStreamInfo(
    minBlockSize: 4,
    maxBlockSize: 4,
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: bitsPerSample,
    totalSamples: totalSamples,
  );
  return Uint8List.fromList([
    0x66, 0x4c, 0x61, 0x43, // fLaC
    0x80, 0x00, 0x00, 0x22, // STREAMINFO header: is_last=1, type=0, len=34
    ...si,
    for (final f in frames) ...f,
  ]);
}

/// Encodes a 34-byte STREAMINFO data body with the given parameters.
List<int> _encodeStreamInfo({
  required int minBlockSize,
  required int maxBlockSize,
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int totalSamples,
}) {
  final bw = _BitWriter();
  bw.writeBits(minBlockSize, 16);
  bw.writeBits(maxBlockSize, 16);
  bw.writeBits(0, 24); // min frame size unknown
  bw.writeBits(0, 24); // max frame size unknown
  bw.writeBits(sampleRate, 20);
  bw.writeBits(channels - 1, 3);
  bw.writeBits(bitsPerSample - 1, 5);
  bw.writeBits(totalSamples >> 32, 4);
  bw.writeBits(totalSamples & 0xFFFFFFFF, 32);
  final body = bw.toBytes();
  return [...body, ...List.filled(16, 0)]; // MD5 all-zero
}

/// Builds a single FLAC audio frame with two CONSTANT subframes, encoded
/// using the given stereo channel assignment (8 = left/side, 9 = right/side,
/// 10 = mid/side).
List<int> _buildConstantStereoFrame({
  required int channelAssignment,
  required int ch0Value,
  required int ch1Value,
  required int blockSize,
  required int bitsPerSample,
  required int sampleRate,
}) {
  final bw = _BitWriter();
  // Frame header.
  bw.writeBits(0x3FFE, 14); // sync
  bw.writeBit(0); // reserved
  bw.writeBit(0); // fixed blocksize
  // Block size code 0x7 (16-bit follow-up).
  bw.writeBits(0x7, 4);
  // Sample rate: pre-coded 44100 = 0x9.
  assert(sampleRate == 44100);
  bw.writeBits(0x9, 4);
  // Channel assignment.
  bw.writeBits(channelAssignment, 4);
  // Bits per sample: 16 = 0x4.
  assert(bitsPerSample == 16);
  bw.writeBits(0x4, 3);
  bw.writeBit(0); // reserved
  // UTF-8 frame number 0.
  bw.writeBits(0x00, 8);
  // Block-size follow-up: blockSize-1 in 16 bits.
  bw.writeBits(blockSize - 1, 16);

  // CRC-8 over the header bytes written so far.
  bw.alignToByte();
  final header = bw.toBytes();
  final headerCrc = _crc8(header);
  final bw2 = _BitWriter()..writeAllBytes(header)..writeBits(headerCrc, 8);

  // Subframe 0: CONSTANT, no wasted bits, value at bitsPerSample (+1 if side).
  final ch0Bits =
      bitsPerSample + _sideExtra(channelAssignment, 0);
  bw2.writeBit(0); // zero padding
  bw2.writeBits(0, 6); // type code 0 = CONSTANT
  bw2.writeBit(0); // no wasted bits
  bw2.writeSignedBits(ch0Value, ch0Bits);

  // Subframe 1.
  final ch1Bits =
      bitsPerSample + _sideExtra(channelAssignment, 1);
  bw2.writeBit(0);
  bw2.writeBits(0, 6);
  bw2.writeBit(0);
  bw2.writeSignedBits(ch1Value, ch1Bits);

  // Byte-align for footer CRC-16.
  bw2.alignToByte();
  final body = bw2.toBytes();
  final crc16 = _crc16(body);
  return [...body, (crc16 >> 8) & 0xFF, crc16 & 0xFF];
}

/// Builds a single mono frame with one CONSTANT subframe that has wasted bits.
List<int> _buildConstantMonoFrameWithWastedBits({
  required int rawValue,
  required int wastedBits,
  required int blockSize,
  required int bitsPerSample,
  required int sampleRate,
}) {
  final bw = _BitWriter();
  bw.writeBits(0x3FFE, 14);
  bw.writeBit(0);
  bw.writeBit(0);
  bw.writeBits(0x7, 4); // 16-bit follow-up blocksize
  bw.writeBits(0x9, 4); // 44100
  bw.writeBits(0, 4); // independent, 1 channel
  bw.writeBits(0x4, 3); // 16-bit
  bw.writeBit(0);
  bw.writeBits(0x00, 8); // frame number 0
  bw.writeBits(blockSize - 1, 16);
  bw.alignToByte();
  final hdr = bw.toBytes();
  final crc = _crc8(hdr);
  final bw2 = _BitWriter()..writeAllBytes(hdr)..writeBits(crc, 8);

  // Subframe: zero bit, type=0 CONSTANT, wasted-bits flag=1,
  // unary encoding of (wastedBits - 1) + trailing 1.
  bw2.writeBit(0);
  bw2.writeBits(0, 6);
  bw2.writeBit(1); // wasted bits present
  for (var i = 0; i < wastedBits - 1; i++) {
    bw2.writeBit(0);
  }
  bw2.writeBit(1);
  // Value at effective width = bitsPerSample - wastedBits.
  bw2.writeSignedBits(rawValue, bitsPerSample - wastedBits);

  bw2.alignToByte();
  final body = bw2.toBytes();
  final crc16 = _crc16(body);
  return [...body, (crc16 >> 8) & 0xFF, crc16 & 0xFF];
}

int _sideExtra(int assignment, int channel) {
  if (assignment == 8 && channel == 1) return 1;
  if (assignment == 9 && channel == 0) return 1;
  if (assignment == 10 && channel == 1) return 1;
  return 0;
}

// Re-implemented CRC-8 / CRC-16 helpers for test-side frame construction.
// (The library versions are private to the src tree.)
int _crc8(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

int _crc16(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= (b << 8);
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ 0x8005) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
  }
  return crc;
}

/// Minimal big-endian bit writer used by hand-built frame fixtures.
class _BitWriter {
  final List<int> _bytes = [];
  int _cur = 0;
  int _bitPos = 0; // 0..7, number of bits already written in _cur from MSB.

  void writeBit(int bit) {
    _cur |= (bit & 1) << (7 - _bitPos);
    _bitPos++;
    if (_bitPos == 8) {
      _bytes.add(_cur);
      _cur = 0;
      _bitPos = 0;
    }
  }

  void writeBits(int value, int n) {
    for (var i = n - 1; i >= 0; i--) {
      writeBit((value >> i) & 1);
    }
  }

  void writeSignedBits(int value, int n) {
    final mask = n == 32 ? 0xFFFFFFFF : (1 << n) - 1;
    writeBits(value & mask, n);
  }

  void alignToByte() {
    if (_bitPos != 0) {
      _bytes.add(_cur);
      _cur = 0;
      _bitPos = 0;
    }
  }

  void writeAllBytes(List<int> bytes) {
    assert(_bitPos == 0);
    _bytes.addAll(bytes);
  }

  List<int> toBytes() {
    assert(_bitPos == 0, 'writer not byte-aligned');
    return List.of(_bytes);
  }
}

/// Returns a copy of [_minimalFlac] with STREAMINFO.md5 replaced by [md5].
Uint8List _minimalFlacWithMd5(Uint8List md5) {
  assert(md5.length == 16);
  // STREAMINFO body starts at offset 8; md5 is its final 16 bytes (26..41).
  final out = Uint8List.fromList(_minimalFlac);
  for (var i = 0; i < 16; i++) {
    out[26 + i] = md5[i];
  }
  return out;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the 34-byte STREAMINFO data for 44100 Hz, 2-ch, 16-bit, 8 samples.
List<int> _buildStreamInfoBytes() {
  // min_block_size=4 (16-bit), max_block_size=4 (16-bit),
  // min_frame_size=0 (24-bit), max_frame_size=0 (24-bit),
  // sample_rate=44100 (20-bit) = 0xAC44,
  // channels-1=1 (3-bit), bps-1=15 (5-bit),
  // total_samples=8 (36-bit), md5=0 (128-bit)
  return [
    0x00, 0x04, 0x00, 0x04,          // min_bs=4, max_bs=4
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // min_fs=0, max_fs=0
    0x0a, 0xc4, 0x42, 0xf0,          // sr=44100, ch=2, bps=16
    0x00, 0x00, 0x00, 0x08,          // total_samples=8 (low 32 bits of 36-bit)
    // MD5 (16 bytes)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ];
}

/// Builds a minimal FLAC byte buffer that starts with the stream marker and
/// a non-last STREAMINFO block, followed by a single metadata block of [type]
/// with [data].
Uint8List _buildFlacWithBlock(int type, bool isLast, Uint8List data) {
  final si = _buildStreamInfoBytes();
  // STREAMINFO header: is_last=0, type=0, length=34
  final siHeader = [0x00, 0x00, 0x00, 0x22];

  final blockIsLast = isLast ? 0x80 : 0x00;
  final blockHeader = [
    blockIsLast | (type & 0x7F),
    (data.length >> 16) & 0xFF,
    (data.length >> 8) & 0xFF,
    data.length & 0xFF,
  ];

  return Uint8List.fromList([
    0x66, 0x4c, 0x61, 0x43, // fLaC
    ...siHeader, ...si,
    ...blockHeader, ...data,
  ]);
}
