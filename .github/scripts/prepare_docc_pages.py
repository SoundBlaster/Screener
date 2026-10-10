#!/usr/bin/env python3
"""Prepare a SwiftPM DocC output directory for a GitHub Pages project site."""

from __future__ import annotations

import argparse
import html
import re
from pathlib import Path


def module_slug(target: str) -> str:
    return target.lower()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-path", type=Path, default=Path("docs"))
    parser.add_argument("--target", required=True, help="SwiftPM target and DocC module name")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.target):
        parser.error("--target must be a Swift target identifier (letters, digits, underscore)")

    output = args.output_path
    module_url = f"./documentation/{module_slug(args.target)}/"
    safe_target = html.escape(args.target)
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta http-equiv="refresh" content="0; url={module_url}">
  <link rel="canonical" href="{module_url}">
  <title>{safe_target} Documentation</title>
</head>
<body>
  <p>Redirecting to <a href="{module_url}">{safe_target} Documentation</a>…</p>
  <script>window.location.replace("{module_url}");</script>
</body>
</html>
"""

    output.mkdir(parents=True, exist_ok=True)
    (output / ".nojekyll").touch()
    (output / "index.html").write_text(document, encoding="utf-8")
    print(f"Prepared {output}: .nojekyll and redirect to {module_url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
