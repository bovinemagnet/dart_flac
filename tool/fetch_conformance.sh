#!/usr/bin/env bash
# Fetch FLAC decoder conformance files from the IETF CELLAR testbench
# (https://github.com/ietf-wg-cellar/flac-test-files, CC0).
#
# Default: download the ten curated files used by `dart test -t conformance`
#          (~12 MB, fetched individually).
# --full:  download the complete testbench tarball (~201 MB download,
#          ~296 MB extracted) used by `dart test -t conformance-full`.
#
# Files land in test/fixtures/conformance/ (gitignored). Idempotent: files
# already present are not downloaded again. Run from anywhere; the script
# resolves paths relative to the repository root.

set -euo pipefail
cd "$(dirname "$0")/.."

# Bump deliberately: also update the actions/cache key in
# .github/workflows/ci.yml and re-triage test/conformance_full_test.dart.
SHA=aa7b0c6cf32994c106ae517a08134c28a96ff5b2
DEST=test/fixtures/conformance

CURATED=(
  "subset/01 - blocksize 4096.flac"
  "subset/23 - 8 bit per sample.flac"
  "subset/24 - variable blocksize file created with flake revision 264.flac"
  "subset/28 - high resolution audio, default settings.flac"
  "subset/37 - 20 bit per sample.flac"
  "subset/41 - 6 channels (5.1).flac"
  "subset/47 - only STREAMINFO.flac"
  "subset/60 - mono audio.flac"
  "uncommon/05 - 32bps audio.flac"
  "faulty/10 - invalid vorbis comment metadata block.flac"
)

if [[ "${1:-}" == "--full" ]]; then
  marker="$DEST/.full-$SHA"
  if [[ -f "$marker" ]]; then
    echo "Full testbench already present ($SHA)."
    exit 0
  fi
  mkdir -p "$DEST"
  echo "Downloading full testbench tarball (~201 MB)..."
  curl -fsSL "https://codeload.github.com/ietf-wg-cellar/flac-test-files/tar.gz/$SHA" \
    | tar -xz -C "$DEST" --strip-components=1
  touch "$marker"
  echo "Extracted full testbench to $DEST."
else
  for path in "${CURATED[@]}"; do
    out="$DEST/$path"
    [[ -f "$out" ]] && continue
    mkdir -p "$(dirname "$out")"
    url="https://raw.githubusercontent.com/ietf-wg-cellar/flac-test-files/$SHA/${path// /%20}"
    echo "Fetching $path"
    curl -fsSL -o "$out" "$url"
  done
  echo "Curated conformance files present in $DEST."
fi
