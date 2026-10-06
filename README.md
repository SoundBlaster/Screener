# Screener

Screener is a local-first visual flight recorder for debugging transient UI states in iOS and macOS apps. It is designed to let a developer or coding agent inspect a recorded timeline after the interesting state has passed.

The repository contains the versioned `.vtrace` bundle core, an app-side session/marker API, UIKit, AppKit, and SwiftUI capture adapters, and a separate read-only MCP server. The macOS fixture app exercises state changes, markers, and real window keyframes.

```swift
import ScreenerKit

let screener = Screener()
let traceURL = try await screener.startSession(
    name: "checkout-flow",
    appBundleID: "com.example.app",
    tracesDirectory: tracesDirectory
)
try await screener.mark("Checkout.submitted", metadata: ["payment": "card"])
let capture = ScreenerCaptureSession(screener: screener)
try await capture.capture(
    from: AppKitCaptureSource(view: window.contentView!),
    reason: "checkout-submitted"
)
try await screener.stopSession()
```

UIKit apps can pass a `UIView` to `UIKitCaptureSource`. SwiftUI callers can pass a view to `SwiftUICaptureSource`; that adapter renders the explicit subtree, while a hosted root view can be captured through its UIKit/AppKit host window. UI rendering happens on the main actor; PNG encoding and bundle writes happen after the rendered `CGImage` crosses to the recorder actor. The resulting `.vtrace` directory contains a JSON manifest, append-only JSONL timeline, and PNG keyframes. Reads tolerate an incomplete trailing line from an interrupted append while rejecting malformed complete records.

Run the interactive macOS fixture with:

```sh
swift run --package-path Examples/ScreenerFixture
```

Use **Start recording**, advance the fixture state, capture a frame, and stop the session. Bundles are written under the fixture app's Caches directory.

## Build and test

```sh
swift test
```

Run repeatable local performance measurements for tail timeline paging and contact-sheet generation:

```sh
swift run -c release screener-benchmarks --records 10000 --frames 400 --iterations 7
```

The benchmark builds a temporary synthetic trace outside the timed section and reports p50/p95 latency. It intentionally reports measurements without enforcing wall-clock thresholds, so shared CI machines do not fail from timing noise.

## Local MCP server

Build the standalone macOS stdio server:

```sh
swift build --product screener-mcp
.build/debug/screener-mcp --traces-dir "$HOME/Library/Caches/ScreenerFixture/Traces"
```

Without `--traces-dir`, it checks `~/Library/Caches/Screener/Traces` and `~/Library/Caches/ScreenerFixture/Traces`. Pass the option more than once to add roots. It discovers `.vtrace` directories below each root and exposes four read-only MCP tools:

- `screener.sessions` lists session metadata without local file paths.
- `screener.timeline` returns chronological records in pages of up to 2,000; use `nextOffset` to continue.
- `screener.contact_sheet` returns a chronological grid of up to 24 downsampled frames plus a numbered cell-to-record map. Use `offset` to page through longer sessions.
- `screener.frame` returns one PNG/JPEG thumbnail or keyframe by session and record UUID.

Tools accept catalog UUIDs rather than arbitrary filesystem paths. Frame references are checked after symlink resolution, image types are limited to PNG/JPEG, and each image is capped at 32 MiB. The executable writes no diagnostics to stdout because stdio carries MCP messages.

Configure an MCP host to launch `.build/debug/screener-mcp` over stdio. If traces are outside the defaults, pass `--traces-dir` and the directory as separate arguments. Simulator-container auto-discovery, semantic inspection, and image diffs remain future work.

For example, an MCP host configuration can use an absolute executable path:

```json
{
  "mcpServers": {
    "screener": {
      "command": "/absolute/path/to/Screener/.build/debug/screener-mcp",
      "args": ["--traces-dir", "/absolute/path/to/traces"]
    }
  }
}
```

## Architecture

- `ScreenerCore` owns the trace format, writer, and reader.
- `ScreenerKit` owns main-actor capture adapters and does not depend on MCP or OpenTelemetry.
- `ScreenerMCP` and the separate `screener-mcp` executable read local `.vtrace` bundles and expose session, timeline, and single-frame tools.
- Optional OpenTelemetry instrumentation may report bounded recorder-health signals, but trace records remain the source of visual history. Telemetry delivery does not imply a trace was captured or persisted.

See [`docs/PRD.md`](docs/PRD.md) and [`docs/adr`](docs/adr) for scope and decisions.
