#!/usr/bin/env bash
# Regenerate binary FLAC test fixtures from known PCM input.
#
# Requires: python3, flac CLI (>= 1.4).
# Run from the repository root: ./test/fixtures/generate.sh

set -euo pipefail
cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Fixture 1: stereo, 16-bit, 44100 Hz. 512 samples of two offset sine waves.
# Exercises: LPC subframes, mid/side decorrelation, 16-bit bps code, 44100 Hz
# sample-rate code, MD5 verification at 16-bit.
# ---------------------------------------------------------------------------
python3 - <<'PY' > stereo_16_44100.pcm
import struct, math
sr = 44100
for i in range(512):
    l = int(10000 * math.sin(2 * math.pi * 440 * i / sr))
    r = int(10000 * math.sin(2 * math.pi * 660 * i / sr))
    import sys
    sys.stdout.buffer.write(struct.pack('<hh', l, r))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=2 --bps=16 --sample-rate=44100 \
     --force-raw-format \
     --blocksize=128 \
     -o stereo_16_44100.flac stereo_16_44100.pcm

# ---------------------------------------------------------------------------
# Fixture 2: mono, 8-bit, 16000 Hz. 256 samples of a simple pattern.
# Exercises: mono, 8-bit bps code, 16000 Hz sample-rate code, MD5 at 8-bit.
# ---------------------------------------------------------------------------
python3 - <<'PY' > mono_8_16000.pcm
import struct, math, sys
sr = 16000
for i in range(256):
    v = int(100 * math.sin(2 * math.pi * 1000 * i / sr))
    sys.stdout.buffer.write(struct.pack('<b', v))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=1 --bps=8 --sample-rate=16000 \
     --force-raw-format \
     -o mono_8_16000.flac mono_8_16000.pcm

# ---------------------------------------------------------------------------
# Fixture 3: stereo, 24-bit, 96000 Hz. 256 samples.
# Exercises: 24-bit bps code, 96000 Hz sample-rate code, MD5 width rounding
# (24 bits -> 3 bytes per sample).
# ---------------------------------------------------------------------------
python3 - <<'PY' > stereo_24_96000.pcm
import struct, math, sys
sr = 96000
for i in range(256):
    l = int(1_000_000 * math.sin(2 * math.pi * 880 * i / sr))
    r = int(500_000 * math.sin(2 * math.pi * 1320 * i / sr))
    for v in (l, r):
        # 24-bit little-endian signed
        b = (v & 0xFFFFFF).to_bytes(3, 'little')
        sys.stdout.buffer.write(b)
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=2 --bps=24 --sample-rate=96000 \
     --force-raw-format \
     -o stereo_24_96000.flac stereo_24_96000.pcm

ls -la *.flac *.pcm
