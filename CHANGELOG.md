# Changelog

## 0.1.0-alpha.2 — 2026-10-10

- Experimental `ScreenCaptureKitSession` records current-app compositor frames
  into `.vtrace` on physical iOS 27 devices after manual system permission.
- Bounded latest-frame handoff, roughly one keyframe per second plus a final drain,
  explicit/idempotent stop, a 180-second bound, and observable capture failures.
- Frame metadata includes source PTS, pixel format, orientation and available
  geometry; actual PNG dimensions/scale/encoding cannot be overwritten.
- Air validation: ten native 1260×2736 scale-3 frames, menu/glass inspection,
  lifecycle tests and real stdio MCP readback. Fixture reruns clear stale errors.
- Project-local `screener-visual-trace` skill, Codex plugin manifest and repo
  marketplace, including lessons from the PhotoCompressor pilot.
- New trace manifests and MCP initialize responses identify this SDK/reader release
  as `0.1.0-alpha.2`; trace format remains version 1. The plugin version is separate.

UIKit remains the default; Simulator material checks combine UIKit traces with
independent system screenshots. ScreenCaptureKit requires a physical iOS 27 device
SDK and manual recording permission. Rotation, background/interruption, startup
stop races, permission timeout and sustained performance remain unverified.

Swift tools 6.1+, iOS 16+, macOS 13+; the experimental API is iOS 27 device-only.

## 0.1.0-alpha.1 — 2026-10-09

First preview release of Screener's local visual trace SDK and read-only MCP reader.

- `ScreenerCore`: versioned `.vtrace` bundles with manifests, JSONL timelines,
  sparse PNG keyframes, and interrupted-tail recovery.
- `ScreenerKit`: session/marker API and UIKit, AppKit, and SwiftUI capture adapters.
  UIKit window captures use the current trait display scale; transparent AppKit
  captures include the window background.
- `screener-mcp`: session discovery, paginated timelines, frame retrieval, and
  paginated contact sheets, including Codex-compatible initialization.
- Synthetic macOS/iOS fixtures and reproducible material-capture evidence.
- Physical iPhone Air research confirms native 3× ScreenCaptureKit frames and
  substantially closer glass/menu pixels than UIKit hierarchy capture.

This is a prerelease: performance gates and broader runtime coverage are incomplete.
UIKit hierarchy capture does not guarantee compositor fidelity. ScreenCaptureKit
remains an opt-in iOS 27 device fixture experiment, requires manually granted recording
permission, and is not a ScreenerKit production backend. Rotation/interruption paths
and sustained encoding performance remain unverified.

Swift tools 6.1+, iOS 16+, macOS 13+. The MCP executable runs on macOS.
