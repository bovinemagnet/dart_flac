/// CRC-8 and CRC-16 utilities used in FLAC frame headers and footers.
///
/// FLAC uses:
///  - CRC-8 with polynomial 0x07 for frame headers.
///  - CRC-16 with polynomial 0x8005 for frame data.
library;

/// Pre-computed CRC-8 table (polynomial 0x07, initial value 0x00).
final List<int> _crc8Table = _buildCrc8Table();

List<int> _buildCrc8Table() {
  const poly = 0x07;
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var crc = i;
    for (var j = 0; j < 8; j++) {
      crc = (crc & 0x80) != 0 ? ((crc << 1) ^ poly) & 0xFF : (crc << 1) & 0xFF;
    }
    table[i] = crc;
  }
  return table;
}

/// Pre-computed CRC-16 table (polynomial 0x8005, initial value 0x0000).
final List<int> _crc16Table = _buildCrc16Table();

List<int> _buildCrc16Table() {
  const poly = 0x8005;
  final table = List<int>.filled(256, 0);
  for (var i = 0; i < 256; i++) {
    var crc = i << 8;
    for (var j = 0; j < 8; j++) {
      crc = (crc & 0x8000) != 0
          ? ((crc << 1) ^ poly) & 0xFFFF
          : (crc << 1) & 0xFFFF;
    }
    table[i] = crc;
  }
  return table;
}

/// Computes the CRC-8 checksum over [data].
///
/// Used to verify FLAC frame headers. The initial value is 0x00.
int crc8(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc = _crc8Table[(crc ^ b) & 0xFF];
  }
  return crc;
}

/// Computes the CRC-16 checksum over [data].
///
/// Used to verify FLAC frame data. The initial value is 0x0000.
int crc16(List<int> data) {
  var crc = 0;
  for (final b in data) {
    crc = ((_crc16Table[((crc >> 8) ^ b) & 0xFF]) ^ ((crc << 8) & 0xFFFF));
  }
  return crc;
}
