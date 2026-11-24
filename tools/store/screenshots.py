"""Google Play screenshots: a caption above each raw screen capture.

Raw captures (adb screencap from the emulators, profile build, status bar in
demo mode) live in tools/store/raw/<device>/<lang>/NN_name.png. Each one is
scaled into a 16:9 frame (Play allows at most 2:1, and phone captures are
20:9) under a caption in the app's language.

    tools/coloring_pipeline/.venv/bin/python tools/store/screenshots.py

Writes tools/store/listing/<device>/<lang>/NN_name.png.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "tools" / "store" / "raw"
OUT = ROOT / "tools" / "store" / "listing"
FONT = ROOT / "assets" / "fonts" / "Nunito.ttf"

# Output size per device: phone 1920x1080, tablet 2560x1440 (both 16:9).
SIZES = {"phone": (1920, 1080), "tablet": (2560, 1440)}
BACKGROUND = "#edb74c"
INK = "#4a2c1a"

# Play rules: no price, ranking or promo words ("free", "no ads", "best").
CAPTIONS = {
    "01_numbers": {
        "en": "Color by number",
        "ru": "Раскраска по номерам",
        "uk": "Розмальовка за номерами",
    },
    "02_free": {
        "en": "Tap, and the whole shape fills in",
        "ru": "Коснись — и область раскрасится",
        "uk": "Торкнись — і ділянка розфарбується",
    },
    "03_magic": {
        "en": "The magic brush colors it for you",
        "ru": "Волшебная кисть раскрасит сама",
        "uk": "Чарівний пензлик розфарбує сам",
    },
    "04_home": {
        "en": "100 cozy pictures in 10 themes",
        "ru": "100 уютных картинок в 10 темах",
        "uk": "100 затишних картинок у 10 темах",
    },
    "05_drawing": {
        "en": "A drawing pad for little artists",
        "ru": "Рисовалка для маленьких художников",
        "uk": "Малювалка для маленьких художників",
    },
    "06_works": {
        "en": "Every picture is kept in My works",
        "ru": "Все картинки хранятся в «Моих работах»",
        "uk": "Усі картинки зберігаються в «Моїх роботах»",
    },
}


def font(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_name("ExtraBold")
    except OSError:
        pass  # a static font has no named instances
    return f


def compose(raw: Path, caption: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    k = w / 1920
    image = Image.new("RGB", size, BACKGROUND)
    draw = ImageDraw.Draw(image)
    # The caption gets the top band; shrink the font until it fits the width.
    band = int(190 * k)
    pt = int(78 * k)
    while draw.textlength(caption, font=font(pt)) > w - 2 * int(80 * k):
        pt -= 2
    f = font(pt)
    draw.text((w / 2, band / 2 + int(10 * k)), caption, font=f, fill=INK, anchor="mm")

    shot = Image.open(raw).convert("RGB")
    max_w, max_h = w - 2 * int(70 * k), h - band - int(50 * k)
    scale = min(max_w / shot.width, max_h / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    x, y = (w - shot.width) // 2, band + (max_h - shot.height) // 2
    radius = int(28 * k)
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius, fill=255)
    shadow = Image.new("RGBA", (shot.width + 80, shot.height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (40, 46, shot.width + 40, shot.height + 46), radius, fill=(90, 50, 10, 110)
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(18 * k)))
    image.paste(shadow, (x - 40, y - 40), shadow)
    image.paste(shot, (x, y), mask)
    return image


def main() -> None:
    count = 0
    for device_dir in sorted(p for p in RAW.iterdir() if p.is_dir()):
        size = SIZES[device_dir.name]
        for lang_dir in sorted(p for p in device_dir.iterdir() if p.is_dir()):
            out = OUT / device_dir.name / lang_dir.name
            out.mkdir(parents=True, exist_ok=True)
            for raw in sorted(lang_dir.glob("*.png")):
                caption = CAPTIONS[raw.stem][lang_dir.name]
                compose(raw, caption, size).save(out / raw.name, optimize=True)
                count += 1
    print(f"{count} screenshots in {OUT}")


if __name__ == "__main__":
    main()
