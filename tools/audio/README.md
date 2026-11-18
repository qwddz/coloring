# Audio synthesis

`synth.py` synthesizes the app's sound effects into `assets/audio/`, with no third-party samples:

- `fill.ogg`: soft "pop" when a region is colored;
- `wrong.ogg`: low soft "boop" for a color that does not belong;
- `win.ogg`: happy arpeggio and a C major chord (about 2.7 s), ported from the puzzles app.

Additive synthesis with soft envelopes. Effects peak at -3 dBFS. Output is deterministic.

```bash
cd tools/audio
uv run synth.py
```

The script prints size, length and peak per file. If libsndfile cannot write Vorbis it stops with an error (the app loads only `.ogg`).
