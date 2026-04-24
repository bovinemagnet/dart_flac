#!/usr/bin/env bash
# Generate an lcov coverage report for the Dart VM test suite.

set -euo pipefail

dart test --coverage=coverage
dart run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --packages=.dart_tool/package_config.json \
  --report-on=lib

echo "Wrote coverage/lcov.info"
