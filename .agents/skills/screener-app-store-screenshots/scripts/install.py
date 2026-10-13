#!/usr/bin/env python3
"""Copy the reusable screenshot tools and Swift adapters into a consuming app."""
import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--root", type=Path, required=True)
parser.add_argument("--app-sources", required=True)
parser.add_argument("--test-sources", required=True)
parser.add_argument("--platform", choices=["iOS", "macOS"], default="iOS")
args = parser.parse_args()
root = args.root.resolve()
skill = Path(__file__).resolve().parents[1]
suffix = "Mac" if args.platform == "macOS" else ""
entries = [(skill / "scripts/run.py", "screenshots/tools/run.py"),
           (skill / "scripts/prepare.swift", "screenshots/tools/prepare.swift"),
           (skill / ("assets/ScreenshotHarness" + suffix + ".swift"), args.app_sources + "/ScreenshotHarness.swift"),
           (skill / ("assets/ScreenshotScenario" + suffix + ".swift"), args.test_sources + "/ScreenshotScenario.swift")]
if suffix:
    entries.append((skill / "scripts/run_macos.py", "screenshots/tools/run_macos.py"))
    entries.append((skill / "assets/ScreenshotRunnerMac.entitlements", args.test_sources + "/ScreenshotRunner.entitlements"))
for source, relative in entries:
    target = (root / relative).resolve()
    if not target.is_relative_to(root):
        parser.error("Destination must remain inside the consuming repository")
    if target.exists():
        parser.error("Refusing to overwrite " + str(target))
    if not source.is_file():
        parser.error("Missing skill asset " + str(source))
if (root / "screenshots/tool-provenance.json").exists():
    parser.error("Refusing to overwrite existing tool provenance")
manifest = []
for source, relative in entries:
    target = root / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(source.read_bytes())
    manifest.append({"source": str(source.relative_to(skill)), "target": relative,
                     "sha256": hashlib.sha256(source.read_bytes()).hexdigest()})
(root / "screenshots/tool-provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
print("Installed tools and adapters. Add the app policy, scenario, configuration and build flag; see integration.md.")
