"""Google Play feature graphic (1024 x 500): the store icon, the name and three
colored pictures as cards.

    tools/coloring_pipeline/.venv/bin/python tools/store/feature_graphic.py

Writes tools/store/listing/feature_1024x500.png.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
ICON = ROOT / "tools" / "store" / "icons" / "fox_brush2_b.png"
FONT = ROOT / "assets" / "fonts" / "Nunito.ttf"
OUT = ROOT / "tools" / "store" / "listing" / "feature_1024x500.png"
PICTURES = ["food_pig_pie", "farm_cow_milk", "home_fox_cocoa"]
CARD_POSITIONS = [(680, 40), (450, 215), (730, 250)]
CARD_ANGLES = [-6, 4, -2]


def card(picture: str, angle: int) -> Image.Image:
    art = Image.open(ROOT / "assets" / "coloring" / "free" / picture / "colored.webp")
    art = art.convert("RGB").resize((300, 225), Image.LANCZOS)
    frame = Image.new("RGBA", (316, 241), "#fffaf0")
    frame.paste(art, (8, 8))
    return frame.rotate(angle, expand=True, resample=Image.BICUBIC)


def main() -> None:
    image = Image.new("RGB", (1024, 500), "#edb74c")
    for picture, position, angle in zip(PICTURES, CARD_POSITIONS, CARD_ANGLES):
        tile = card(picture, angle)
        shadow = Image.new("RGBA", tile.size, (0, 0, 0, 0))
        shadow.paste(Image.new("RGBA", tile.size, (90, 50, 10, 90)), (0, 0), tile.split()[3])
        shadow = shadow.filter(ImageFilter.GaussianBlur(8))
        image.paste(shadow, (position[0] + 6, position[1] + 10), shadow)
        image.paste(tile, position, tile)
    icon = Image.open(ICON).convert("RGB").resize((230, 230), Image.LANCZOS)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 229, 229), 48, fill=255)
    image.paste(icon, (60, 50), mask)
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(str(FONT), 58)
    try:
        font.set_variation_by_axes([900])
    except OSError:
        pass  # a static font has no weight axis
    draw.text((60, 300), "Animosaic", font=font, fill="#4a2c1a")
    draw.text((60, 365), "Colors", font=font, fill="#4a2c1a")
    subtitle = ImageFont.truetype(str(FONT), 30)
    try:
        subtitle.set_variation_by_axes([800])
    except OSError:
        pass
    draw.text((62, 440), "Coloring for kids", font=subtitle, fill="#9a3f1c")
    image.save(OUT)


if __name__ == "__main__":
    main()
