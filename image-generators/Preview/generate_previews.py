"""
Generates 500x500 store preview images from simulator screenshots.

Input:  image-generators/Preview/View.png      — main watch screen (260x260)
        image-generators/Preview/Forecast.png  — forecast screen   (260x260)
Output: store_assets/preview_view_500x500.png
        store_assets/preview_forecast_500x500.png

Requirements: pip install pillow
Run from repo root: python image-generators/Preview/generate_previews.py
"""

from PIL import Image
from pathlib import Path

ROOT       = Path(__file__).parent.parent.parent
INPUT_DIR  = Path(__file__).parent
OUTPUT_DIR = ROOT / "store_assets"
BG_COLOR   = (12, 17, 32)     # same dark navy as cover/hero
TARGET     = 500               # store requires 500x500
INNER      = 440               # screen fills this much of the canvas


def make_preview(src: Path, dst: Path) -> None:
    img = Image.open(src).convert("RGB")

    # Scale to INNER x INNER maintaining aspect ratio (resize handles both up and down)
    orig_w, orig_h = img.size
    scale    = min(INNER / orig_w, INNER / orig_h)
    scaled_w = int(orig_w * scale)
    scaled_h = int(orig_h * scale)
    img      = img.resize((scaled_w, scaled_h), Image.LANCZOS)

    # Centre on TARGET x TARGET dark background
    canvas = Image.new("RGB", (TARGET, TARGET), BG_COLOR)
    x = (TARGET - scaled_w) // 2
    y = (TARGET - scaled_h) // 2
    canvas.paste(img, (x, y))

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    canvas.save(dst)
    print(f"Saved {dst}  ({scaled_w}x{scaled_h} → {TARGET}x{TARGET})")


def main():
    make_preview(
        INPUT_DIR / "View.png",
        OUTPUT_DIR / "preview_view_500x500.png",
    )

    make_preview(
        INPUT_DIR / "View with Watch.png",
        OUTPUT_DIR / "preview_view_with_watch_500x500.png",
    )

    make_preview(
        INPUT_DIR / "Forecast.png",
        OUTPUT_DIR / "preview_forecast_500x500.png",
    )

    make_preview(
        INPUT_DIR / "Forecast with Watch.png",
        OUTPUT_DIR / "preview_forecast_with_watch_500x500.png",
    )



if __name__ == "__main__":
    main()
