# PRD — Screener v0.1

Status: Draft for implementation
Working name: Screener
Primary platforms: iOS, macOS
Primary implementation language: Swift 6

## 1. Summary

Screener is a native development-time visual flight recorder for iOS and macOS applications. The application records a timestamped local trace of its own UI and related semantic events. A coding agent running on the developer's Mac can later query that history through MCP, visually scan thumbnails, zoom into a smaller time range, request a full-resolution frame, inspect metadata, and compare frames.

The core problem is temporal: a coding agent usually observes only the current UI state. Many bugs, transitions and layout glitches are transient. By the time the agent asks for a screenshot, the interesting state is gone. Screener separates the moment an event occurs from the moment the agent inspects it.

## 2. Problem

Typical agent-assisted UI debugging has one or more of these failures:

1. The agent asks for a screenshot after the relevant state has disappeared.
2. The human must manually reproduce a bug and stop at the right moment.
3. Continuous video is expensive to store, transmit and inspect.
4. A screenshot has no strong relationship to app events, navigation, markers or UI semantics.
5. System-level screen recorders see pixels but know little about the application that produced them.
6. Existing session replay products are generally analytics-oriented, web-oriented, cloud-oriented, or designed for human playback rather than agent-driven temporal search.

## 3. Product goal

Give a coding agent a rewindable, queryable visual memory of an iOS/macOS application with minimal integration and minimal runtime overhead.

The desired interaction is:

    User: “The Send button jumped after the avatar loaded. Find out when.”

    Agent:
        1. requests recent timeline
        2. sees `AvatarLoaded` marker and visual-change records
        3. requests a contact sheet around that timestamp
        4. zooms into the relevant interval
        5. requests two full-resolution frames
        6. inspects UI metadata / accessibility snapshots
        7. diffs the frames and correlates them with source/runtime context

The user should not need to reproduce the state again merely so the agent can see it.

## 4. Product principles

### 4.1 App-centric, not desktop-centric

The embedded SDK understands the host app, scene, build, semantic markers and UI tree. Screener is not primarily a recorder of the entire desktop.

### 4.2 Native first

Use Apple frameworks and Swift. Avoid mandatory Chromium, ffmpeg, OpenCV, Python, browser instrumentation or a cloud backend.

### 4.3 Query history instead of streaming observation

The primary abstraction is a timestamped trace, not a live video feed.

### 4.4 Progressive disclosure

The agent should consume the cheapest representation that answers the current question:

    session summary
        → timeline records
        → contact sheet / thumbnails
        → exact frame
        → semantic inspection / diff

### 4.5 Local and explicit

The default implementation stores traces locally in development builds. Nothing is uploaded by default.

### 4.6 Sparse high fidelity

Store many cheap thumbnails and relatively few full-resolution keyframes. Full-resolution capture is triggered by semantic importance or significant visual change, not by a fixed video frame rate.

## 5. Users

Primary user:

- iOS/macOS developer using a coding agent such as Claude Code, Codex or another MCP-capable agent.

Secondary user:

- developer or QA engineer inspecting the same trace manually through a future native macOS viewer.

## 6. Scope

### 6.1 MVP in scope

- Swift Package `ScreenerKit` embedded in an iOS or macOS app.
- Explicit start/stop session lifecycle.
- Window/view capture for UIKit and AppKit.
- Support for SwiftUI applications through host window capture; optional explicit SwiftUI component rendering may use `ImageRenderer`.
- Low-resolution thumbnails.
- Sparse full-resolution keyframes.
- Timestamped manual semantic markers.
- Basic app/scene/window metadata.
- Optional accessibility snapshot at selected keyframes.
- Append-only `.vtrace` bundle stored locally.
- Configurable retention cap.
- macOS executable `screener-mcp`.
- Simulator-first trace discovery.
- MCP tools: sessions, timeline, contact_sheet, frame, inspect, diff.
- Contact-sheet rendering on the Mac from recorded thumbnails.
- Crash-tolerant reading of traces while the application is still writing them.

### 6.2 Post-MVP / extension points

- Physical iPhone/iPad transport over a local developer bridge.
- Automatic interaction-event capture.
- Route/navigation adapters for common app architectures.
- Vision OCR and local semantic indexing.
- Region-based visual diffs.
- Native macOS trace viewer.
- ScreenCaptureKit capture backend for compositor-level content.
- Cross-process / extension trace stitching.
- Agent-generated bookmarks and annotations.

### 6.3 Explicitly out of scope for MVP

- Production analytics/session replay service.
- Cloud storage or a hosted account system.
- Live remote control of the app.
- Full deterministic runtime replay.
- Arbitrary code execution from MCP.
- Recording microphone/camera/audio.
- High-FPS video capture.
- Guaranteed capture of protected content or every Metal/video surface through the embedded view-rendering backend.

## 7. Package topology

### 7.1 `ScreenerKit`

Swift Package linked into the target application.

Responsibilities:

- session lifecycle;
- capture scheduling;
- platform capture adapters;
- image downsampling/encoding;
- visual-change scoring;
- settled-frame detection;
- marker API;
- metadata/accessibility snapshots;
- trace bundle writing;
- retention.

### 7.2 `.vtrace` bundle

A local directory-based trace format with append-only timeline records and separate image blobs.

### 7.3 `screener-mcp`

macOS executable.

Responsibilities:

- discover local Simulator traces;
- open/read active and completed traces;
- index timeline records;
- render contact sheets;
- return images and metadata through MCP;
- compute on-demand frame diffs;
- never modify the source application state.

## 8. Public SDK API — conceptual

The exact Swift API may evolve, but the MVP capability surface should stay small.

```swift
Screener.configure(.developmentDefault)
Screener.startSession(name: "manual-debug")
Screener.mark("Profile.opened")
Screener.mark("Avatar.loaded", metadata: ["userID": userID])
Screener.capture(reason: "before-layout-change")
Screener.stopSession()
```

Configuration must include:

- enabled / disabled;
- thumbnail dimensions;
- full-frame encoding/quality;
- capture cadence / adaptive policy;
- visual-change threshold;
- retention bytes / age;
- accessibility capture policy;
- privacy/redaction policy;
- optional metadata provider callback.

The API must be safe to leave compiled into a development build while disabled.

## 9. Capture model

### 9.1 Primary capture backend

For UIKit, render the visible window/view hierarchy through native UIKit snapshot rendering. For AppKit, render the target view/window hierarchy through AppKit bitmap display caching. SwiftUI full-app capture should normally happen through the host UIKit/AppKit window rather than trying to reconstruct the root SwiftUI view separately.

### 9.2 Why not continuous video

The agent normally needs a small number of semantically meaningful visual states. Video introduces unnecessary bitrate, decoding and temporal search cost. Screener instead records discrete visual observations with timestamps.

### 9.3 Capture levels

`thumbnail`

- low spatial resolution;
- cheap enough to retain frequently;
- input to visual-change scoring;
- used by contact sheets.

`keyframe`

- full or near-full app/window resolution;
- captured less frequently;
- retained around markers, significant changes and stable end states.

`semantic-only`

- event/marker without image when an image is unnecessary or throttled.

### 9.4 Initial adaptive policy

The initial defaults are implementation targets, not protocol constants.

- Heartbeat sample while active: low frequency (for example 1–2 samples/s).
- Burst sample after a marker/significant visual change: higher frequency for a short bounded window (for example up to 4–5 samples/s for ~1–2 s).
- Store a thumbnail only if the candidate differs materially from the last stored thumbnail, or if a semantic reason forces retention.
- Store full resolution when:
  - the developer explicitly requests capture;
  - a marker is configured as a keyframe marker;
  - visual delta crosses a high threshold;
  - a burst settles into a stable frame;
  - periodic keyframe fallback requires one.

No capture loop should attempt display-refresh-rate screenshots.

### 9.5 Settled-frame detection

A transition often matters most at its stable end state. During a bounded burst, compare successive thumbnails. If the delta remains below a configured threshold for a configured number of samples, emit a keyframe record with reason `settled`.

Settled detection is heuristic and must not block UI work.

## 10. Threading and performance

- UI hierarchy capture that requires UIKit/AppKit access occurs on the main actor.
- Scaling, encoding, hashing, visual comparison, bundle I/O and contact-sheet rendering occur off the main actor whenever possible.
- The capture scheduler must coalesce requests and apply backpressure rather than queue unbounded screenshots.
- There is at most one expensive capture pipeline per scene/window at a time.
- If the encoder/storage queue is saturated, the system may drop non-forced visual samples but must preserve semantic markers.

Initial performance targets on a representative sample app:

- no persistent display-link-rate screenshot loop;
- no unbounded main-thread queue growth;
- p95 main-thread snapshot work should be measured and kept below a budget established by benchmarks; initial target is ≤12 ms for the representative test window, with graceful degradation if it cannot be met;
- image compression/storage must not execute synchronously on the main actor;
- retention must keep disk usage bounded.

Performance targets are gates for release, not assumptions about every application.

## 11. Trace bundle format

Proposed bundle:

```text
2026-10-05T20-45-12Z-<uuid>.vtrace/
    manifest.json
    timeline.jsonl
    thumbs/
        00000001.heic
        00000002.heic
    frames/
        00000001.heic
        00000017.heic
    semantic/
        00000017.json
```

### 11.1 `manifest.json`

Contains session-level immutable or slowly changing metadata:

- format version;
- session ID;
- app bundle ID;
- app version/build;
- platform and OS version;
- device/simulator model identifier;
- session start/end timestamps;
- image encoding parameters;
- privacy configuration summary;
- optional source-control metadata supplied by host app/build integration.

### 11.2 `timeline.jsonl`

Append-only line-delimited records. Each complete line is independently decodable.

Record kinds:

- `frame`
- `marker`
- `lifecycle`
- `warning`
- `session`

Example conceptual frame record:

```json
{
  "kind": "frame",
  "id": "f-184",
  "timestampNs": 18420301000,
  "wallTime": "2026-10-05T20:45:18.420+03:00",
  "reason": "settled",
  "thumbnail": "thumbs/00000184.heic",
  "frame": "frames/00000184.heic",
  "visualDelta": 0.031,
  "scene": "main",
  "window": {"width": 1179, "height": 2556, "scale": 3},
  "semantic": "semantic/00000184.json"
}
```

### 11.3 Write ordering

For crash safety and concurrent readers:

1. write an image/semantic blob to a temporary file;
2. close/fsync as appropriate;
3. atomically rename into its final bundle path;
4. append the timeline record only after all referenced blobs exist;
5. flush timeline records in bounded batches.

The MCP reader ignores a trailing incomplete JSONL line.

## 12. Semantic markers

Markers are first-class and must survive even if visual frames are dropped.

Each marker has:

- stable record ID;
- monotonic timestamp;
- wall-clock timestamp;
- name;
- optional scalar metadata;
- optional scene/window identity;
- optional keyframe request.

Examples:

- `Navigation.Profile.presented`
- `Avatar.loaded`
- `Video.playbackStarted`
- `Sheet.detentChanged`
- `Network.profile.completed`

Screener must not impose one navigation or state-management architecture on the host app.

## 13. Accessibility / semantic snapshot

At configured keyframes, Screener may capture a sanitized representation of accessible UI elements:

- role/type;
- label;
- value where allowed;
- frame in window coordinates;
- enabled/selected/focused traits;
- hierarchy or parent relation where feasible.

This representation is intended for agent reasoning and frame-to-element correlation, not as a replacement for XCTest accessibility APIs.

Sensitive labels/values must pass through the configured privacy policy before persistence.

## 14. Privacy and security

Visual traces can contain credentials, messages, photos, customer data and other sensitive information. Privacy is an architectural requirement.

MVP requirements:

- tracing disabled by default outside explicitly enabled development configuration;
- local-only storage by default;
- configurable maximum disk usage and age;
- easy purge API;
- host-provided redaction hooks for views/rectangles/semantic values;
- ability to exclude specific windows/scenes/views from capture;
- no automatic upload;
- MCP exposes only local trace data and read-only inspection tools;
- no MCP tool may trigger arbitrary host-app code or mutate application state;
- logs must not duplicate unredacted semantic payloads.

A future production mode, if ever added, requires a separate threat/privacy review.

## 15. Simulator discovery

MVP development path:

1. SDK stores traces under the app data container, preferably `Library/Caches/Screener/`.
2. `screener-mcp` is configured with bundle ID and optional simulator identifier.
3. The helper uses Apple developer tooling (`xcrun simctl`) to resolve the running/booted Simulator app data container.
4. The helper enumerates `.vtrace` bundles and can read the active one while it grows.

No undocumented CoreSimulator framework dependency is required for MVP.

## 16. Physical-device bridge

Not required for MVP, but architecture must keep storage discovery behind a `TraceSource` boundary.

Candidate native implementation:

- opt-in local developer bridge in `ScreenerKit`;
- Network.framework transport;
- local-network permission and explicit enablement;
- read-only trace export/streaming;
- pairing/authentication before exposing trace contents.

The exact protocol is a separate ADR after Simulator MVP is validated.

## 17. Optional ScreenCaptureKit backend

ScreenCaptureKit is not the primary MVP backend because it introduces user-mediated screen-capture permission/content selection and is broader than needed when the application can render its own UI.

It remains valuable for:

- compositor-level visual fidelity;
- AV/video/Metal surfaces not represented faithfully by view-hierarchy rendering;
- external macOS utility mode that records another application.

The capture backend abstraction must allow this without changing the trace model or MCP surface.

## 18. MCP server

`screener-mcp` is a separate macOS Swift executable using the official MCP Swift SDK.

### 18.1 Design rule

MCP is an inspection boundary, not the source of truth. The `.vtrace` bundle is the source artifact.

### 18.2 Tools

#### `screener.sessions`

Purpose: discover available sessions.

Input:

- optional bundle ID;
- optional time range;
- optional status (`active`, `completed`).

Output:

- session ID;
- app/build;
- start/end;
- duration;
- frame/marker counts;
- trace size;
- active/completed state.

#### `screener.timeline`

Purpose: cheaply inspect a time range before requesting images.

Input:

- session ID;
- time range;
- optional kinds;
- maximum records.

Output:

- compact timestamped records;
- markers;
- frame IDs;
- visual delta;
- reasons;
- warnings/lifecycle.

#### `screener.contact_sheet`

Purpose: let a multimodal agent visually scan time.

Input:

- session ID;
- time range or frame IDs;
- maximum cells;
- optional sampling strategy.

Output:

- one generated image;
- deterministic mapping from cell label to frame ID/timestamp.

#### `screener.frame`

Purpose: retrieve one exact visual state.

Input:

- session ID;
- frame ID or timestamp;
- resolution preference (`thumbnail`, `full`, `bestAvailable`).

Output:

- image;
- frame metadata;
- exact resolved timestamp/frame ID.

#### `screener.inspect`

Purpose: retrieve structured information associated with a frame.

Input:

- session ID;
- frame ID.

Output:

- frame metadata;
- nearby markers;
- app/scene/window metadata;
- accessibility snapshot if present;
- privacy/redaction indicators.

#### `screener.diff`

Purpose: compare two recorded visual states.

Input:

- session ID;
- frame A;
- frame B;
- optional region.

Output:

- numeric change metrics;
- optional generated diff image;
- dimension/scale changes;
- semantic/accessibility changes if available.

### 18.3 Agent navigation pattern

The intended default is:

    sessions
      → timeline
      → contact_sheet
      → narrower contact_sheet (optional)
      → frame
      → inspect / diff

An agent should not fetch all full-resolution frames for a long session.

## 19. Contact-sheet requirements

A contact sheet must:

- be generated on demand from thumbnails;
- fit within a configurable image size;
- overlay a short stable cell label, not large verbose text;
- return cell-label → frame-ID/timestamp mapping as structured metadata;
- optionally use uniform time sampling or significant-frame sampling;
- preserve chronological order;
- never rewrite source trace files.

This is a core feature, not a convenience UI. It is the primary visual index for multimodal agents.

## 20. Diff requirements

MVP diff may be intentionally simple:

- normalize dimensions;
- compute basic pixel/luma difference metrics;
- optionally generate an absolute-difference visualization;
- report changed-region bounding box if robust enough;
- avoid ML dependency.

Later versions may add perceptual hashing, Vision features or semantic element diffing.

## 21. Retention

Default development configuration should bound storage automatically.

Initial proposed defaults (tunable, not protocol constants):

- maximum total trace storage: 256 MiB per app;
- active session soft age: 60 minutes;
- delete oldest completed sessions first;
- never delete a session currently being exported/read if the implementation can cheaply detect the lease;
- allow developer override.

If a budget is hit during an active session, preserve markers and drop/degrade lower-priority visual frames before allowing unbounded growth.

## 22. Error strategy

Recording errors must not crash the host application.

Categories:

- capture unavailable/incomplete;
- encoder failure;
- disk full;
- retention failure;
- malformed partial timeline;
- unsupported semantic snapshot;
- trace version mismatch.

SDK behavior:

- emit local warning records where possible;
- throttle repeated errors;
- disable a failing optional subsystem rather than the app;
- expose diagnostic state to the host developer.

MCP behavior:

- return explicit partial/unavailable status;
- never invent missing frames;
- tolerate active traces and trailing incomplete records;
- reject unsupported newer major trace versions clearly.

## 23. Versioning

`.vtrace` has an explicit format version in `manifest.json`.

Rules:

- backward-compatible additive changes stay within a major version;
- breaking changes require a new major version;
- MCP reader should support at least the current and previous major version once v2 exists;
- record kinds are extensible; unknown optional kinds (marked with `"optional": true` on the JSONL record) can be skipped with diagnostics.

## 24. Testing strategy

### Unit tests

- timeline record encoding/decoding;
- atomic blob publication;
- retention ordering;
- visual delta calculation;
- settled detector;
- contact-sheet cell mapping;
- MCP request validation;
- privacy filters.

### Integration fixtures

Create a small iOS/macOS fixture application with deterministic screens:

- static screen;
- animated sheet;
- delayed image load causing a layout change;
- navigation transition;
- sensitive/redacted field;
- SwiftUI hosted inside UIKit and vice versa where practical.

### Golden traces

Check a small committed synthetic `.vtrace` fixture into tests for MCP behavior without requiring the Simulator.

### Performance tests

Measure:

- main-thread snapshot duration;
- memory peak during capture;
- encoder queue depth;
- disk bytes per minute for static and active UI;
- contact-sheet generation latency;
- timeline query time on a long trace.

## 25. MVP milestones

### M0 — Trace core

- package skeleton;
- session lifecycle;
- format version;
- JSONL writer;
- blob store;
- crash-safe append;
- retention foundation.

### M1 — Native capture

- UIKit capture adapter;
- AppKit capture adapter;
- SwiftUI `ImageRenderer` adapter for explicit view subtrees;
- explicit capture API;
- thumbnails and keyframes;
- fixture app.

Implementation note (2026-10-06): the three capture adapters, explicit keyframe API, and macOS fixture are implemented. A local release benchmark now measures long-trace timeline paging and contact-sheet generation; adaptive thumbnails, redaction, and the production fixture/benchmark matrix remain open.

### M2 — Adaptive recording

- heartbeat sampling;
- visual delta;
- burst mode;
- settled detection;
- marker API;
- bounded backpressure.

### M3 — Agent access

- Simulator discovery;
- MCP server;
- sessions;
- timeline;
- frame;
- contact sheet.

### M4 — Inspection

- accessibility snapshot;
- inspect;
- diff;
- privacy/redaction hooks;
- performance/retention hardening.

### M5 — Device bridge

- separate ADR;
- authenticated local transport;
- physical-device trace discovery/read.

## 26. MVP acceptance criteria

A developer can:

1. add `ScreenerKit` to an iOS Simulator app;
2. start a trace session with one line of app-level setup;
3. use the app normally for at least five minutes;
4. observe that unchanged periods do not produce display-rate screenshots;
5. emit a named marker from app code;
6. open an MCP-capable coding agent on the Mac;
7. list recent sessions without manually locating the app container;
8. request the last 30 seconds of timeline records;
9. request a contact sheet for that range;
10. select one frame and retrieve it at best available resolution;
11. inspect its timestamp, reason, nearby marker and window metadata;
12. compare two frames;
13. continue reading the session while the app is still recording;
14. keep trace disk usage within the configured cap;
15. disable tracing without changing application behavior.

The fixture scenario “delayed image load causes a button to move” must be diagnosable from a previously recorded trace without reproducing the transition.

## 27. Risks

### View-hierarchy snapshots are not compositor-perfect

Some AV/Metal/protected surfaces may be missing or stale. Mitigation: capture-backend abstraction and optional ScreenCaptureKit backend later.

### Main-thread capture cost

Snapshot APIs can be expensive. Mitigation: low cadence, burst bounds, coalescing, backpressure, aggressive thumbnails and benchmarking.

### Sensitive data leakage

A visual trace is inherently sensitive. Mitigation: debug-first, local-only, redaction/exclusion, bounded retention, explicit physical-device bridge.

### Agent token/image cost

Too many frames defeat the product goal. Mitigation: timeline and contact-sheet hierarchy; full frames are on-demand.

### Over-instrumentation

Deep app hooks can make the SDK fragile. Mitigation: manual markers plus optional adapters; avoid mandatory swizzling or dependence on a particular navigation architecture.

## 28. Open design questions after MVP validation

- Should the trace store keep HEIC exclusively or negotiate PNG for deterministic test fixtures?
- Is one timeline per process sufficient, or should multi-scene/multi-process traces share a session graph?
- How should physical-device pairing/authentication work?
- Which UI metadata is useful enough to justify automatic capture cost?
- Should source control/build metadata be supplied by generated build settings or a host callback?
- What is the right public abstraction for privacy redaction: view identity, rectangle, semantic key, or a combination?
- Which video/Metal workloads justify ScreenCaptureKit integration on iOS 27+?

## 29. Verified platform anchors

- UIKit `UIView.drawHierarchy(in:afterScreenUpdates:)` renders a snapshot of the complete visible view hierarchy into the current graphics context.
- AppKit `NSView.cacheDisplay(in:to:)` draws a view and its descendants into a bitmap representation.
- SwiftUI `ImageRenderer` can render a SwiftUI view to `CGImage`, `NSImage` or `UIImage`.
- ScreenCaptureKit supports screen capture across current Apple platforms and requires user screen-recording permission/content selection; it is an optional backend, not an MVP dependency.
- The official MCP Swift SDK provides MCP client/server components and supports Swift 6.
