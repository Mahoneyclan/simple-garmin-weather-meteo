"""
Generates all Connect IQ store assets in one pass.

Outputs written to store_assets/:
  cover_500x500.png
  hero_1440x720.png
  preview_view_500x500.png
  preview_view_with_watch_500x500.png
  preview_forecast_500x500.png
  preview_forecast_with_watch_500x500.png

Requirements: pip install pillow numpy
Run from repo root: python image-generators/generate_store_assets.py
"""

from PIL import Image, ImageDraw, ImageFont
import numpy as np
from pathlib import Path

HERE    = Path(__file__).parent
ROOT    = HERE.parent
STORE   = ROOT / "store_assets"
FONT    = "/System/Library/Fonts/SFNS.ttf"
BG_DARK = np.array([12, 17, 32], dtype=float)
BG_RGB  = (12, 17, 32)
WHITE   = (255, 255, 255)
SUBWHT  = (190, 200, 215)
GREY    = (130, 145, 165)
DIMGREY = (90, 105, 120)


# ── Shared helpers ────────────────────────────────────────────────────────────

def grad_color(x: int, g_start: int, g_end: int) -> np.ndarray:
    t = max(0.0, min(1.0, (x - g_start) / (g_end - g_start)))
    return (BG_DARK * (1 - t) + 255 * t).astype(np.uint8)


def gradient_canvas(w: int, h: int, g_start: int, g_end: int) -> Image.Image:
    arr = np.zeros((h, w, 3), dtype=np.uint8)
    for x in range(w):
        arr[:, x] = grad_color(x, g_start, g_end)
    return Image.fromarray(arr, "RGB")


def remove_watch_bg(img: Image.Image, wx: int, g_start: int, g_end: int) -> Image.Image:
    """Replace white simulator chrome with the matching gradient colour."""
    ww, wh = img.size
    tmp  = img.copy()
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
    watch_arr = np.array(img)
    mask = (tmp_arr[:, :, 0] == 1) & (tmp_arr[:, :, 1] == 254) & (tmp_arr[:, :, 2] == 1)
    for px in range(ww):
        watch_arr[mask[:, px], px] = grad_color(wx + px, g_start, g_end)
    return Image.fromarray(watch_arr, "RGB")


def paste_icon(canvas: Image.Image, size: int, pos: tuple) -> None:
    icon = Image.open(STORE / "icon_128x128.png").convert("RGBA").resize(
        (size, size), Image.LANCZOS
    )
    arr = np.array(icon)
    arr[(arr[:, :, 0] < 30) & (arr[:, :, 1] < 30) & (arr[:, :, 2] < 40), 3] = 0
    tile = Image.new("RGBA", (size, size), (12, 17, 32, 255))
    tile.paste(Image.fromarray(arr, "RGBA"), mask=Image.fromarray(arr, "RGBA").split()[3])
    canvas.paste(tile.convert("RGB"), pos)


# ── Cover 500×500 ─────────────────────────────────────────────────────────────

def generate_cover() -> None:
    W, H, GS, GE = 500, 500, 180, 380

    raw  = Image.open(HERE / "Cover/Watch.png").convert("RGB")
    wh   = 420
    ww   = int(raw.width * wh / raw.height)
    wx   = W - ww - 5
    wy   = (H - wh) // 2
    watch = remove_watch_bg(raw.resize((ww, wh), Image.LANCZOS), wx, GS, GE)

    canvas = gradient_canvas(W, H, GS, GE)
    canvas.paste(watch, (wx, wy))
    paste_icon(canvas, 52, (20, 20))

    draw    = ImageDraw.Draw(canvas)
    f_title = ImageFont.truetype(FONT, 36)
    f_meta  = ImageFont.truetype(FONT, 17)
    f_feat  = ImageFont.truetype(FONT, 14)

    X, y = 20, 90
    for line in ["SimpleGlance", "Weather", "Widget"]:
        draw.text((X, y), line, font=f_title, fill=WHITE)
        y += f_title.getbbox(line)[3] + 10
    y += 30
    for line in ["Open-Meteo", "No API key required"]:
        draw.text((X, y), line, font=f_meta, fill=GREY)
        y += f_meta.getbbox(line)[3] + 6
    draw.text((X, y + 8), "Temp · Wind · Rain", font=f_feat, fill=DIMGREY)

    out = STORE / "cover_500x500.png"
    canvas.save(out)
    print(f"Saved {out}")


# ── Hero 1440×720 ─────────────────────────────────────────────────────────────

def generate_hero() -> None:
    W, H, GS, GE = 1440, 720, 500, 950

    raw  = Image.open(HERE / "Hero/Watch.png").convert("RGB")
    wh   = 700
    ww   = int(raw.width * wh / raw.height)
    wx   = W - ww - 10
    wy   = (H - wh) // 2
    watch = remove_watch_bg(raw.resize((ww, wh), Image.LANCZOS), wx, GS, GE)

    canvas = gradient_canvas(W, H, GS, GE)
    canvas.paste(watch, (wx, wy))
    paste_icon(canvas, 72, (55, 45))

    draw    = ImageDraw.Draw(canvas)
    f_title = ImageFont.truetype(FONT, 92)
    f_sub   = ImageFont.truetype(FONT, 52)
    f_meta  = ImageFont.truetype(FONT, 26)
    f_feat  = ImageFont.truetype(FONT, 22)

    X  = 55
    y1 = 148
    draw.text((X, y1), "SimpleGlance", font=f_title, fill=WHITE)
    y2 = y1 + f_title.getbbox("SimpleGlance")[3] + 16
    draw.text((X, y2), "Weather Widget", font=f_sub, fill=SUBWHT)
    y3 = y2 + f_sub.getbbox("Weather Widget")[3] + 38
    draw.text((X, y3), "Open-Meteo · No API key required", font=f_meta, fill=GREY)
    y4 = y3 + f_meta.getbbox("Open-Meteo · No API key required")[3] + 10
    draw.text((X, y4), "Temperature · Wind · Rain · Two locations", font=f_feat, fill=DIMGREY)

    out = STORE / "hero_1440x720.png"
    canvas.save(out)
    print(f"Saved {out}")


# ── Previews 500×500 ──────────────────────────────────────────────────────────

def make_preview(src: Path, dst: Path, inner: int = 440) -> None:
    img = Image.open(src).convert("RGB")
    ow, oh   = img.size
    scale    = min(inner / ow, inner / oh)
    sw, sh   = int(ow * scale), int(oh * scale)
    img      = img.resize((sw, sh), Image.LANCZOS)
    canvas   = Image.new("RGB", (500, 500), BG_RGB)
    canvas.paste(img, ((500 - sw) // 2, (500 - sh) // 2))
    canvas.save(dst)
    print(f"Saved {dst}  ({sw}x{sh} → 500x500)")


def generate_previews() -> None:
    src = HERE / "Preview"
    previews = [
        ("View.png",                "preview_view_500x500.png"),
        ("View with Watch.png",     "preview_view_with_watch_500x500.png"),
        ("Forecast.png",            "preview_forecast_500x500.png"),
        ("Forecast with Watch.png", "preview_forecast_with_watch_500x500.png"),
    ]
    for name, out in previews:
        make_preview(src / name, STORE / out)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    STORE.mkdir(parents=True, exist_ok=True)
    generate_cover()
    generate_hero()
    generate_previews()


if __name__ == "__main__":
    main()
