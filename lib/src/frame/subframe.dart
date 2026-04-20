import 'dart:typed_data';

import '../bit_reader.dart';

/// Subframe type identifiers as encoded in a FLAC subframe header.
abstract final class SubframeType {
  static const int constant = 0;
  static const int verbatim = 1;
  static const int fixedBase = 8; // types 8–12: FIXED with order 0–4
  static const int lpcBase = 32; // types 32–63: LPC with order 1–32
}

/// Decodes a single FLAC subframe from the bit stream.
///
/// A subframe encodes one channel's worth of samples using one of four
/// coding methods: constant, verbatim, fixed-predictor, or FIR LPC.
abstract final class SubframeDecoder {
  /// Decodes [blockSize] samples from [reader] using [bitsPerSample] bits.
  ///
  /// Returns the decoded samples as an [Int32List].
  static Int32List decode(BitReader reader, int blockSize, int bitsPerSample) {
    // Subframe header: 1 reserved bit, 6 type bits, wasted-bits flag + count.
    reader.readBit(); // zero bit (padding)
    final typeCode = reader.readBits(6);
    final hasWastedBits = reader.readFlag();
    final int wastedBits;
    if (hasWastedBits) {
      wastedBits = reader.readUnary() + 1;
    } else {
      wastedBits = 0;
    }
    final effectiveBits = bitsPerSample - wastedBits;

    final Int32List samples;
    if (typeCode == 0) {
      samples = _decodeConstant(reader, blockSize, effectiveBits);
    } else if (typeCode == 1) {
      samples = _decodeVerbatim(reader, blockSize, effectiveBits);
    } else if (typeCode >= 8 && typeCode <= 12) {
      final order = typeCode - 8;
      samples = _decodeFixed(reader, blockSize, effectiveBits, order);
    } else if (typeCode >= 32 && typeCode <= 63) {
      final order = typeCode - 31; // LPC order 1–32
      samples = _decodeLpc(reader, blockSize, effectiveBits, order);
    } else {
      throw FormatException('Unknown subframe type: $typeCode');
    }

    // Shift samples left to restore wasted bits.
    if (wastedBits > 0) {
      for (var i = 0; i < samples.length; i++) {
        samples[i] <<= wastedBits;
      }
    }

    return samples;
  }

  // -------------------------------------------------------------------------
  // Constant subframe
  // -------------------------------------------------------------------------

  /// Every sample has the same value.
  static Int32List _decodeConstant(
      BitReader r, int blockSize, int bitsPerSample) {
    final value = r.readSignedBits(bitsPerSample);
    return Int32List(blockSize)..fillRange(0, blockSize, value);
  }

  // -------------------------------------------------------------------------
  // Verbatim subframe
  // -------------------------------------------------------------------------

  /// Samples are stored uncompressed.
  static Int32List _decodeVerbatim(
      BitReader r, int blockSize, int bitsPerSample) {
    final samples = Int32List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      samples[i] = r.readSignedBits(bitsPerSample);
    }
    return samples;
  }

  // -------------------------------------------------------------------------
  // Fixed-predictor subframe
  // -------------------------------------------------------------------------

  /// Fixed linear predictor with [order] warm-up samples.
  static Int32List _decodeFixed(
      BitReader r, int blockSize, int bitsPerSample, int order) {
    final samples = Int32List(blockSize);

    // Warm-up samples (uncompressed).
    for (var i = 0; i < order; i++) {
      samples[i] = r.readSignedBits(bitsPerSample);
    }

    // Residual.
    _decodeResidual(r, blockSize, order, samples);

    // Apply fixed predictor.
    _applyFixedPredictor(samples, order, blockSize);

    return samples;
  }

  /// Applies the fixed predictor polynomial to restore sample values.
  static void _applyFixedPredictor(
      Int32List samples, int order, int blockSize) {
    switch (order) {
      case 0:
        // order 0: signal = residual (already correct).
        break;
      case 1:
        for (var i = 1; i < blockSize; i++) {
          samples[i] += samples[i - 1];
        }
      case 2:
        for (var i = 2; i < blockSize; i++) {
          samples[i] += 2 * samples[i - 1] - samples[i - 2];
        }
      case 3:
        for (var i = 3; i < blockSize; i++) {
          samples[i] +=
              3 * samples[i - 1] - 3 * samples[i - 2] + samples[i - 3];
        }
      case 4:
        for (var i = 4; i < blockSize; i++) {
          samples[i] += 4 * samples[i - 1] -
              6 * samples[i - 2] +
              4 * samples[i - 3] -
              samples[i - 4];
        }
    }
  }

  // -------------------------------------------------------------------------
  // FIR LPC subframe
  // -------------------------------------------------------------------------

  /// FIR linear predictor with [order] coefficients.
  static Int32List _decodeLpc(
      BitReader r, int blockSize, int bitsPerSample, int order) {
    final samples = Int32List(blockSize);

    // Warm-up samples.
    for (var i = 0; i < order; i++) {
      samples[i] = r.readSignedBits(bitsPerSample);
    }

    // Quantised LPC precision (4 bits: precision = value + 1).
    final qlpPrecision = r.readBits(4) + 1;

    // QLP shift (5-bit signed integer).
    final qlpShift = r.readSignedBits(5);

    // QLP coefficients.
    final coefficients =
        List<int>.generate(order, (_) => r.readSignedBits(qlpPrecision));

    // Residual.
    _decodeResidual(r, blockSize, order, samples);

    // Apply LPC predictor.
    for (var i = order; i < blockSize; i++) {
      var sum = 0;
      for (var j = 0; j < order; j++) {
        sum += coefficients[j] * samples[i - j - 1];
      }
      samples[i] += sum >> qlpShift;
    }

    return samples;
  }

  // -------------------------------------------------------------------------
  // Residual coding
  // -------------------------------------------------------------------------

  /// Decodes Rice-coded residuals into [samples] starting at index [order].
  static void _decodeResidual(
      BitReader r, int blockSize, int order, Int32List samples) {
    // Coding method: 0 = Rice (4-bit param), 1 = Rice2 (5-bit param).
    final codingMethod = r.readBits(2);
    final paramBits = codingMethod == 0 ? 4 : 5;

    final partitionOrder = r.readBits(4);
    final partitionCount = 1 << partitionOrder;

    var sampleIndex = order;
    for (var part = 0; part < partitionCount; part++) {
      final samplesInPartition = partitionOrder == 0
          ? blockSize - order
          : (part == 0
              ? (blockSize >> partitionOrder) - order
              : blockSize >> partitionOrder);

      final riceParam = r.readBits(paramBits);

      if (riceParam == (1 << paramBits) - 1) {
        // Escape code: samples are stored verbatim.
        final escapeBits = r.readBits(5);
        for (var i = 0; i < samplesInPartition; i++) {
          samples[sampleIndex++] = r.readSignedBits(escapeBits);
        }
      } else {
        for (var i = 0; i < samplesInPartition; i++) {
          samples[sampleIndex++] = r.readRice(riceParam);
        }
      }
    }
  }
}
