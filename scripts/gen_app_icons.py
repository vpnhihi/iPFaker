#!/usr/bin/env python3
"""Generate iOS app icon PNGs from a square source image."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "theos" / "app" / "Resources"

SIZES = {
    "AppIcon60x60@2x.png": 120,
    "AppIcon60x60@3x.png": 180,
    "AppIcon-Small@2x.png": 58,
    "AppIcon-Small@3x.png": 87,
    "AppIcon-Small-40@2x.png": 80,
    "AppIcon-Small-40@3x.png": 120,
}


def main() -> int:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if not src or not src.is_file():
        # default session asset
        cand = Path(
            r"C:\Users\Pem\.grok\sessions\C%3A%5CUsers%5CPem\019f7d62-a913-7173-8e2d-0573906b16ad"
            r"\assets\image-25d2e8d8-42cc-473a-b4f3-614df9263e78.png"
        )
        src = cand if cand.is_file() else None
    if not src or not src.is_file():
        print("Usage: python scripts/gen_app_icons.py path/to/icon.png")
        return 1

    img = Image.open(src).convert("RGBA")
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    master = OUT / "AppIcon-Source.png"
    img.save(master, "PNG")
    print("master", master)

    for name, px in SIZES.items():
        r = img.resize((px, px), Image.Resampling.LANCZOS)
        path = OUT / name
        r.save(path, "PNG", optimize=True)
        print(name, px, path.stat().st_size)
    print("OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
