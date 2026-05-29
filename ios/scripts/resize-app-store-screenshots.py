#!/usr/bin/env python3
"""Resize App Store source screenshots to required Connect dimensions."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSET_DIRS = [
    Path.home() / ".cursor/projects/Users-porari-kaihatu-ios-yamabikochat/assets",
    Path.home() / ".cursor/projects/Users-porari-kaihatu-ios-yamabikochat-ios/assets",
]

OUT = ROOT / "AppStoreScreenshots"
BG = (245, 245, 247, 255)


def resize_fit_pad(img: Image.Image, target_w: int, target_h: int) -> Image.Image:
    src_w, src_h = img.size
    scale = min(target_w / src_w, target_h / src_h)
    new_w = round(src_w * scale)
    new_h = round(src_h * scale)
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (target_w, target_h), BG)
    canvas.paste(resized, ((target_w - new_w) // 2, (target_h - new_h) // 2))
    return canvas.convert("RGB")


JOBS = [
    ("ipad-13-inch", "01-split-empty.png", "simulator_screenshot_A538891C*.png", 2048, 2732),
    ("ipad-13-inch", "02-settings-api.png", "simulator_screenshot_30449E51*.png", 2048, 2732),
    ("ipad-13-inch", "03-settings-system-prompt.png", "simulator_screenshot_E134CA2B*.png", 2048, 2732),
    ("iphone-6.5-inch", "01-settings-api.png", "9CDD7159*.png", 1284, 2778),
    ("iphone-6.5-inch", "02-chat-math.png", "74B73A4E*.png", 1284, 2778),
    ("iphone-6.5-inch", "03-token-statistics.png", "7B9DD486*.png", 1284, 2778),
]


def resolve_source(pattern: str) -> Path:
    for assets in ASSET_DIRS:
        if not assets.exists():
            continue
        matches = sorted(assets.glob(pattern))
        if matches:
            return matches[0]
    searched = ", ".join(str(d) for d in ASSET_DIRS)
    raise FileNotFoundError(f"No asset matching {pattern} in [{searched}]")


def main() -> None:
    for folder, name, pattern, width, height in JOBS:
        try:
            src = resolve_source(pattern)
        except FileNotFoundError as err:
            print(f"Skip {folder}/{name}: {err}")
            continue
        out_dir = OUT / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        out = resize_fit_pad(Image.open(src).convert("RGBA"), width, height)
        out_path = out_dir / name
        out.save(out_path, format="PNG", optimize=True)
        print(f"Wrote {out_path} ({width}×{height}) from {src.name}")


if __name__ == "__main__":
    main()
