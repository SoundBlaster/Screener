#!/usr/bin/env python3
"""Select checks from the complete Git diff; uncertain inputs run every check."""
import json
import os
from pathlib import Path, PurePosixPath
import subprocess


def select_checks(paths):
    checks = {"swift": False, "tools": False, "documentation": False}
    prose = {".md", ".rst", ".adoc"}
    images = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".ico"}
    evidence = prose | images | {".json", ".jsonl", ".txt", ".hc", ".hcs", ".patch"}
    for path in paths:
        item = PurePosixPath(path)
        if any(part.endswith(".docc") for part in item.parts):
            checks["documentation"] = True
        elif path.startswith(("Sources/", "Tests/", "Examples/")) or path in {"Package.swift", "Package.resolved"}:
            checks["swift"] = checks["documentation"] = True
        elif path.startswith(".github/"):
            # Changes to workflows or the selector must exercise the full pipeline.
            checks = dict.fromkeys(checks, True)
        elif path.startswith(".agents/skills/"):
            if item.suffix.lower() in prose | images or path.endswith("/agents/openai.yaml"):
                continue
            checks["tools"] = True
        elif path.startswith("docs/") and item.suffix.lower() in evidence:
            continue
        elif item.suffix.lower() in prose | images or path in {"LICENSE", ".gitignore"}:
            continue
        elif path.startswith((".codex-plugin/", ".agents/plugins/")) and item.suffix == ".json":
            continue
        else:
            # New inputs/configuration are checked until deliberately classified.
            checks = dict.fromkeys(checks, True)
    return checks


def changed_paths(event_name, event):
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
        head = event["pull_request"]["head"]["sha"]
        revisions = [base + "..." + head]
    elif event_name == "push":
        base, head = event["before"], event["after"]
        if not base.strip("0") or not head.strip("0"):
            raise ValueError("No previous commit for this push")
        revisions = [base, head]
    else:
        raise ValueError("Manual or unsupported event requires every check")
    # Full history and --no-renames include both sides of moves/deletions, without
    # GitHub's path-filter file-count limit. NUL separation preserves path names.
    output = subprocess.check_output(
        ["git", "diff", "--name-only", "--no-renames", "-z", *revisions, "--"]
    )
    return [os.fsdecode(path) for path in output.split(b"\0") if path]


def main():
    try:
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        checks = select_checks(changed_paths(os.environ["GITHUB_EVENT_NAME"], event))
    except (KeyError, ValueError, OSError, subprocess.CalledProcessError):
        print("Change selection unavailable or forced; running every check.")
        checks = {"swift": True, "tools": True, "documentation": True}
    print(json.dumps(checks, sort_keys=True))
    with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
        for key, value in checks.items():
            output.write(f"{key}={str(value).lower()}\n")


if __name__ == "__main__":
    main()
