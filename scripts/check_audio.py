#!/usr/bin/env python3
"""Validate the shipped music loop (the actual WAV file the game imports).

Checks format, loop length, headroom, loudness, DC offset, silence gaps and the
loop seam (the jump from the last sample back to the first must look like an
ordinary step inside the music). It cannot judge taste: listen on a device too.

  python3 scripts/check_audio.py
"""
import array
import math
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WAV = ROOT / 'game/assets/audio/meadow_lanterns.wav'
RATE = 24000
EXPECTED_SECONDS = 16 * 4 * 60 / 84


def main():
    with wave.open(str(WAV)) as w:
        assert w.getnchannels() == 2 and w.getsampwidth() == 2 and w.getframerate() == RATE, w.getparams()
        pcm = array.array('h', w.readframes(w.getnframes()))
    left, right = pcm[0::2], pcm[1::2]
    seconds = len(left) / RATE
    assert abs(seconds - EXPECTED_SECONDS) < 0.05, f'loop length {seconds:.3f}s, expected {EXPECTED_SECONDS:.3f}s'
    peak = max(max(abs(v) for v in left), max(abs(v) for v in right)) / 32768
    rms = math.sqrt(sum(v * v for v in left[::7]) / len(left[::7])) / 32768
    dc = sum(left) / len(left) / 32768
    peak_db, rms_db = 20 * math.log10(peak), 20 * math.log10(rms)
    assert peak_db < -3.0, f'peak {peak_db:.1f} dBFS leaves too little headroom'
    assert -26 < rms_db < -14, f'loudness {rms_db:.1f} dBFS outside the calm range'
    assert abs(dc) < 0.01, f'DC offset {dc:.4f}'
    # Longest near-silent stretch (the loop should never drop out).
    window = RATE // 10
    quiet, longest = 0, 0
    for i in range(0, len(left) - window, window):
        level = max(abs(v) for v in left[i:i + window:4])
        quiet = quiet + 1 if level < 160 else 0
        longest = max(longest, quiet)
    assert longest * 0.1 < 1.0, f'{longest * 0.1:.1f}s of silence'
    # Seam: compare the wrap-around step with the 99.9th percentile of ordinary steps.
    steps = sorted(abs(left[i + 1] - left[i]) for i in range(0, len(left) - 1, 3))
    typical = steps[int(len(steps) * 0.999)]
    seam = abs(left[0] - left[-1])
    assert seam <= typical, f'loop seam step {seam} is larger than ordinary steps ({typical})'
    print(f'PASS: {WAV.relative_to(ROOT)} PCM {RATE} Hz stereo, {seconds:.2f}s loop, peak {peak_db:.1f} dBFS, '
          f'rms {rms_db:.1f} dBFS, DC {dc:+.4f}, longest quiet {longest * 0.1:.1f}s, seam step {seam} <= {typical}')


if __name__ == '__main__':
    sys.exit(main())
