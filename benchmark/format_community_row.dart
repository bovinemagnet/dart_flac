// Formats a single Markdown table row for the "Community device results"
// section of README.md.
//
// This file is intentionally a pure function with zero dart_flac imports,
// so you can copy it verbatim into a Flutter `integration_test/` harness
// without pulling the rest of the benchmark CLI in. That keeps the row
// format stable across submissions.
//
// Usage sketch inside a Flutter integration test:
//
//   final row = formatCommunityRow(
//     device: 'Pixel 7 / Tensor G2',
//     osAndDart: 'Android 14 / Dart 3.5',
//     mode: 'AOT',
//     full:      OpResult(medianMs: 3200, realtime: 56, peakRssMb: 260),
//     streaming: OpResult(medianMs: 3050, realtime: 59, peakRssMb: 45),
//     oneshot:   OpResult(medianMs: 3400, realtime: 53, peakRssMb: 140),
//   );
//   print(row);

/// A single operation's decode measurement.
class OpResult {
  final double medianMs;
  final double realtime;
  final double peakRssMb;
  const OpResult({
    required this.medianMs,
    required this.realtime,
    required this.peakRssMb,
  });

  String get shortLabel =>
      '${realtime.toStringAsFixed(0)}× / ${peakRssMb.toStringAsFixed(0)} MB';
}

/// Returns a Markdown row matching the README "Community device results"
/// table schema. No trailing newline; caller adds one if needed.
String formatCommunityRow({
  required String device,
  required String osAndDart,
  required String mode,
  required OpResult full,
  required OpResult streaming,
  required OpResult oneshot,
}) {
  return '| $device | $osAndDart | $mode '
      '| ${full.shortLabel} '
      '| ${streaming.shortLabel} '
      '| ${oneshot.shortLabel} |';
}
