#!/usr/bin/env bash
# Fetch FLAC decoder conformance files from the IETF CELLAR testbench
# (https://github.com/ietf-wg-cellar/flac-test-files, CC0).
#
# Default: download the ten curated files used by `dart test -t conformance`
#          (~12 MB, fetched individually).
# --full:  download the complete testbench tarball (~201 MB download,
#          ~296 MB extracted) used by `dart test -t conformance-full`.
#
# Files land in test/fixtures/conformance/ (gitignored). Idempotent: each
# mode writes a marker naming the pinned SHA, and files fetched at that SHA
# are not downloaded again. Run from anywhere; the script resolves paths
# relative to the repository root.

set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
  echo "Usage: $0 [--full]" >&2
  exit 2
}

case "$#:${1:-}" in
  0:) full=false ;;
  1:--full) full=true ;;
  *) usage ;;
esac

# Bump deliberately and re-triage test/conformance_full_test.dart. The CI
# cache key hashes this script, so a bump also invalidates the cache.
SHA=aa7b0c6cf32994c106ae517a08134c28a96ff5b2
DEST=test/fixtures/conformance

# Retry transient failures (5xx, connection resets) so a flaky download
# does not fail an unrelated CI run.
CURL=(curl -fsSL --retry 3 --retry-all-errors)

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

if [[ "$full" == true ]]; then
  marker="$DEST/.full-$SHA"
  if [[ -f "$marker" ]]; then
    echo "Full testbench already present ($SHA)."
    exit 0
  fi
  mkdir -p "$DEST"
  echo "Downloading full testbench tarball (~201 MB)..."
  # Download to a file before extracting: a retried transfer piped straight
  # into tar would feed it a duplicated, corrupt stream.
  tarball="$DEST/.full-$SHA.tar.gz.tmp"
  "${CURL[@]}" -o "$tarball" \
    "https://codeload.github.com/ietf-wg-cellar/flac-test-files/tar.gz/$SHA"
  tar -xzf "$tarball" -C "$DEST" --strip-components=1
  rm "$tarball"
  touch "$marker"
  echo "Extracted full testbench to $DEST."
else
  marker="$DEST/.curated-$SHA"
  # Without a marker for this SHA, files already present may come from
  # another testbench revision: download every curated file again.
  refetch=false
  if [[ ! -f "$marker" ]]; then
    refetch=true
    rm -f "$DEST"/.curated-*
  fi
  for path in "${CURATED[@]}"; do
    out="$DEST/$path"
    if [[ "$refetch" == false && -f "$out" ]]; then continue; fi
    mkdir -p "$(dirname "$out")"
    url="https://raw.githubusercontent.com/ietf-wg-cellar/flac-test-files/$SHA/${path// /%20}"
    echo "Fetching $path"
    "${CURL[@]}" -o "$out.tmp" "$url"
    mv "$out.tmp" "$out"
  done
  touch "$marker"
  echo "Curated conformance files present in $DEST."
fi
