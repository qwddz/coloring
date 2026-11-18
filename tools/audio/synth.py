"""Synthesizes the game's sounds into assets/audio/.

Everything is additive synthesis with soft envelopes, so the output is the
same on every run (the only randomness is a seeded velocity jitter).

    uv run synth.py
"""

from __future__ import annotations

from pathlib import Path

import numpy as np
import soundfile as sf

RATE = 44100
SEED = 6
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio"

SFX_PEAK_DB = -3.0


def db(x: float) -> float:
    return 20 * np.log10(max(x, 1e-12))


def midi_hz(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def envelope(n: int, attack: float, decay: float, release: float = 0.03) -> np.ndarray:
    """Raised-cosine attack, exponential decay, raised-cosine fade at the end."""
    t = np.arange(n) / RATE
    env = np.exp(-t / decay)
    a = max(1, int(attack * RATE))
    env[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, a))
    r = min(n, max(1, int(release * RATE)))
    env[n - r :] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, r))
    return env


def partials(
    freq: float,
    length: float,
    ratios: list[float],
    amps: list[float],
    decay: float,
    attack: float,
    glide: float = 0.0,
) -> np.ndarray:
    """Sum of sines; higher partials decay faster, which keeps the tone soft.

    `glide` bends the pitch down by that share over the first 60 ms
    (a woody "tuk").
    """
    n = int(length * RATE)
    t = np.arange(n) / RATE
    bend = 1 - glide * (1 - np.exp(-t / 0.06))
    out = np.zeros(n)
    for k, (ratio, amp) in enumerate(zip(ratios, amps)):
        f = freq * ratio
        if f > 7000:  # nothing shrill for small ears
            continue
        phase = 2 * np.pi * np.cumsum(f * bend) / RATE
        out += amp * np.sin(phase) * envelope(n, attack, decay / (1 + 1.6 * k))
    return out


def bell(note: float, length: float = 2.0, decay: float = 0.55) -> np.ndarray:
    """Soft marimba/celesta-like voice."""
    return partials(
        midi_hz(note), length, [1, 2, 3, 4.01], [1, 0.32, 0.1, 0.04], decay, 0.006
    )


def pad(note: float, length: float) -> np.ndarray:
    """Quiet chord tone: slow attack, mostly fundamental."""
    return partials(midi_hz(note), length, [1, 2], [1, 0.15], 1.4, 0.06)


def bass(note: float, length: float = 1.6) -> np.ndarray:
    """Warm round bass."""
    return partials(midi_hz(note), length, [1, 2, 3], [1, 0.22, 0.06], 0.7, 0.02)


def mix(buf: np.ndarray, sound: np.ndarray, at: float, gain: float) -> None:
    start = int(round(at * RATE))
    end = min(len(buf), start + len(sound))
    buf[start:end] += gain * sound[: end - start]


def finish(x: np.ndarray, peak_db: float) -> np.ndarray:
    x = x - x.mean()
    return x * (10 ** (peak_db / 20) / np.abs(x).max())


# --- Sound effects ----------------------------------------------------------


def fill() -> np.ndarray:
    """Soft "pop/click" when a region is colored."""
    buf = np.zeros(int(0.16 * RATE))
    mix(buf, partials(midi_hz(76), 0.16, [1, 2.0, 3.0], [1, 0.3, 0.08], 0.05, 0.003, glide=0.2), 0, 1.0)
    mix(buf, partials(midi_hz(64), 0.16, [1], [1], 0.04, 0.003, glide=0.15), 0, 0.4)
    return finish(buf, SFX_PEAK_DB)


def wrong() -> np.ndarray:
    """Low, soft "boop" for a color that does not belong."""
    buf = np.zeros(int(0.3 * RATE))
    mix(buf, partials(midi_hz(52), 0.3, [1, 2.0], [1, 0.12], 0.12, 0.01, glide=0.18), 0, 1.0)
    return finish(buf, SFX_PEAK_DB - 3)


def win() -> np.ndarray:
    """Happy arpeggio up to a ringing C major chord, about 2.6 s."""
    length = 2.7
    buf = np.zeros(int(length * RATE))
    step = 0.13
    for i, note in enumerate([72, 76, 79, 84, 88]):  # C5 E5 G5 C6 E6
        mix(buf, bell(note, 1.2, 0.35), i * step, 0.8)
    chord_at = 5 * step + 0.08
    for note in [72, 76, 79, 84]:
        mix(buf, bell(note, length - chord_at, 0.9), chord_at, 0.55)
    mix(buf, bass(48, length - chord_at), chord_at, 0.9)
    mix(buf, bass(36, length - chord_at), chord_at, 0.5)
    return finish(buf, SFX_PEAK_DB)


# --- Output and analysis -----------------------------------------------------


def write(name: str, data: np.ndarray) -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.ogg"
    try:
        sf.write(path, data, RATE, format="OGG", subtype="VORBIS")
    except Exception as error:  # libsndfile without Vorbis
        raise SystemExit(
            f"Cannot write {path.name}: libsndfile has no Ogg Vorbis support "
            f"({error}). Install a libsndfile build with Vorbis."
        ) from error
    return path


def report(path: Path) -> None:
    decoded, rate = sf.read(path)
    peak = np.abs(decoded).max()
    rms = np.sqrt(np.mean(decoded**2))
    line = (
        f"{path.name:10} {path.stat().st_size / 1024:6.1f} KiB "
        f"{len(decoded) / rate:6.2f} s  peak {db(peak):6.2f} dBFS  "
        f"RMS {db(rms):6.2f} dBFS  DC {decoded.mean():+.1e}"
    )
    line += f"  start {abs(decoded[0]):.4f} end {abs(decoded[-1]):.4f}"
    print(line)


def main() -> None:
    sounds = {"fill": fill(), "wrong": wrong(), "win": win()}
    for name, data in sounds.items():
        assert np.abs(data).max() < 1.0, f"{name} clips"
        report(write(name, data))


if __name__ == "__main__":
    main()
