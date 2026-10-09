"""Compare research batches against their independent system screenshots.

Requires Pillow. Usage: python3 compare-variants.py PATH_WITH_BASE_AND_MENU
Incomplete snapshot-hierarchy diagnostics are excluded from pixel metrics.
"""
import io
import json
import sys
from pathlib import Path
from PIL import Image, ImageChops, ImageCms, ImageStat

root = Path(sys.argv[1])
regions = {
    "control": (0, 110, 402, 170),
    "blur": (24, 180, 364, 300),
    "glass": (24, 340, 364, 460),
    "menu": (120, 442, 370, 588),
}


def srgb(path):
    with Image.open(path) as image:
        assert image.size == (1206, 2622)
        profile = image.info.get("icc_profile")
        if profile:
            return ImageCms.profileToProfile(
                image.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(profile)),
                ImageCms.createProfile("sRGB"), outputMode="RGB"
            )
        assert "srgb" in image.info, "Image must identify its color space"
        return image.convert("RGB")


results = {"color_space": "sRGB", "regions_points": regions, "states": {}}
for state in ("base", "menu"):
    directory = root / state
    reference = srgb(directory / "system.png")
    metadata = json.loads((directory / "latest.json").read_text())
    variants = {}
    for path in sorted(directory.glob("*.png")):
        if path.stem in ("snapshot-hierarchy", "system"):
            continue
        image = srgb(path)
        metrics = {}
        for name, rect in regions.items():
            if name == "menu" and state == "base":
                continue
            if name == "glass" and state == "menu":
                continue  # Settled menu overlaps the glass panel.
            box = tuple(value * 3 for value in rect)
            delta = ImageChops.difference(image.crop(box), reference.crop(box))
            metrics[name] = sum(ImageStat.Stat(delta).mean) / 3
        variants[path.stem] = metrics
    results["states"][state] = {"metadata": metadata, "mean_absolute_RGB_error_0_255": variants}
print(json.dumps(results, indent=2))
