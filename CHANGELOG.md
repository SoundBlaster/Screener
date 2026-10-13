# Changelog

## 0.2.0 — 2026-10-13

- New `screener-app-store-screenshots` skill: repeatable iOS/iPadOS Simulator
  batches with real XCTest navigation, flag-gated app checkpoints, paired native
  Screener/system PNGs, pixel-preserving preparation and a review gallery.
- Experimental macOS whole-window screenshot adapter, validated with BuildHunter;
  explicit window queries, app-owned readiness, scoped runner entitlements,
  local ad hoc signing and documented developer/UI Automation setup.
- Public custom-frame ingestion for images, encoded data, pixel buffers and raw
  RGBA8/BGRA8 buffers, with explicit conversion, ownership and source timestamps.
- Optional `ScreenerScreenCaptureKit` product supplies macOS 14+ async window
  stills with explicit window/owner checks, native geometry validation and
  existing Screen Recording access. It does not start a continuous stream.
- UIKit image capture handles draw-only `UIImage` values without CG/CI backing.
- iOS/macOS DocC API reference, tutorial and custom-frame examples; updated
  capture guidance and source-bound PhotoCompressor, CityChain, BuildHunter and
  Dreams evidence.
- README screenshot-skill hero and clearer first-integration/repeat/recovery
  workflows. Prose/image-only changes skip heavy CI; screenshot-tool checks
  run on Linux and Swift/DocC checks follow their actual inputs.
- Trace producer, MCP server and skills-only plugin identify version `0.2.0`.
  Trace format remains version 1; existing 0.1.0 traces remain readable.

Screenshot automation requires consuming app/test integration and content review;
it does not upload to Apple or establish App Store acceptance. macOS screenshot
automation remains experimental. Hierarchy capture can omit GPU content and
render materials differently; the settled SDR Dreams Metal comparison does not
establish RealityKit, HDR/EDR or universal GPU fidelity. The opt-in physical iOS 27
ScreenCaptureKit session still requires manual system permission.

Swift tools 6.1+, iOS 16+, macOS 13+; the optional macOS compositor module needs
macOS 14+. The MCP executable runs on macOS.

## 0.1.0 — 2026-10-10

First stable release of the local visual trace SDK and read-only MCP server.

- UIKit, AppKit and SwiftUI capture adapters, semantic markers, version-1 `.vtrace`
  bundles, and local PNG keyframes.
- MCP session discovery, paginated timelines, contact sheets and individual frames.
- Public README with an end-to-end Simulator quick start, geometric cover, and
  BuildHunter usage example; detailed capture and plugin guidance in a separate guide.
- Repeatable release benchmarks with per-query warm-up, 100 measured samples by
  default, empirical p95 for larger samples, and median/max for short runs.
- SDK trace manifests and MCP initialize responses now identify version `0.1.0`.
  Trace format remains version 1; the skills-only plugin is also version `0.1.0`.

The opt-in iOS 27 ScreenCaptureKit backend remains experimental. UIKit/AppKit
rendering does not guarantee compositor fidelity, and sampled keyframes do not
cover every animation frame. Recording stays app-side; the MCP server reads traces.

Swift tools 6.1+, iOS 16+, macOS 13+. The MCP executable runs on macOS.

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
