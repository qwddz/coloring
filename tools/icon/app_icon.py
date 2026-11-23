"""Launcher icon from the chosen store icon (tools/store/icons/fox_brush2_b.png).

Run: tools/coloring_pipeline/.venv/bin/python tools/icon/app_icon.py
Then: FLUTTER_ROOT=/opt/homebrew/share/flutter /opt/homebrew/share/flutter/bin/dart run flutter_launcher_icons

Writes assets/icon/icon.png (legacy, the full art) and assets/icon/foreground.png
(adaptive: the art at 66% inside the safe zone, its edge faded into the
background color). Prints the background color for pubspec.yaml
(adaptive_icon_background) and writes the 512 px store icon.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "tools" / "store" / "icons" / "fox_brush2_b.png"
OUT = ROOT / "assets" / "icon"
STORE = ROOT / "tools" / "store" / "listing" / "icon_512.png"
SIZE = 1024
SCALE = 0.66


def corner_color(image: Image.Image) -> tuple[int, int, int]:
    px = [image.getpixel((x, y)) for x in (8, SIZE - 9) for y in (8, SIZE - 9)]
    return tuple(sorted(c[i] for c in px)[1] for i in range(3))


def main() -> None:
    art = Image.open(SOURCE).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    background = corner_color(art)
    art.save(OUT / "icon.png")
    art.resize((512, 512), Image.LANCZOS).save(STORE)

    inner = int(SIZE * SCALE)
    small = art.resize((inner, inner), Image.LANCZOS).convert("RGBA")
    fade = Image.new("L", (inner, inner), 0)
    margin = inner // 20
    ImageDraw.Draw(fade).rectangle((margin, margin, inner - margin, inner - margin), fill=255)
    small.putalpha(fade.filter(ImageFilter.GaussianBlur(margin / 2)))
    foreground = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    offset = (SIZE - inner) // 2
    foreground.alpha_composite(small, (offset, offset))
    foreground.save(OUT / "foreground.png")
    print("adaptive_icon_background: \"#%02x%02x%02x\"" % background)


if __name__ == "__main__":
    main()
