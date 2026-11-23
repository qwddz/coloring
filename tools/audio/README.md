# Audio synthesis

`synth.py` synthesizes the app's sounds into `assets/audio/`, with no third-party samples:

- `fill.ogg`: soft "pop" when a region is colored;
- `wrong.ogg`: low soft "boop" for a color that does not belong;
- `win.ogg`: happy arpeggio and a C major chord (about 2.7 s), ported from the puzzles app;
- `music.ogg`: a seamless 45.7 s background loop: 16 bars at 84 BPM in F major over I–vi–IV–V, kalimba-like plucks on a warm detuned pad with a soft bass. It is a calmer track than the puzzles app's loop (C major, 100 BPM), so the two apps do not sound the same. Notes ringing past the end are wrapped onto the start, so the loop has no click.

Additive synthesis with soft envelopes and nothing above 7 kHz. Effects peak at -3 dBFS; the music is normalized to RMS -20 dBFS (peak at most -4 dBFS). Output is deterministic (seeded velocity jitter): a rerun gives the same decoded samples, and only the Ogg stream serial number changes, so restore unchanged files with `git checkout` instead of committing them.

```bash
cd tools/audio
uv run synth.py
```

The script prints size, length, peak, RMS and DC per file, and for the music the jump across the loop seam next to the ordinary sample-to-sample steps. If libsndfile cannot write Vorbis it stops with an error (the app loads only `.ogg`).

The music can be replaced with a ready-made `assets/audio/music.ogg` without code changes.
