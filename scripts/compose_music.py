#!/usr/bin/env python3
"""Render the original background music loop "Meadow Lanterns".

An original composition written for Lantern Lane (melody, chords and
arrangement are in this file). It does not use samples, recordings or
third-party material: every sound is synthesized here from sine and triangle
waves. The loop is rendered circularly (note tails and reverb wrap around), so
the end joins the start without a click.

  tools/venv/bin/python scripts/compose_music.py     # needs numpy

Writes game/assets/audio/meadow_lanterns.wav: a sample-exact loop (compressed
formats such as Vorbis pad the last block, which would click at the seam). See docs/assets.md for provenance.
"""
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/audio/meadow_lanterns.wav'
RATE = 24000
BPM = 84
BEAT = 60.0 / BPM
BARS = 16
N = int(round(BARS * 4 * BEAT * RATE))

# F major. MIDI note numbers: F4 = 65, A4 = 69, C5 = 72.
NOTE = {'F3': 53, 'G3': 55, 'A3': 57, 'Bb3': 58, 'C4': 60, 'D4': 62, 'E4': 64, 'F4': 65, 'G4': 67,
        'A4': 69, 'Bb4': 70, 'C5': 72, 'D5': 74, 'E5': 76, 'F5': 77, 'G5': 79, 'A5': 81, 'Bb5': 82, 'C6': 84}
CHORDS = {  # pad voicing, bass root
    'F': ([53, 57, 60], 41), 'Dm': ([50, 53, 57], 38), 'Bb': ([50, 53, 58], 34), 'C': ([52, 55, 60], 36),
    'Am': ([52, 57, 60], 45), 'Gm': ([50, 55, 58], 43), 'Csus': ([53, 55, 60], 36),
}
# One chord per half bar.
PROGRESSION = ['F', 'F', 'Dm', 'Dm', 'Bb', 'Bb', 'C', 'C', 'F', 'F', 'Am', 'Am', 'Bb', 'C', 'F', 'F',
               'Dm', 'Dm', 'Bb', 'Bb', 'F', 'F', 'C', 'C', 'Gm', 'Gm', 'Bb', 'Bb', 'Csus', 'C', 'F', 'F']
# Melody per bar: (note, start beat, length in beats).
MELODY = [
    [('A4', 0, 1), ('C5', 1, 1), ('F5', 2, 1.5), ('E5', 3.5, .5)],
    [('D5', 0, 1.5), ('C5', 1.5, .5), ('A4', 2, 2)],
    [('Bb4', 0, 1), ('D5', 1, 1), ('F5', 2, 1), ('D5', 3, 1)],
    [('E5', 0, 1.5), ('D5', 1.5, .5), ('C5', 2, 1), ('G4', 3, 1)],
    [('A4', 0, .5), ('C5', .5, .5), ('F5', 1, 1), ('A5', 2, 1.5), ('G5', 3.5, .5)],
    [('E5', 0, 1), ('C5', 1, 1), ('E5', 2, 1), ('A5', 3, 1)],
    [('G5', 0, 1), ('F5', 1, 1), ('E5', 2, 1), ('D5', 3, 1)],
    [('C5', 0, 1), ('A4', 1, 1), ('F4', 2, 2)],
    [('F5', 0, 1), ('E5', 1, .5), ('D5', 1.5, .5), ('A4', 2, 2)],
    [('D5', 0, 1), ('F5', 1, 1), ('Bb5', 2, 1.5), ('A5', 3.5, .5)],
    [('A5', 0, 1.5), ('G5', 1.5, .5), ('F5', 2, 1), ('C5', 3, 1)],
    [('E5', 0, 1), ('G5', 1, 1), ('E5', 2, 1), ('C5', 3, 1)],
    [('D5', 0, 1), ('Bb4', 1, 1), ('D5', 2, 1), ('G5', 3, 1)],
    [('F5', 0, 1.5), ('D5', 1.5, .5), ('F5', 2, 1), ('D5', 3, 1)],
    [('F5', 0, 1), ('E5', 1, 1), ('D5', 2, 1), ('E5', 3, 1)],
    [('F5', 0, 3), ('C5', 3.5, .5)],
]


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12)


def env_ar(n, attack, release_from=None, release=0.0):
    t = np.arange(n) / RATE
    e = np.minimum(1.0, t / max(attack, 1e-4))
    if release_from is not None:
        e *= np.clip(1.0 - (t - release_from) / max(release, 1e-4), 0.0, 1.0)
    return e


def kalimba(f, beats):
    n = int(RATE * (beats * BEAT + 1.6))
    t = np.arange(n) / RATE
    s = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(4 * np.pi * f * t) * np.exp(-t * 6)
    s += 0.08 * np.sin(2 * np.pi * 5.4 * f * t) * np.exp(-t * 16)  # soft "tine" shimmer
    return s * np.exp(-t * 2.6) * env_ar(n, 0.004)


def harp(f):
    n = int(RATE * 1.2)
    t = np.arange(n) / RATE
    s = np.sin(2 * np.pi * f * t) + np.sin(6 * np.pi * f * t) / 9 + np.sin(10 * np.pi * f * t) / 25
    return s * np.exp(-t * 4.0) * env_ar(n, 0.006)


def pad(f, beats):
    length = beats * BEAT
    n = int(RATE * (length + 1.0))
    t = np.arange(n) / RATE
    s = sum(np.sin(2 * np.pi * f * d * t) for d in (0.997, 1.0, 1.003)) / 3
    s += 0.25 * np.sin(4 * np.pi * f * t)
    return s * env_ar(n, 0.7, length, 1.0)


def bass(f, beats):
    n = int(RATE * (beats * BEAT + 0.4))
    t = np.arange(n) / RATE
    s = np.sin(2 * np.pi * f * t) + 0.15 * np.sin(4 * np.pi * f * t)
    return s * np.exp(-t * 1.8) * env_ar(n, 0.012, beats * BEAT, 0.4)


def place(buf, sound, beat, pan=0.0, gain=1.0):
    """Adds a sound at a beat position, wrapping its tail to the loop start."""
    start = int(round(beat * BEAT * RATE)) % N
    idx = (start + np.arange(len(sound))) % N
    left, right = gain * np.sqrt(0.5 - pan * 0.5), gain * np.sqrt(0.5 + pan * 0.5)
    np.add.at(buf[0], idx, sound * left)
    np.add.at(buf[1], idx, sound * right)


def circular_reverb(buf, seconds=2.2, mix=0.22, seed=7):
    """Convolution with decaying filtered noise, done circularly so the loop stays seamless."""
    rng = np.random.default_rng(seed)
    n = int(RATE * seconds)
    t = np.arange(n) / RATE
    out = np.empty_like(buf)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / 0.55)
        ir = np.convolve(ir, np.ones(12) / 12, mode='same')  # darker tail
        ir /= np.sqrt(np.sum(ir ** 2))
        padded = np.zeros(N)
        padded[:n] = ir
        wet = np.real(np.fft.ifft(np.fft.fft(buf[ch]) * np.fft.fft(padded)))
        out[ch] = buf[ch] * (1 - mix) + wet * mix * 2.0
    return out


def main():
    buf = np.zeros((2, N))
    for half, name in enumerate(PROGRESSION):
        voicing, root = CHORDS[name]
        beat = half * 2
        for i, m in enumerate(voicing):
            place(buf, pad(hz(m), 2), beat, pan=(i - 1) * 0.3, gain=0.05)
        place(buf, bass(hz(root), 1.5), beat, gain=0.22)
        # Harp arpeggio, two notes per beat, an octave above the pad.
        for k, step in enumerate([0, 1, 2, 1]):
            place(buf, harp(hz(voicing[step] + 12)), beat + k * 0.5, pan=0.35, gain=0.05)
    for bar, notes in enumerate(MELODY):
        for name, start, length in notes:
            place(buf, kalimba(hz(NOTE[name]), length), bar * 4 + start, pan=-0.15, gain=0.2)
    for bar in range(0, BARS, 4):  # a quiet bell sparkle every four bars
        place(buf, kalimba(hz(NOTE['C6']), 2), bar * 4 + 3.5, pan=0.5, gain=0.05)
    buf = circular_reverb(buf)
    # One-pole low-pass for a soft, warm top end, applied circularly in the frequency domain.
    a = np.exp(-2 * np.pi * 5200 / RATE)
    w = 2 * np.pi * np.fft.rfftfreq(N)
    response = (1 - a) / (1 - a * np.exp(-1j * w))
    buf = np.array([np.fft.irfft(np.fft.rfft(ch) * response, n=N) for ch in buf])
    buf = np.tanh(buf * 1.2) / np.tanh(1.2)
    buf *= 0.5 / np.max(np.abs(buf))  # peak at -6 dBFS; the game plays it quieter still
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((buf.T * 32767).astype('<i2').tobytes())
    seam = np.abs(buf[:, 0] - buf[:, -1]).max()
    rms = float(np.sqrt(np.mean(buf ** 2)))
    print(f'{OUT.relative_to(ROOT)}: {N / RATE:.2f} s loop, {OUT.stat().st_size // 1024} KB, '
          f'peak -6.0 dBFS, rms {20 * np.log10(rms):.1f} dBFS, seam step {seam:.4f}')


if __name__ == '__main__':
    main()
