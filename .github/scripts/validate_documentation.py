#!/usr/bin/env python3
"""Check rendered module coverage, conditional adapters, and tutorial diffs."""
import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
site = root / ".build/docc-site"
for platform, path, expected, excluded in [
    ("iOS", site, "uikitcapturesource", "appkitcapturesource"),
    ("macOS", site / "macos", "appkitcapturesource", "uikitcapturesource"),
]:
    for module in ["screenerkit", "screenercore", "screenermcp"]:
        data = json.loads((path / "data/documentation" / f"{module}.json").read_text())
        assert data["metadata"]["title"], f"Empty {module} landing page"
    symbols = path / "data/documentation/screenerkit"
    assert (symbols / f"{expected}.json").is_file(), f"Missing {platform} adapter"
    assert not (symbols / f"{excluded}.json").exists(), f"Wrong {platform} symbol graph"
    tutorials = list((path / "data/tutorials").rglob("firsttrace.json"))
    assert len(tutorials) == 1, f"Expected one {platform} tutorial"
    subprocess.run([sys.executable, str(root / ".github/scripts/validate_tutorial_output.py"),
                    "--tutorial-json", str(tutorials[0])], check=True)
    print(f"PASS: {platform} modules, conditional symbols, and tutorial diffs")

# Compile tutorial snapshots and complete article listings against the iOS modules.
import re
import tempfile
sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()
bin_path = Path(subprocess.check_output([
    "swift", "build", "--triple", "arm64-apple-ios16.0", "--sdk", sdk, "--show-bin-path"
], cwd=root, text=True).strip())
module_paths = [bin_path, bin_path / "Modules"]
command = ["swiftc", "-typecheck", "-D", "DEBUG", "-target", "arm64-apple-ios16.0", "-sdk", sdk]
for path in module_paths:
    command += ["-I", str(path)]
catalog = root / "Sources/ScreenerKit/Documentation.docc"
for snapshot in sorted((catalog / "Tutorials").glob("*.swift")):
    subprocess.run([*command, str(snapshot)], check=True)
    print(f"PASS: iOS tutorial snapshot {snapshot.name}")
article = (catalog / "RecordingAReproduction.md").read_text()
listing = re.search(r"```swift\n(.*?)```", article, re.S).group(1)
with tempfile.TemporaryDirectory() as temporary:
    snippet = Path(temporary) / "RecordingExample.swift"
    snippet.write_text(listing)
    subprocess.run([*command, str(snippet)], check=True)
print("PASS: iOS recording article example")
