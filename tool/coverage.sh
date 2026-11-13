#!/usr/bin/env bash
# Generate an lcov coverage report for the Dart VM test suite.

set -euo pipefail

# Exclude the full conformance sweep rather than letting its tag skip it:
# a suite skipped as a whole leaves an empty coverage file, which
# format_coverage (coverage >= 1.16.0) rejects.
dart test --coverage=coverage -x conformance-full
dart run coverage:format_coverage \
  --lcov \
  --in=coverage \
  --out=coverage/lcov.info \
  --packages=.dart_tool/package_config.json \
  --report-on=lib

echo "Wrote coverage/lcov.info"
