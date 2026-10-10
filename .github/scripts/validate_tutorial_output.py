#!/usr/bin/env python3
"""Validate code snapshots and diffs in compiled Swift-DocC tutorial JSON."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Check a generated DocC tutorial JSON page for code snapshots and "
            "step-to-step diff highlights."
        )
    )
    parser.add_argument(
        "--tutorial-json",
        required=True,
        type=Path,
        help="Generated data/tutorials/<module>/<tutorial>.json file.",
    )
    parser.add_argument(
        "--allow-prose-only-section",
        action="append",
        default=[],
        metavar="TITLE",
        help="Section title whose code-free steps are intentional (repeatable).",
    )
    parser.add_argument(
        "--allow-no-diff",
        action="append",
        default=[],
        metavar="FILE",
        help=(
            "Code snapshot reference allowed to have no highlights, such as an "
            "intentional reset (repeatable)."
        ),
    )
    return parser.parse_args()


def tutorial_tasks(document: dict[str, Any]) -> list[dict[str, Any]]:
    tasks: list[dict[str, Any]] = []
    for section in document.get("sections", []):
        if section.get("kind") == "tasks":
            tasks.extend(section.get("tasks", []))
    return tasks


def main() -> int:
    args = parse_args()
    if not args.tutorial_json.is_file():
        print(f"error: tutorial JSON not found: {args.tutorial_json}", file=sys.stderr)
        return 2

    try:
        document = json.loads(args.tutorial_json.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"error: cannot read tutorial JSON: {error}", file=sys.stderr)
        return 2

    tasks = tutorial_tasks(document)
    if not tasks:
        print("error: no tutorial task sections found in generated JSON", file=sys.stderr)
        return 1

    references = document.get("references", {})
    allowed_prose = set(args.allow_prose_only_section)
    allowed_no_diff = set(args.allow_no_diff)
    errors: list[str] = []
    code_steps: list[tuple[str, str, int, int]] = []
    prose_only_steps = 0

    for task in tasks:
        title = task.get("title", "<untitled section>")
        steps = task.get("stepsSection", [])
        if not steps:
            errors.append(f"{title}: section has no steps")
            continue

        for index, step in enumerate(steps, start=1):
            code_ref = step.get("code")
            if not code_ref:
                if title in allowed_prose:
                    prose_only_steps += 1
                    continue
                errors.append(
                    f"{title}, step {index}: no code snapshot; if this is an "
                    "intentional handoff, allow this section explicitly"
                )
                continue

            code_data = references.get(code_ref)
            if not isinstance(code_data, dict):
                errors.append(f"{title}, step {index}: missing code reference {code_ref!r}")
                continue

            content = code_data.get("content")
            if not isinstance(content, list) or not content:
                errors.append(f"{title}, step {index}: code snapshot {code_ref!r} is empty")
                continue

            highlights = code_data.get("highlights") or []
            highlight_count = len(highlights)
            code_steps.append((title, code_ref, len(content), highlight_count))

    if not code_steps:
        errors.append("tutorial contains no code snapshots")

    for index, (title, code_ref, line_count, highlight_count) in enumerate(code_steps):
        if index == 0:
            continue  # The first code snapshot is the comparison baseline.
        if (
            highlight_count == 0
            and code_ref not in allowed_no_diff
            and Path(code_ref).name not in allowed_no_diff
        ):
            errors.append(
                f"{title}: {code_ref!r} has no diff highlights; check its @Code "
                "previousFile or explicitly allow this intentional no-diff snapshot"
            )

    print(f"Tutorial: {document.get('metadata', {}).get('title', args.tutorial_json.stem)}")
    for index, (title, code_ref, line_count, highlight_count) in enumerate(code_steps):
        state = "baseline" if index == 0 else f"{highlight_count} highlighted line(s)"
        print(f"  {title}: {code_ref} ({line_count} lines; {state})")
    if prose_only_steps:
        print(f"  Intentional prose-only handoff step(s): {prose_only_steps}")

    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        print(f"Failed: {len(errors)} issue(s).", file=sys.stderr)
        return 1

    highlighted_steps = sum(highlights > 0 for _, _, _, highlights in code_steps[1:])
    allowed_no_diff_steps = sum(
        highlights == 0
        and (code_ref in allowed_no_diff or Path(code_ref).name in allowed_no_diff)
        for _, code_ref, _, highlights in code_steps[1:]
    )
    print(
        f"Passed: {len(code_steps)} code step(s), {highlighted_steps} highlighted "
        f"transition(s), {allowed_no_diff_steps} allowed no-diff snapshot(s), "
        f"{prose_only_steps} allowed prose-only step(s)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
