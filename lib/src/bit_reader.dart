import 'dart:typed_data';

/// A reader that can read individual bits from a [Uint8List] byte buffer.
///
/// Supports reading arbitrary-width integers, signed values, UTF-8 coded
/// numbers, and unary (tally) coded integers as required by the FLAC format.
class BitReader {
  final Uint8List _data;
  int _bytePos;
  int _bitPos; // 0 = most significant bit of current byte

  BitReader(this._data)
      : _bytePos = 0,
        _bitPos = 0;

  /// Creates a [BitReader] positioned at the given byte offset.
  BitReader.atOffset(this._data, int offset)
      : _bytePos = offset,
        _bitPos = 0;

  /// Current byte position (number of fully consumed bytes).
  int get bytePosition => _bytePos;

  /// Whether the reader is aligned to a byte boundary.
  bool get isByteAligned => _bitPos == 0;

  /// Total number of bits consumed so far.
  int get bitsConsumed => _bytePos * 8 + _bitPos;

  /// Number of bits remaining in the buffer.
  int get bitsRemaining => (_data.length - _bytePos) * 8 - _bitPos;

  /// Reads [n] bits as an unsigned integer (0 ≤ n ≤ 32).
  int readBits(int n) {
    assert(n >= 0 && n <= 32);
    if (n == 0) return 0;

    var result = 0;
    var remaining = n;

    while (remaining > 0) {
      if (_bytePos >= _data.length) {
        throw StateError(
            'Not enough data: tried to read $n bits but only '
            '${(_data.length * 8) - bitsConsumed + remaining} bits remain.');
      }
      final bitsInByte = 8 - _bitPos;
      final take = remaining < bitsInByte ? remaining : bitsInByte;
      final shift = bitsInByte - take;
      final mask = (1 << take) - 1;
      result = (result << take) | ((_data[_bytePos] >> shift) & mask);
      _bitPos += take;
      if (_bitPos == 8) {
        _bitPos = 0;
        _bytePos++;
      }
      remaining -= take;
    }
    return result;
  }

  /// Reads [n] bits as a signed integer using two's complement.
  int readSignedBits(int n) {
    assert(n > 0 && n <= 32);
    final val = readBits(n);
    if (n < 32 && (val & (1 << (n - 1))) != 0) {
      return val - (1 << n);
    }
    return val;
  }

  /// Reads a single bit (0 or 1).
  int readBit() => readBits(1);

  /// Reads a single boolean bit.
  bool readFlag() => readBits(1) == 1;

  /// Reads [n] bytes and returns them as a [Uint8List].
  ///
  /// The reader must be byte-aligned before calling this method.
  Uint8List readBytes(int n) {
    if (!isByteAligned) {
      throw StateError('readBytes requires byte alignment.');
    }
    if (_bytePos + n > _data.length) {
      throw StateError('Not enough data to read $n bytes.');
    }
    final result = _data.sublist(_bytePos, _bytePos + n);
    _bytePos += n;
    return result;
  }

  /// Reads a single byte (requires byte alignment).
  int readByte() {
    if (!isByteAligned) {
      throw StateError('readByte requires byte alignment.');
    }
    if (_bytePos >= _data.length) {
      throw StateError('End of data.');
    }
    return _data[_bytePos++];
  }

  /// Reads an unary-coded non-negative integer: counts the number of 0 bits
  /// before the first 1 bit (stop bit).
  int readUnary() {
    var count = 0;
    while (readBit() == 0) {
      count++;
    }
    return count;
  }

  /// Reads a Rice-coded signed integer with the given Rice parameter [k].
  int readRice(int k) {
    final msbs = readUnary();
    final lsbs = readBits(k);
    final uval = (msbs << k) | lsbs;
    // Zigzag decode: even -> positive, odd -> negative
    return (uval >> 1) ^ -(uval & 1);
  }

  /// Reads a UTF-8 coded number as used in FLAC frame headers.
  ///
  /// Returns an integer up to 36 bits wide.
  int readUtf8CodedNumber() {
    final first = readByte();
    if (first < 0x80) return first;

    int extraBytes;
    int value;
    if ((first & 0xFE) == 0xFC) {
      // 6-byte sequence → 36-bit number
      extraBytes = 5;
      value = first & 0x01;
    } else if ((first & 0xFC) == 0xF8) {
      // 5-byte sequence
      extraBytes = 4;
      value = first & 0x03;
    } else if ((first & 0xF8) == 0xF0) {
      // 4-byte sequence
      extraBytes = 3;
      value = first & 0x07;
    } else if ((first & 0xF0) == 0xE0) {
      // 3-byte sequence
      extraBytes = 2;
      value = first & 0x0F;
    } else if ((first & 0xE0) == 0xC0) {
      // 2-byte sequence
      extraBytes = 1;
      value = first & 0x1F;
    } else {
      throw FormatException(
          'Invalid UTF-8 coded number starting byte: 0x${first.toRadixString(16)}');
    }
    for (var i = 0; i < extraBytes; i++) {
      final b = readByte();
      if ((b & 0xC0) != 0x80) {
        throw FormatException('Invalid UTF-8 continuation byte: '
            '0x${b.toRadixString(16)}');
      }
      value = (value << 6) | (b & 0x3F);
    }
    return value;
  }

  /// Skips [n] bits.
  void skipBits(int n) {
    assert(n >= 0);
    // Fast path: byte-aligned and skipping whole bytes.
    if (_bitPos == 0 && n % 8 == 0) {
      _bytePos += n ~/ 8;
      return;
    }
    var remaining = n;
    while (remaining > 0) {
      final bitsInByte = 8 - _bitPos;
      final skip = remaining < bitsInByte ? remaining : bitsInByte;
      _bitPos += skip;
      if (_bitPos == 8) {
        _bitPos = 0;
        _bytePos++;
      }
      remaining -= skip;
    }
  }

  /// Skips to the next byte boundary (no-op if already aligned).
  void skipToByteBoundary() {
    if (_bitPos != 0) {
      _bitPos = 0;
      _bytePos++;
    }
  }
}
