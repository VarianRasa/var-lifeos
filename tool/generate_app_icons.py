from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
RESAMPLE = Image.Resampling.LANCZOS


def save(source: Image.Image, path: Path, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    source.resize((size, size), RESAMPLE).save(path, optimize=True)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tool/generate_app_icons.py <square-logo.png>")

    source = Image.open(sys.argv[1]).convert("RGB")
    if source.width != source.height:
        raise SystemExit("Logo must be square")
    if source.width < 1024:
        raise SystemExit("Logo must be at least 1024x1024")

    source_asset = ROOT / "assets" / "branding" / "app_icon.png"
    save(source, source_asset, 1024)

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in android_sizes.items():
        save(source, ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png", size)

    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    ios_manifest = json.loads((ios_dir / "Contents.json").read_text(encoding="utf-8"))
    for item in ios_manifest["images"]:
        filename = item.get("filename")
        if not filename:
            continue
        points = float(item["size"].split("x")[0])
        scale = int(item["scale"].removesuffix("x"))
        save(source, ios_dir / filename, round(points * scale))

    mac_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save(source, mac_dir / f"app_icon_{size}.png", size)

    windows_icon = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    source.resize((256, 256), RESAMPLE).save(
        windows_icon,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    save(source, ROOT / "web" / "favicon.png", 32)
    save(source, ROOT / "web" / "icons" / "Icon-192.png", 192)
    save(source, ROOT / "web" / "icons" / "Icon-512.png", 512)

    # Maskable icons need a safe zone so launchers can crop them to any shape.
    maskable = Image.new("RGB", (1024, 1024), source.getpixel((0, 0)))
    inset = source.resize((820, 820), RESAMPLE)
    maskable.paste(inset, (102, 102))
    save(maskable, ROOT / "web" / "icons" / "Icon-maskable-192.png", 192)
    save(maskable, ROOT / "web" / "icons" / "Icon-maskable-512.png", 512)

    save(source, ROOT / "linux" / "runner" / "resources" / "app_icon.png", 512)


if __name__ == "__main__":
    main()
