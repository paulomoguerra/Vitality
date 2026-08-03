#!/usr/bin/env python3
"""
Render design/icon.svg into the app's AppIcon asset catalogue.

Renders one 1024px master with a headless Chromium, then downscales with
LANCZOS. Downscaling a single master (rather than rendering each size straight
from SVG) keeps the blur/glow filters visually consistent across sizes —
rendering a 16px canvas directly would resolve those filters completely
differently and the small icons would not match the large one.

    python3 scripts/make-icon.py

Requires Pillow and a Chromium-based browser.
"""
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SVG = os.path.join(ROOT, "design", "icon.svg")
ICONSET = os.path.join(ROOT, "Vitality", "Assets.xcassets", "AppIcon.appiconset")

BROWSERS = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
]

# (points, scale) -> pixel size. macOS asset catalogues want both 1x and 2x.
VARIANTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
            (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]


def find_browser():
    for path in BROWSERS:
        if os.path.exists(path):
            return path
    sys.exit("error: no Chromium-based browser found to render the SVG.")


def render_master(dest):
    browser = find_browser()
    html = os.path.join(os.path.dirname(dest), "_icon.html")
    with open(SVG) as f:
        svg = f.read()
    with open(html, "w") as f:
        f.write(f"<html><body style='margin:0'>{svg}</body></html>")

    subprocess.run([
        browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
        "--force-device-scale-factor=1", "--default-background-color=00000000",
        f"--screenshot={dest}", "--window-size=1024,1024", f"file://{html}",
    ], capture_output=True, timeout=120)
    os.remove(html)
    if not os.path.exists(dest):
        sys.exit("error: headless render produced no PNG.")
    return dest


def main():
    try:
        from PIL import Image
    except ImportError:
        sys.exit("error: Pillow required — pip3 install Pillow")

    if not os.path.exists(SVG):
        sys.exit(f"error: {SVG} not found")

    shutil.rmtree(ICONSET, ignore_errors=True)
    os.makedirs(ICONSET, exist_ok=True)

    master_path = os.path.join(ICONSET, "_master.png")
    render_master(master_path)
    master = Image.open(master_path).convert("RGBA")
    os.remove(master_path)

    images = []
    for points, scale in VARIANTS:
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(ICONSET, name))
        images.append({
            "size": f"{points}x{points}",
            "idiom": "mac",
            "filename": name,
            "scale": f"{scale}x",
        })

    with open(os.path.join(ICONSET, "Contents.json"), "w") as f:
        json.dump({"images": images, "info": {"version": 1, "author": "xcode"}}, f, indent=2)

    print(f"wrote {len(images)} icon sizes to {os.path.relpath(ICONSET, ROOT)}")


if __name__ == "__main__":
    main()
