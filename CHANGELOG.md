# Changelog

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
