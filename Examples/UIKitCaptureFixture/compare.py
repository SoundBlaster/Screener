"""Measure fixture regions in paired captures (requires Pillow).

Usage: python3 compare.py docs/validation/uikit-2026-10-09
No images are changed. ICC-tagged captures are converted to sRGB in memory.
"""
import io
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageCms, ImageStat

root = Path(sys.argv[1])
regions = {
    "blur": ("materials", (24, 180, 364, 300)),
    "glass": ("materials", (24, 340, 364, 460)),
    "menu": ("menu", (120, 442, 370, 588)),
    "control_stripes": ("materials", (0, 110, 402, 170)),
}


def srgb(path):
    with Image.open(path) as image:
        assert image.size == (1206, 2622), "Regions are for the 402x874pt, 3x fixture"
        profile = image.info.get("icc_profile")
        if profile:
            return ImageCms.profileToProfile(
                image.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(profile)),
                ImageCms.createProfile("sRGB"), outputMode="RGB"
            )
        assert "srgb" in image.info, "Image must identify its color space"
        return image.convert("RGB")


results = {}
for name, (pair, rect) in regions.items():
    box = tuple(value * 3 for value in rect)
    adapter = srgb(root / f"{pair}-adapter.png").crop(box)
    system = srgb(root / f"{pair}-system.png").crop(box)
    delta = ImageChops.difference(adapter, system)
    pixels = delta.load()
    different = sum(max(pixels[x, y]) > 10 for y in range(delta.height) for x in range(delta.width))
    results[name] = {
        "region_points": rect,
        "mean_absolute_sRGB_error_0_255": sum(ImageStat.Stat(delta).mean) / 3,
        "percent_pixels_any_channel_difference_gt_10": different * 100 / (delta.width * delta.height),
    }
print(json.dumps(results, indent=2))
