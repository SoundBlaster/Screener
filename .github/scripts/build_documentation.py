#!/usr/bin/env python3
"""Build separate iOS and macOS DocC sites without losing conditional APIs."""
import shutil
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
output = root / ".build/docc-site"

def run(*args):
    subprocess.run(args, cwd=root, check=True)

sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
# Build the root first: DocC replaces its output directory during conversion.
for platform, destination, base_path, options in [
    ("iOS", output, "Screener", ["--triple", "arm64-apple-ios16.0", "--sdk", sdk]),
    ("macOS", output / "macos", "Screener/macos", []),
]:
    print(f"Building {platform} documentation", flush=True)
    run("swift", "package", *options, "--allow-writing-to-directory", str(root / ".build"),
        "generate-documentation", "--target", "ScreenerKit", "--target", "ScreenerCore",
        "--target", "ScreenerMCP",
        "--output-path", str(root / ".build" / f"docc-{platform}-archives"), "--transform-for-static-hosting",
        "--hosting-base-path", base_path, "--warnings-as-errors")
    archives = root / ".build" / f"docc-{platform}-archives"
    if destination.exists():
        shutil.rmtree(destination)
    run("xcrun", "docc", "merge", *(str(archives / f"{name}.doccarchive")
        for name in ["ScreenerKit", "ScreenerCore", "ScreenerMCP"]),
        "--output-path", str(destination))
    run(sys.executable, ".github/scripts/prepare_docc_pages.py", "--output-path", str(destination),
        "--target", "ScreenerKit")
    run(sys.executable, ".github/scripts/validate_docc_pages.py", "--output-path", str(destination),
        "--target", "ScreenerKit", "--base-path", base_path)
print(f"Documentation ready: {output}")
