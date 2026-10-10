#!/usr/bin/env python3
"""Validate the relevant structure of a generated DocC Pages artifact."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-path", type=Path, default=Path("docs"))
    parser.add_argument("--target", required=True, help="SwiftPM target and DocC module name")
    parser.add_argument("--base-path", required=True, help="GitHub Pages hosting prefix, without leading or trailing slashes")
    args = parser.parse_args()

    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.target):
        parser.error("--target must be a Swift target identifier (letters, digits, underscore)")
    if not args.base_path or any(part in {"", ".", ".."} for part in args.base_path.split("/")):
        parser.error("--base-path must contain nonempty path components without dot traversal")

    output = args.output_path
    slug = args.target.lower()
    expected_base_url = f'var baseUrl = "/{args.base_path}/"'
    module_page = output / "documentation" / slug / "index.html"
    checks = [
        (output / ".nojekyll").is_file(), "Pages artifact contains .nojekyll",
        (output / "index.html").is_file(), "artifact root contains index.html",
        module_page.is_file(), f"DocC module page exists: documentation/{slug}/",
        (output / "data" / "documentation" / f"{slug}.json").is_file(),
        f"DocC module JSON exists: data/documentation/{slug}.json",
    ]

    root_contents = (output / "index.html").read_text(encoding="utf-8", errors="replace") if (output / "index.html").is_file() else ""
    module_contents = module_page.read_text(encoding="utf-8", errors="replace") if module_page.is_file() else ""
    module_redirect = f"./documentation/{slug}/"
    checks.extend([
        module_redirect in root_contents, f"root page redirects to {module_redirect}",
        expected_base_url in module_contents,
        f"DocC module page uses expected hosting base URL {expected_base_url}",
    ])

    failed = False
    for index in range(0, len(checks), 2):
        passed, label = checks[index], checks[index + 1]
        print(f"{'PASS' if passed else 'FAIL'}: {label}")
        failed |= not passed

    if failed:
        print("DocC Pages artifact validation failed.", file=sys.stderr)
        return 1
    print("DocC Pages artifact validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
