# Screener

Screener is a local-first visual flight recorder for debugging transient UI states in iOS and macOS apps. It is designed to let a developer or coding agent inspect a recorded timeline after the interesting state has passed.

The repository contains the versioned `.vtrace` bundle core, an app-side session/marker API, and UIKit, AppKit, and SwiftUI capture adapters. The macOS fixture app exercises state changes, markers, and real window keyframes. The read-only MCP server remains a planned milestone.

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

## Architecture

- `ScreenerCore` owns the trace format, writer, and reader.
- `ScreenerKit` owns main-actor capture adapters and does not depend on MCP or OpenTelemetry.
- A future `screener-mcp` process will read `.vtrace` bundles and expose read-only inspection tools.
- Optional OpenTelemetry instrumentation may report bounded recorder-health signals, but trace records remain the source of visual history. Telemetry delivery does not imply a trace was captured or persisted.

See [`docs/PRD.md`](docs/PRD.md) and [`docs/adr`](docs/adr) for scope and decisions.
