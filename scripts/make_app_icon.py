"""Draw the Mac app icon: a paper page with a dark serif C and a bookmark ribbon.

    uv run --with pillow python scripts/make_app_icon.py

Same mark as the browser extension (integrations/web-extension/tools/make_icons.py),
on Apple's macOS grid: an 824 px rounded square centred in a 1024 px canvas, so the
icon sits at the same size as its neighbours in the Dock.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PAPER_TOP, PAPER_BOTTOM = (250, 245, 234), (240, 231, 213)
EDGE = (220, 207, 184, 255)
INK = (42, 37, 32, 255)
RIBBON = (179, 64, 42, 255)  # the app's accent
FONT = "/System/Library/Fonts/Supplemental/Georgia Bold.ttf"
S = 2  # supersample
N, BOX, R = 1024 * S, 824 * S, 185 * S
X0 = (N - BOX) // 2
X1 = X0 + BOX

mask = Image.new("L", (N, N), 0)
ImageDraw.Draw(mask).rounded_rectangle((X0, X0, X1, X1), radius=R, fill=255)

icon = Image.new("RGBA", (N, N), (0, 0, 0, 0))
shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 90), (0, 12 * S), mask)
icon.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * S)))

page = Image.new("RGBA", (N, N))
px = ImageDraw.Draw(page)
for y in range(X0, X1 + 1):
    t = (y - X0) / BOX
    px.line((X0, y, X1, y), fill=tuple(round(a + (b - a) * t) for a, b in zip(PAPER_TOP, PAPER_BOTTOM)) + (255,))
# Bookmark ribbon hanging from the top edge, with a notch cut into its end.
rx0, rx1, ry = X0 + round(BOX * 0.76), X0 + round(BOX * 0.86), X0 + round(BOX * 0.33)
px.polygon([(rx0, X0), (rx1, X0), (rx1, ry), ((rx0 + rx1) // 2, ry - round(BOX * 0.05)), (rx0, ry)], fill=RIBBON)
font = ImageFont.truetype(FONT, round(BOX * 0.74))
l, t, r, b = px.textbbox((0, 0), "C", font=font)
px.text((X0 + (BOX - (r - l)) / 2 - l - BOX * 0.07, X0 + (BOX - (b - t)) / 2 - t + BOX * 0.02), "C", font=font, fill=INK)
px.rounded_rectangle((X0, X0, X1, X1), radius=R, outline=EDGE, width=4 * S)
icon.paste(page, (0, 0), mask)

out = Path(__file__).resolve().parent.parent / "Sources/CoreaderApp/Assets.xcassets"
iconset = out / "AppIcon.appiconset"
iconset.mkdir(parents=True, exist_ok=True)
images = []
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        icon.resize((points * scale,) * 2, Image.LANCZOS).save(iconset / name, optimize=True)
        images.append({"idiom": "mac", "size": f"{points}x{points}", "scale": f"{scale}x", "filename": name})
info = {"author": "xcode", "version": 1}
(iconset / "Contents.json").write_text(json.dumps({"images": images, "info": info}, indent=2) + "\n")
(out / "Contents.json").write_text(json.dumps({"info": info}, indent=2) + "\n")
