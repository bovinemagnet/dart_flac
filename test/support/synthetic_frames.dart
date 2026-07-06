// Hand-built FLAC stream builders shared by the browser smoke test.
//
// Everything here is web-safe: no bitwise operation ever sees a value wider
// than 31 bits, so the builders produce identical bytes under dart2js
// (where bitwise operators wrap at 32 bits) and on the VM.
library;

import 'dart:typed_data';

/// 2^n as an exact integer without a ≥32-bit shift.
int pow2(int n) => n <= 30 ? 1 << n : (1 << 30) * pow2(n - 30);

/// Minimal big-endian bit writer for hand-built frames.
class BitWriter {
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

  /// Writes the low [n] bits of a non-negative [value], MSB first.
  void writeBits(int value, int n) {
    assert(value >= 0);
    for (var i = n - 1; i >= 0; i--) {
      writeBit((value ~/ pow2(i)) & 1);
    }
  }

  /// Writes a signed [value] as [n]-bit two's complement.
  void writeSignedBits(int value, int n) {
    writeBits(value < 0 ? value + pow2(n) : value, n);
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

/// CRC-8 (poly 0x07) over [data], as used by FLAC frame headers.
int crc8(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ 0x07) & 0xFF : (crc << 1) & 0xFF;
    }
  }
  return crc;
}

/// CRC-16 (poly 0x8005) over [data], as used by FLAC frame footers.
int crc16(List<int> data) {
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

/// Wraps [frames] in a stream marker and a last STREAMINFO block.
Uint8List buildFlacFromStreamInfoAndFrames({
  required int sampleRate,
  required int channels,
  required int bitsPerSample,
  required int totalSamples,
  required List<List<int>> frames,
}) {
  final bw = BitWriter();
  bw.writeBits(4, 16); // min block size
  bw.writeBits(4, 16); // max block size
  bw.writeBits(0, 24); // min frame size unknown
  bw.writeBits(0, 24); // max frame size unknown
  bw.writeBits(sampleRate, 20);
  bw.writeBits(channels - 1, 3);
  bw.writeBits(bitsPerSample - 1, 5);
  bw.writeBits(totalSamples ~/ pow2(32), 4);
  bw.writeBits(totalSamples % pow2(32), 32);
  final si = [...bw.toBytes(), ...List.filled(16, 0)];
  return Uint8List.fromList([
    0x66, 0x4c, 0x61, 0x43, // fLaC
    0x80, 0x00, 0x00, 0x22, // STREAMINFO header: is_last=1, type=0, len=34
    ...si,
    for (final f in frames) ...f,
  ]);
}

/// Writes the shared 32-bit 44100 Hz frame-header prefix and returns a
/// writer positioned just after the header CRC-8.
BitWriter _frameHeader({required int blockSize, required int channelBits}) {
  final bw = BitWriter();
  bw.writeBits(0x3FFE, 14); // sync
  bw.writeBit(0); // reserved
  bw.writeBit(0); // fixed blocksize
  bw.writeBits(0x7, 4); // 16-bit follow-up blocksize
  bw.writeBits(0x9, 4); // 44100
  bw.writeBits(channelBits, 4);
  bw.writeBits(0x7, 3); // 32-bit samples
  bw.writeBit(0); // reserved
  bw.writeBits(0x00, 8); // UTF-8 frame number 0
  bw.writeBits(blockSize - 1, 16);
  bw.alignToByte();
  final hdr = bw.toBytes();
  return BitWriter()
    ..writeAllBytes(hdr)
    ..writeBits(crc8(hdr), 8);
}

List<int> _finishFrame(BitWriter bw) {
  bw.alignToByte();
  final body = bw.toBytes();
  final c = crc16(body);
  return [...body, (c >> 8) & 0xFF, c & 0xFF];
}

/// A 32-bit mid/side stereo frame with two CONSTANT subframes: [mid] at
/// 32 bits and [side] at 33 bits.
List<int> buildConstantMidSideFrame32({
  required int mid,
  required int side,
  required int blockSize,
}) {
  final bw = _frameHeader(blockSize: blockSize, channelBits: 10);
  bw.writeBit(0); // zero padding
  bw.writeBits(0, 6); // CONSTANT
  bw.writeBit(0); // no wasted bits
  bw.writeSignedBits(mid, 32);
  bw.writeBit(0);
  bw.writeBits(0, 6);
  bw.writeBit(0);
  bw.writeSignedBits(side, 33);
  return _finishFrame(bw);
}

/// A 32-bit mono frame with one LPC order-1 subframe: warm-up [warmUp],
/// a single coefficient [coefficient] at 4-bit precision, shift [shift],
/// and all-zero Rice residuals.
List<int> buildLpcMonoFrame32({
  required int warmUp,
  required int coefficient,
  required int shift,
  required int blockSize,
}) {
  final bw = _frameHeader(blockSize: blockSize, channelBits: 0);
  bw.writeBit(0);
  bw.writeBits(0x20, 6); // LPC order 1
  bw.writeBit(0); // no wasted bits
  bw.writeSignedBits(warmUp, 32);
  bw.writeBits(3, 4); // precision 4
  bw.writeSignedBits(shift, 5);
  bw.writeSignedBits(coefficient, 4);
  // Residual: Rice method 0, partition order 0, parameter 0; each zero
  // residual is a single stop bit.
  bw.writeBits(0, 2);
  bw.writeBits(0, 4);
  bw.writeBits(0, 4);
  for (var i = 0; i < blockSize - 1; i++) {
    bw.writeBit(1);
  }
  return _finishFrame(bw);
}

/// A 32-bit left/side stereo frame: channel 0 is a CONSTANT [left] at
/// 32 bits, channel 1 a FIXED order-0 subframe whose 33-bit side samples
/// [sideValues] are Rice2-coded (coding method 1) with [riceParam].
List<int> buildLeftSideRice2Frame32({
  required int left,
  required List<int> sideValues,
  required int riceParam,
}) {
  final bw = _frameHeader(blockSize: sideValues.length, channelBits: 8);
  bw.writeBit(0); // zero padding
  bw.writeBits(0, 6); // CONSTANT
  bw.writeBit(0); // no wasted bits
  bw.writeSignedBits(left, 32);
  bw.writeBit(0);
  bw.writeBits(8, 6); // FIXED order 0
  bw.writeBit(0); // no wasted bits
  bw.writeBits(1, 2); // Rice method 1 (5-bit parameters)
  bw.writeBits(0, 4); // partition order 0
  bw.writeBits(riceParam, 5);
  for (final v in sideValues) {
    // Zigzag encode, then unary msbs + riceParam-bit lsbs.
    final uval = v >= 0 ? v * 2 : -v * 2 - 1;
    final msbs = uval ~/ pow2(riceParam);
    final lsbs = uval % pow2(riceParam);
    for (var i = 0; i < msbs; i++) {
      bw.writeBit(0);
    }
    bw.writeBit(1);
    bw.writeBits(lsbs, riceParam);
  }
  return _finishFrame(bw);
}

/// A FLAC stream whose only extra metadata block is a PICTURE with the
/// given [width] and [height] and no image data.
Uint8List buildFlacWithPicture({required int width, required int height}) {
  final pic = <int>[
    0, 0, 0, 3, // picture type: cover (front)
    0, 0, 0, 0, // MIME length 0
    0, 0, 0, 0, // description length 0
    ..._uint32BE(width),
    ..._uint32BE(height),
    0, 0, 0, 0, // colour depth
    0, 0, 0, 0, // colours used
    0, 0, 0, 0, // picture data length 0
  ];
  final bw = BitWriter();
  bw.writeBits(4, 16);
  bw.writeBits(4, 16);
  bw.writeBits(0, 24);
  bw.writeBits(0, 24);
  bw.writeBits(44100, 20);
  bw.writeBits(1, 3); // 2 channels
  bw.writeBits(15, 5); // 16-bit
  bw.writeBits(0, 4);
  bw.writeBits(0, 32);
  final si = [...bw.toBytes(), ...List.filled(16, 0)];
  return Uint8List.fromList([
    0x66, 0x4c, 0x61, 0x43, // fLaC
    0x00, 0x00, 0x00, 0x22, ...si, // STREAMINFO (not last)
    0x86, 0x00, 0x00, pic.length, ...pic, // PICTURE (is last)
  ]);
}

List<int> _uint32BE(int v) => [
      (v ~/ pow2(24)) & 0xFF,
      (v ~/ pow2(16)) & 0xFF,
      (v ~/ pow2(8)) & 0xFF,
      v & 0xFF,
    ];
