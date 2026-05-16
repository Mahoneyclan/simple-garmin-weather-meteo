"""
Generates store_assets/hero_1440x720.png for the SimpleGlance Weather Widget
Connect IQ store listing.

Requirements: pip install pillow numpy
Run from repo root: python docs/generate_hero.py
"""

from PIL import Image, ImageDraw, ImageFont
import numpy as np
from pathlib import Path

ROOT     = Path(__file__).parent.parent
FONT     = "/System/Library/Fonts/SFNS.ttf"
BG_L     = np.array([12, 17, 32], dtype=float)
WHITE    = (255, 255, 255)
SUBWHITE = (190, 200, 215)
GREY     = (130, 145, 165)
DIMGREY  = (90, 105, 120)
W, H     = 1440, 720
GRAD_START, GRAD_END = 500, 950


def grad_color(x: int) -> np.ndarray:
    t = max(0.0, min(1.0, (x - GRAD_START) / (GRAD_END - GRAD_START)))
    return (BG_L * (1 - t) + 255 * t).astype(np.uint8)


def remove_watch_bg(watch_img: Image.Image, wx: int) -> Image.Image:
    """Flood-fill white simulator background and replace with matching gradient colour."""
    ww, wh = watch_img.size
    tmp = watch_img.copy()
    FILL = (1, 254, 1)
    seeds = (
        [(x, 0)      for x in range(0, ww, 6)] +
        [(x, wh - 1) for x in range(0, ww, 6)] +
        [(0, y)      for y in range(0, wh, 6)] +
        [(ww - 1, y) for y in range(0, wh, 6)]
    )
    for seed in seeds:
        if all(c > 200 for c in tmp.getpixel(seed)):
            ImageDraw.floodfill(tmp, seed, FILL, thresh=40)

    tmp_arr   = np.array(tmp)
    watch_arr = np.array(watch_img)
    bg_mask   = (tmp_arr[:, :, 0] == 1) & (tmp_arr[:, :, 1] == 254) & (tmp_arr[:, :, 2] == 1)
    for px in range(ww):
        col = grad_color(wx + px)
        watch_arr[bg_mask[:, px], px] = col
    return Image.fromarray(watch_arr, "RGB")


def main():
    f_title = ImageFont.truetype(FONT, 92)
    f_sub   = ImageFont.truetype(FONT, 52)
    f_meta  = ImageFont.truetype(FONT, 26)
    f_feat  = ImageFont.truetype(FONT, 22)

    # Watch
    watch_raw    = Image.open(ROOT / "docs/screenshot_samford_watch.png").convert("RGB")
    watch_h      = 700
    scale        = watch_h / watch_raw.height
    watch_w      = int(watch_raw.width * scale)
    watch_scaled = watch_raw.resize((watch_w, watch_h), Image.LANCZOS)
    wx           = W - watch_w - 10
    wy           = (H - watch_h) // 2
    watch_final  = remove_watch_bg(watch_scaled, wx)

    # Background gradient
    bg_arr = np.zeros((H, W, 3), dtype=np.uint8)
    for x in range(W):
        bg_arr[:, x] = grad_color(x)
    hero = Image.fromarray(bg_arr, "RGB")
    hero.paste(watch_final, (wx, wy))

    draw = ImageDraw.Draw(hero)

    # Icon
    icon_src = Image.open(ROOT / "store_assets/icon_128x128.png").convert("RGBA")
    icon     = icon_src.resize((72, 72), Image.LANCZOS)
    i_arr    = np.array(icon)
    i_arr[(i_arr[:, :, 0] < 30) & (i_arr[:, :, 1] < 30) & (i_arr[:, :, 2] < 40), 3] = 0
    icon_c   = Image.fromarray(i_arr, "RGBA")
    tile     = Image.new("RGBA", (72, 72), (12, 17, 32, 255))
    tile.paste(icon_c, mask=icon_c.split()[3])
    hero.paste(tile.convert("RGB"), (55, 45))

    # Text
    X  = 55
    b1 = f_title.getbbox("SimpleGlance")
    y1 = 148
    draw.text((X, y1), "SimpleGlance", font=f_title, fill=WHITE)

    b2 = f_sub.getbbox("Weather Widget")
    y2 = y1 + b1[3] + 16
    draw.text((X, y2), "Weather Widget", font=f_sub, fill=SUBWHITE)

    b3 = f_meta.getbbox("Open-Meteo · No API key required")
    y3 = y2 + b2[3] + 38
    draw.text((X, y3), "Open-Meteo · No API key required", font=f_meta, fill=GREY)

    y4 = y3 + b3[3] + 10
    draw.text((X, y4), "Temperature · Wind · Rain · Two locations", font=f_feat, fill=DIMGREY)

    out = ROOT / "store_assets/hero_1440x720.png"
    hero.save(out)
    print(f"Saved {out}")


if __name__ == "__main__":
    main()
