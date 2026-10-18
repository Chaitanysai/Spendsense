#!/usr/bin/env python3
"""Deterministic generator for SpendSense's bundled UI sound effects.

Why a generator instead of downloaded samples
---------------------------------------------
Every cue in `assets/sounds/` is synthesised here from first principles, so the
project ships no third-party audio. That keeps the licensing story trivial (the
output is original work, dedicated to the public domain) and makes the sound
identity reproducible: re-running this script regenerates byte-identical assets.

Design intent
-------------
Premium fintech, not arcade. Every cue is short, soft and slightly rounded:

* band-limited sines with fast exponential decays (no square/saw buzz),
* a 2 ms fade on both ends so nothing clicks,
* a conservative peak target (-6 dBFS) so the app is never loud,
* tempos/notes kept low-key except the single transaction "signature".

Usage
-----
    python tool/generate_sounds.py

Writes 16-bit mono PCM WAVs at 44.1 kHz into `assets/sounds/`.
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 44_100
OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "assets",
    "sounds",
)

# -6 dBFS. Deliberately quiet: volume is also scaled at playback time.
PEAK = 10 ** (-6.0 / 20.0)


def envelope(n: int, attack: float, decay: float, power: float = 2.0) -> list[float]:
    """Attack/decay envelope over `n` samples (times in seconds)."""
    a = max(1, int(attack * SAMPLE_RATE))
    d = max(1, int(decay * SAMPLE_RATE))
    total = a + d
    out = []
    for i in range(n):
        if i < a:
            out.append(i / a)
        elif i < total:
            out.append((1.0 - (i - a) / d) ** power)
        else:
            out.append(0.0)
    return out


def partial(freq: float, length: float, amp: float = 1.0, phase: float = 0.0):
    """A single sine partial: (sample index -> amplitude) callable."""
    def fn(i: int) -> float:
        return amp * math.sin(2 * math.pi * freq * (i / SAMPLE_RATE) + phase)

    return fn


def render(length: float, voices, env, fade_ms: float = 2.0) -> list[float]:
    """Sum `voices` (callables), apply envelope then edge fades."""
    n = int(length * SAMPLE_RATE)
    env_values = envelope(n, env[0], env[1], env[2] if len(env) > 2 else 2.0)
    fade = max(1, int(fade_ms / 1000 * SAMPLE_RATE))

    buf = [0.0] * n
    for i in range(n):
        total = 0.0
        for v in voices:
            total += v(i)
        buf[i] = total * env_values[i]

    for i in range(min(fade, n)):
        buf[i] *= i / fade
        buf[n - 1 - i] *= i / fade
    return buf


def note(freq: float, start: float, length: float, amp: float = 1.0, voices=1):
    """A note that only contributes over [start, start+length) samples."""
    def fn(i: int) -> float:
        if i < start * SAMPLE_RATE or i >= (start + length) * SAMPLE_RATE:
            return 0.0
        t = (i - start * SAMPLE_RATE) / SAMPLE_RATE
        decay = math.exp(-t / (length * 0.35))
        value = 0.0
        for k in range(1, voices + 1):
            value += (1.0 / k) * math.sin(2 * math.pi * freq * k * t)
        return amp * value * decay

    return fn


def lowpass(buf: list[float], cutoff: float) -> list[float]:
    """One-pole low-pass; used to take the edge off the low failure tone."""
    dt = 1.0 / SAMPLE_RATE
    rc = 1.0 / (2 * math.pi * cutoff)
    alpha = dt / (rc + dt)
    out = [0.0] * len(buf)
    prev = 0.0
    for i, x in enumerate(buf):
        prev += alpha * (x - prev)
        out[i] = prev
    return out


def normalize(buf: list[float], peak: float = PEAK) -> list[float]:
    high = max((abs(x) for x in buf), default=0.0)
    if high == 0:
        return buf
    scale = peak / high
    return [x * scale for x in buf]


def write_wav(name: str, buf: list[float]) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    frames = bytearray()
    for x in buf:
        clamped = max(-1.0, min(1.0, x))
        frames += struct.pack("<h", int(round(clamped * 32767)))

    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(bytes(frames))
    print(f"wrote {path} ({len(buf) / SAMPLE_RATE * 1000:.0f} ms)")


def ui_tap() -> list[float]:
    """Soft digital tick: 1.6 kHz blip with a whisper of air."""
    rng = random.Random(7)
    length = 0.045
    buf = render(
        length,
        [
            partial(1600, length, amp=1.0),
            partial(2400, length, amp=0.35),
            lambda i: 0.10 * (rng.random() * 2 - 1),
        ],
        env=(0.001, 0.040, 3.4),
    )
    return normalize(lowpass(buf, 9000.0))


def selection() -> list[float]:
    """Subtle confirmation tone: a rounded 880 Hz pop with a soft overtone."""
    length = 0.085
    buf = render(
        length,
        [partial(880, length), partial(1320, length, amp=0.28)],
        env=(0.003, 0.075, 2.6),
    )
    return normalize(lowpass(buf, 7000.0))


def transaction_saved() -> list[float]:
    """The signature: a restrained modern digital cha-ching.

    Two bright partial-rich tones ascending (C6 -> G6) with a short shimmer,
    which reads as 'done' without sounding like a slot machine.
    """
    length = 0.42
    voices = [
        note(1046.50, 0.00, 0.22, amp=1.0, voices=3),  # C6
        note(1567.98, 0.09, 0.30, amp=0.85, voices=3),  # G6
        # Inharmonic sparkle, well below the fundamentals.
        note(2637.02, 0.10, 0.34, amp=0.16, voices=1),  # E7
        note(3520.00, 0.12, 0.30, amp=0.10, voices=1),  # A7
    ]
    buf = render(length, voices, env=(0.004, 0.40, 1.6))
    return normalize(lowpass(buf, 11000.0))


def action_success() -> list[float]:
    """Clean, brief two-note chime: G5 -> C6."""
    length = 0.36
    voices = [
        note(783.99, 0.00, 0.16, amp=0.9, voices=2),
        note(1046.50, 0.11, 0.24, amp=1.0, voices=2),
    ]
    buf = render(length, voices, env=(0.006, 0.34, 1.8))
    return normalize(lowpass(buf, 8000.0))


def action_failed() -> list[float]:
    """Gentle, unobtrusive low tone: A3 -> F3, softened so it never scolds."""
    length = 0.34
    voices = [
        note(220.00, 0.00, 0.16, amp=1.0, voices=1),
        note(174.61, 0.10, 0.24, amp=0.95, voices=1),
    ]
    buf = render(length, voices, env=(0.010, 0.32, 2.0))
    return normalize(lowpass(buf, 1400.0), peak=PEAK * 0.85)


def milestone() -> list[float]:
    """Restrained celebration: a three-note bell arpeggio (C6-E6-G6)."""
    length = 0.62
    voices = [
        note(1046.50, 0.00, 0.26, amp=0.85, voices=2),
        note(1318.51, 0.10, 0.30, amp=0.95, voices=2),
        note(1567.98, 0.20, 0.40, amp=1.00, voices=3),
    ]
    buf = render(length, voices, env=(0.006, 0.60, 1.7))
    return normalize(lowpass(buf, 10000.0))


BUILDERS = {
    "ui_tap.wav": ui_tap,
    "selection.wav": selection,
    "transaction_saved.wav": transaction_saved,
    "action_success.wav": action_success,
    "action_failed.wav": action_failed,
    "milestone.wav": milestone,
}


def main() -> None:
    for name, builder in BUILDERS.items():
        write_wav(name, builder())


if __name__ == "__main__":
    main()
