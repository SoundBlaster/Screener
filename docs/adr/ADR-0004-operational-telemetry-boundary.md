# ADR-0004 — Keep operational telemetry separate from visual traces

Status: Accepted for initial implementation
Date: 2026-10-05

## Context

ScreenKit and its examples demonstrate a useful boundary: a core library emits typed events through a small sink, while an optional adapter owns OpenTelemetry providers and exporters. The host application controls exporter configuration. This keeps the core usable without a telemetry backend and avoids doing network or flush work in UI callbacks.

Screener has a different primary data product: a local, inspectable visual trace containing frames and semantic events. Exported telemetry is useful for diagnosing recorder health, but it cannot replace or prove the existence of a `.vtrace` artifact.

## Decision

- `ScreenerCore` and `ScreenerKit` do not depend on OpenTelemetry.
- If operational instrumentation is added, it uses a separate optional adapter and a bounded typed event contract.
- Initial health signals may include capture duration, write duration, dropped capture count, and writer errors. They must not contain screenshots, view text, file paths, or unbounded identifiers.
- Record wall-clock timestamps for cross-system correlation and monotonic durations for elapsed-time measurements.
- Sink callbacks must not perform network I/O or exporter shutdown on the UI thread; batching and export lifecycle belong to the app-owned adapter.
- Successful local enqueue or exporter shutdown is not described as server ingestion. Ingestion checks are a separate integration test.
- Trace writing remains local-first and functional when telemetry is disabled or unavailable.

## Consequences

Screener can adopt the ScreenKit integration pattern without coupling trace compatibility to OpenTelemetry. The cost is maintaining two explicit observability surfaces: visual history in `.vtrace`, and optional operational health telemetry.
