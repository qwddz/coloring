"""Placeholder launcher icon until the real art (Stage 7).

Run: uv run --with pillow tools/icon/placeholder_icon.py
Writes assets/icon/icon.png and assets/icon/foreground.png (1024 x 1024):
three palette dots on a white disc over the puzzles' warm yellow.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
BACKGROUND = "#eeba54"
DOTS = ["#e07b52", "#8db8d8", "#8fbf8a"]
OUT = Path(__file__).resolve().parents[2] / "assets" / "icon"


def draw_foreground(image: Image.Image) -> None:
    draw = ImageDraw.Draw(image)
    # Adaptive icons crop to the inner 66%, so stay inside that circle.
    c, r = SIZE / 2, SIZE * 0.26
    draw.ellipse((c - r, c - r, c + r, c + r), fill="#fffdf8")
    dot = SIZE * 0.07
    for i, color in enumerate(DOTS):
        x = c + (i - 1) * dot * 2.4
        draw.ellipse((x - dot, c - dot, x + dot, c + dot), fill=color)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw_foreground(foreground)
    foreground.save(OUT / "foreground.png")
    icon = Image.new("RGBA", (SIZE, SIZE), BACKGROUND)
    icon.alpha_composite(foreground)
    icon.convert("RGB").save(OUT / "icon.png")


if __name__ == "__main__":
    main()
