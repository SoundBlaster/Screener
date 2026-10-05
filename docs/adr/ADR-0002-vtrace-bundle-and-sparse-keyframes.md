# ADR-0002 — Directory-based `.vtrace` bundle with append-only timeline and sparse keyframes

Status: Accepted for MVP
Date: 2026-10-05

## Context

Screener needs to record a session while it is happening and allow another local process to inspect that session concurrently. The format must tolerate application termination, bound storage, support progressive agent queries and avoid continuous-video overhead.

Candidate storage designs:

- video container plus sidecar metadata;
- SQLite database with image blobs;
- custom binary log;
- directory bundle with append-only textual timeline and separate image blobs.

## Decision

Use a directory-based `.vtrace` bundle:

```text
<session>.vtrace/
    manifest.json
    timeline.jsonl
    thumbs/
    frames/
    semantic/
```

The timeline is append-only JSON Lines. Binary/large payloads are separate files referenced by records.

Visual history is sparse:

- frequent/meaningful low-resolution thumbnails;
- fewer full-resolution keyframes;
- semantic-only records when no image is required.

A timeline record referencing a blob is appended only after the blob is fully written and atomically published at its final path.

## Rationale

### Concurrent local reading

A reader can tail complete JSONL records without opening an application-owned database connection or negotiating a live protocol.

### Crash tolerance

A crash can leave a temporary blob or an incomplete trailing JSONL line; both are easy to detect and ignore. Previously committed records remain usable.

### Human inspectability

Developers can inspect manifest/timeline data with ordinary tools during early development.

### Progressive access

The agent can query textual records without loading images, then read thumbnails, then selected keyframes.

### Cheap retention

Completed session directories can be deleted oldest-first. Lower-priority thumbnails/frames can also be pruned under explicit rules if future versions support partial retention.

### Format independence

The trace artifact is not coupled to MCP. A future native viewer can consume the same data.

## Consequences

Positive:

- Very simple first implementation.
- Good debugging ergonomics.
- Streaming/tailing behavior is natural.
- No database migration machinery for v0.1.
- Easy fixture/golden-trace creation.

Negative:

- Directory may contain many files.
- Global queries across many sessions require a reader-side index/cache.
- Atomicity spans multiple files and must follow strict write ordering.
- JSONL is not as compact as a custom binary format.

## Why not video

Video optimizes playback, not semantic random access. The product's expected access pattern is sparse and hierarchical: inspect a timeline, scan a contact sheet, then retrieve one or two frames. Sparse images map directly to that access pattern.

## Why not SQLite for MVP

SQLite would be viable, but it adds cross-process lifecycle, schema migration and blob strategy choices before the trace semantics are proven. If scale later makes JSONL/indexing inadequate, a reader-side SQLite cache or a v2 store can be introduced without changing the high-level model.

## Record invariants

- Every record has a unique ID within the session.
- Every record has a monotonic timestamp.
- Wall-clock time is supplementary; ordering uses monotonic time.
- A timeline record never points to a blob that has not been atomically published.
- Unknown optional record kinds are skippable.
- Semantic markers are never dropped solely because the image pipeline is under backpressure.
- A trailing malformed/incomplete line in an active trace is ignored until completed or abandoned.

## Encoding defaults

- HEIC is preferred for development trace imagery where available because space efficiency matters.
- PNG may be used for deterministic test fixtures/golden files.
- Encoding choice belongs in the manifest and is not hardcoded into MCP behavior.

## Retention

Initial default budget: 256 MiB per app, configurable.

When pressure occurs:

1. delete oldest completed sessions;
2. if necessary, drop future non-forced visual samples in the active session;
3. preserve semantic markers and diagnostics;
4. never allow unbounded growth.
