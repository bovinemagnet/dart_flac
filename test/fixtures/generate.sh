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

# ---------------------------------------------------------------------------
# Fixture 4: mono, 16-bit, 44100 Hz. 256 samples of full-scale seeded noise.
# Incompressible input makes the reference encoder emit VERBATIM subframes.
# ---------------------------------------------------------------------------
python3 - <<'PY' > noise_16_44100.pcm
import random, struct, sys
random.seed(42)
for _ in range(256):
    sys.stdout.buffer.write(struct.pack('<h', random.randint(-32768, 32767)))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=1 --bps=16 --sample-rate=44100 \
     --force-raw-format \
     --blocksize=64 -0 \
     -o noise_16_44100.flac noise_16_44100.pcm

# ---------------------------------------------------------------------------
# Fixture 5: stereo, 20-bit, 44100 Hz. 256 samples.
# The flac CLI only accepts 8/16/24/32-bit raw input, so a
# WAVE_FORMAT_EXTENSIBLE WAV with wValidBitsPerSample=20 is generated as the
# encoder input (samples left-justified in a 24-bit container). The committed
# .pcm reference holds the right-justified 20-bit values in 24-bit two's
# complement, 3 bytes little-endian — the decoder's output convention.
# Exercises: 20-bit bps, non-byte-aligned depth, MD5 at 20 bits.
# ---------------------------------------------------------------------------
python3 - <<'PY'
import struct, math
sr = 44100
pcm = bytearray()
wav = bytearray()
for i in range(256):
    l = int(400000 * math.sin(2 * math.pi * 440 * i / sr))
    r = int(200000 * math.sin(2 * math.pi * 660 * i / sr))
    for v in (l, r):
        pcm += (v & 0xFFFFFF).to_bytes(3, 'little')
        wav += ((v << 4) & 0xFFFFFF).to_bytes(3, 'little')
fmt = struct.pack('<HHIIHH', 0xFFFE, 2, sr, sr * 6, 6, 24)
fmt += struct.pack('<HHI', 22, 20, 0x3)  # cbSize, valid bits, channel mask
fmt += b'\x01\x00\x00\x00\x00\x00\x10\x00\x80\x00\x00\xaa\x00\x38\x9b\x71'
data = bytes(wav)
riff = (b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt
        + b'data' + struct.pack('<I', len(data)) + data)
open('stereo_20_44100.wav', 'wb').write(b'RIFF' + struct.pack('<I', len(riff)) + riff)
open('stereo_20_44100.pcm', 'wb').write(bytes(pcm))
PY

flac --silent --force --no-preserve-modtime --verify \
     -o stereo_20_44100.flac stereo_20_44100.wav
rm stereo_20_44100.wav

# ---------------------------------------------------------------------------
# Fixture 6: 5.1 surround (6 channels), 16-bit, 44100 Hz. 256 samples, a
# different sine per channel. Exercises: independent-channel decoding with
# channel count > 2, MD5 over six interleaved channels.
# ---------------------------------------------------------------------------
python3 - <<'PY' > surround_16_44100.pcm
import struct, math, sys
sr = 44100
for i in range(256):
    for ch in range(6):
        v = int(8000 * math.sin(2 * math.pi * (220 * (ch + 1)) * i / sr))
        sys.stdout.buffer.write(struct.pack('<h', v))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=6 --bps=16 --sample-rate=44100 \
     --force-raw-format \
     -o surround_16_44100.flac surround_16_44100.pcm

# ---------------------------------------------------------------------------
# Fixture 7: mono, 32-bit, 48000 Hz. 256 samples. Requires flac >= 1.4.
# Exercises: 32-bit bps (the format's maximum), MD5 at 4 bytes per sample.
# ---------------------------------------------------------------------------
python3 - <<'PY' > mono_32_48000.pcm
import struct, math, sys
sr = 48000
for i in range(256):
    v = int(1_000_000_000 * math.sin(2 * math.pi * 440 * i / sr))
    sys.stdout.buffer.write(struct.pack('<i', v))
PY

flac --silent --force --no-preserve-modtime --verify \
     --endian=little --sign=signed --channels=1 --bps=32 --sample-rate=48000 \
     --force-raw-format \
     -o mono_32_48000.flac mono_32_48000.pcm

ls -la *.flac *.pcm
