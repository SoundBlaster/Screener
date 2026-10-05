# ADR-0003 — Hierarchical temporal query model for multimodal agents

Status: Accepted for MVP
Date: 2026-10-05

## Context

An agent can technically request every screenshot in a session, but doing so is expensive in image bandwidth/model context and scales poorly. The agent instead needs a way to navigate time at multiple resolutions.

The original product insight is that thumbnails are not merely a storage optimization. A contact sheet is an agent-facing temporal index: a multimodal model can scan many UI states in one image and decide which interval deserves closer inspection.

## Decision

Expose a small MCP query hierarchy:

```text
sessions
  → timeline
  → contact_sheet
  → frame
  → inspect / diff
```

The MCP API should encourage progressive refinement rather than bulk full-resolution retrieval.

## Tool responsibilities

### `sessions`

Select the relevant run.

### `timeline`

Return cheap structured records: timestamps, markers, frame IDs, reasons and visual-change scores.

### `contact_sheet`

Generate one image containing chronologically ordered thumbnails and a structured map from cell labels to frame IDs/timestamps.

This is the primary visual-search primitive.

### `frame`

Return exactly one chosen state at thumbnail/full/best-available resolution.

### `inspect`

Return semantic information associated with the chosen frame, including nearby markers and accessibility data when recorded.

### `diff`

Compare two selected observations rather than asking the model to infer all changes from two unrelated images.

## Rationale

### Multimodal temporal search

A contact sheet lets the vision model perform a visual coarse search across time without dozens of independent image calls.

### Context efficiency

Most investigation can happen with structured metadata and compressed thumbnails. Full-resolution images are fetched only after the interesting moment is localized.

### Model independence

The server does not need a vision model. It renders a deterministic visual index; the connected agent decides which cells matter.

### Recursive zoom

The same `contact_sheet` operation can be called on 30 seconds, then 5 seconds, then 1 second. This creates a map-like zoom model for time.

## Consequences

Positive:

- Lower image/token usage.
- Natural interaction for multimodal agents.
- Small MCP surface.
- Works even without OCR or sophisticated semantic search.
- Easy to combine with markers when semantics are available.

Negative:

- Contact-sheet generation becomes core infrastructure, not optional UI polish.
- Cell labeling/mapping must be deterministic and machine-readable.
- Very rapid transitions may still require denser recording around bursts.

## Constraints

- Contact sheets preserve chronological ordering.
- Cell label → frame ID mapping is returned as structured data, not inferred from pixels alone.
- The server may sample a long interval, but must report the sampling strategy.
- Full-resolution bulk export is not part of the initial MCP surface.
- MCP operations are read-only.

## Example agent sequence

```text
screener.sessions(bundleID: "com.example.App")

screener.timeline(
    session: "S1",
    last: 30s
)

screener.contact_sheet(
    session: "S1",
    range: 12.0s ... 18.0s,
    maxCells: 24
)

// model identifies cells C11-C15

screener.contact_sheet(
    session: "S1",
    range: 14.2s ... 15.1s,
    maxCells: 18
)

screener.frame(session: "S1", frame: "f-184", resolution: "full")
screener.inspect(session: "S1", frame: "f-184")
screener.diff(session: "S1", from: "f-183", to: "f-184")
```

## Future extension

Structured search can later be added on top of this model:

- marker name search;
- OCR search;
- accessibility label search;
- route/state metadata search;
- perceptual-similarity search.

These should narrow candidate time ranges; they do not replace visual temporal navigation.
