#!/usr/bin/env bash
# Generates a stereo 16-bit 44100 Hz FLAC fixture for the decode
# benchmark. Default duration is 30 s; override with e.g.
#   ./generate_fixture.sh 180     # 3-minute track
# Output: benchmark/fixtures/bench.flac (gitignored).
#
# Signal content is a pair of sine waves + low-amplitude noise — enough
# to stop the encoder from trivialising every frame to CONSTANT
# subframes, so the decode path actually does LPC/Rice work.

set -euo pipefail
cd "$(dirname "$0")/fixtures"
seconds="${1:-30}"
export SECONDS_ARG="$seconds"

python3 - <<'PY' > bench.pcm
import os, struct, math, random, sys
sr = 44100
seconds = int(os.environ['SECONDS_ARG'])
random.seed(0)  # reproducible noise
for i in range(sr * seconds):
    l = int(12000 * math.sin(2 * math.pi * 440 * i / sr) +
            2000 * (random.random() - 0.5))
    r = int(12000 * math.sin(2 * math.pi * 660 * i / sr) +
            2000 * (random.random() - 0.5))
    sys.stdout.buffer.write(struct.pack('<hh', l, r))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=2 --bps=16 --sample-rate=44100 \
     --force-raw-format \
     -o bench.flac bench.pcm

rm bench.pcm
ls -la bench.flac
