"""Compare preserved Air base/menu triples. Requires Pillow; no image resampling.

Usage: python3 compare-air.py docs/validation/air-2026-10-09
"""
import io
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageCms, ImageStat

root = Path(sys.argv[1])
regions = {
    "control": (0, 110, 420, 170),
    "blur": (24, 180, 364, 300),
    "glass": (24, 340, 364, 460),
    "menu": (120, 454, 370, 588),
}


def srgb(path):
    with Image.open(path) as image:
        assert image.size == (1260, 2736), (path, image.size)
        profile = image.info.get("icc_profile")
        if profile:
            return ImageCms.profileToProfile(
                image.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(profile)),
                ImageCms.createProfile("sRGB"), outputMode="RGB"
            )
        assert "srgb" in image.info, f"Unidentified color space: {path}"
        return image.convert("RGB")


result = {"color_space": "sRGB", "size_pixels": [1260, 2736], "scale": 3,
          "regions_points": regions, "mean_absolute_RGB_error_0_255": {}}
for state in ("base", "menu"):
    reference = srgb(root / state / "system.png")
    result["mean_absolute_RGB_error_0_255"][state] = {}
    for variant in ("adapter", "stream"):
        image = srgb(root / state / (variant + ".png"))
        metrics = {}
        for name, rect in regions.items():
            if name == "menu" and state == "base":
                continue
            box = tuple(value * 3 for value in rect)
            delta = ImageChops.difference(image.crop(box), reference.crop(box))
            metrics[name] = sum(ImageStat.Stat(delta).mean) / 3
        result["mean_absolute_RGB_error_0_255"][state][variant] = metrics
print(json.dumps(result, indent=2))
