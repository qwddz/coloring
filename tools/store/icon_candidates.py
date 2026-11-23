"""Generates app icon candidates with Gemini in the style of the puzzles icon.

    tools/coloring_pipeline/.venv/bin/python tools/store/icon_candidates.py [name ...]

Writes tools/store/icons/<name>.png (1:1). The puzzles icon is the style
reference, so both apps look like one family. Costs a few cents per image.
"""

import io
import os
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REFERENCE = PROJECT.parent / "puzzles" / "assets" / "icon" / "icon.png"
MODEL = os.environ.get("CP_GEMINI_MODEL", "gemini-nano-banana-2.1")

STYLE = (
    "Create a mobile app icon for a coloring app, the sister app of the game "
    "whose icon is the reference image. Match the reference art style exactly: "
    "bold dark brown outlines, smooth flat cartoon shading, warm saturated "
    "colors, big glossy cartoon eyes, the same cute fox character design. "
    "The design fills the whole square, centered, simple and readable at "
    "small size, few large shapes, a plain warm yellow background like the "
    "reference, no text, no letters, no frame, no border, no rounded corners, "
    "no puzzle pieces."
)

CONCEPTS = {
    "fox_half": "The same cute fox face, the left half fully colored orange and cream, the right half still uncolored white line art with dark outlines, a paintbrush tip with orange paint at the border between the halves.",
    "fox_half2": "The same cute fox face, perfectly symmetric, both ears fully visible. The left half is fully colored orange and cream, the right half is uncolored white with only the dark outlines, split by a straight vertical line down the middle. A small paintbrush with orange paint touches the split line at the lower right cheek, not covering the ears or eyes. One uniform background color from edge to edge.",
    "fox_rainbow": "The same cute fox face peeking from behind a big rainbow arc; the left half of the rainbow is brightly colored, the right half is still white with only dark outlines. Everything fully inside the square.",
    "fox_crayon_stroke": "The same cute fox face, fully colored, with one big chunky orange crayon at the lower right drawing a thick wavy orange stroke under the chin. Everything fully inside the square, nothing cut off by the edges.",
    "fox_splash": "The same cute fox face, fully colored, surrounded by a few round bright paint splashes in red, blue, green and purple behind its head like a halo. Everything fully inside the square.",
    "fox_paint_ears": "The same cute fox face; the face is colored orange and cream, one ear is dipped in blue paint and the other in green paint, with a small paint drip. Everything fully inside the square.",
    "fox_page": "The same cute fox face popping out of a white coloring book page with a few uncolored outline flowers on it, the fox itself fully colored, a small paintbrush lying on the page. Everything fully inside the square.",
    "fox_brush2": "The same cute smiling fox face, holding up a big paintbrush in its orange furry paw (the paw is the same orange as the fox fur, not brown); the brush tip has orange paint and a drop of paint. A few small colorful paint splashes around (blue, green, red). Show only the head and the paw with the brush, no body; the whole brush and paw are fully inside the square with a margin, nothing cut off by the edges.",
    "fox_brush": "The same cute fox face, smiling, holding a big paintbrush with a drop of orange paint, small colorful paint splashes around.",
    "fox_palette": "The same cute fox face peeking over a round wooden painter's palette with five big bright paint blobs: red, blue, green, yellow, purple.",
    "fox_crayons": "The same cute fox face, smiling, with three big chunky crayons (red, blue, green) fanned out in front of its chin.",
}


def load_env() -> None:
    env = PROJECT / ".env"
    for line in env.read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def main() -> None:
    load_env()
    from google import genai
    from google.genai import types

    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    out = HERE / "icons"
    out.mkdir(exist_ok=True)
    reference = Image.open(REFERENCE)
    config = types.GenerateContentConfig(
        response_modalities=["IMAGE"],
        image_config=types.ImageConfig(aspect_ratio="1:1"),
    )
    names = sys.argv[1:] or list(CONCEPTS)
    for name in names:
        response = client.models.generate_content(
            model=MODEL,
            contents=[reference, f"{STYLE}\nSubject: {CONCEPTS[name]}"],
            config=config,
        )
        data = [p.inline_data.data for p in response.parts or [] if p.inline_data and not p.thought]
        if not data:
            print(f"{name}: no image")
            continue
        image = Image.open(io.BytesIO(data[-1])).convert("RGB")
        image.save(out / f"{name}.png")
        print(f"{name}: {image.size}")


if __name__ == "__main__":
    main()
