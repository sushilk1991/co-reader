"""Draw the toolbar icons: a paper-coloured rounded square with a dark serif C.

    uv run --with pillow python tools/make_icons.py

Writes icons/icon{16,32,48,128}.png next to the manifest.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

PAPER = (246, 239, 225, 255)
EDGE = (220, 207, 184, 255)
INK = (42, 37, 32, 255)
FONT = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
SCALE = 8  # draw large, then downsample, so curves stay smooth at 16 px

out = Path(__file__).resolve().parent.parent / "icons"
out.mkdir(exist_ok=True)

for size in (16, 32, 48, 128):
    big = size * SCALE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (0, 0, big - 1, big - 1),
        radius=round(big * 0.22),
        fill=PAPER,
        outline=EDGE,
        width=max(1, round(big * 0.03)),
    )
    font = ImageFont.truetype(FONT, round(big * 0.78))
    left, top, right, bottom = draw.textbbox((0, 0), "C", font=font)
    draw.text(
        ((big - (right - left)) / 2 - left, (big - (bottom - top)) / 2 - top),
        "C",
        font=font,
        fill=INK,
    )
    image.resize((size, size), Image.LANCZOS).save(out / f"icon{size}.png", optimize=True)
    print(out / f"icon{size}.png")
