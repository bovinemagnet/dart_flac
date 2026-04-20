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
