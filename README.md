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

When the captured view is its window's content view, `AppKitCaptureSource` fills pixels the view hierarchy leaves transparent with the window's background color, resolved in the view's appearance. A content view usually draws no background, because the window frame paints it, so without this keyframes are mostly transparent and look black in viewers that drop alpha. Subviews keep their transparency by default, because on screen their clear pixels show their ancestors. Pass `background: .window` or `.transparent` to choose explicitly.

UIKit apps can pass a `UIView` to `UIKitCaptureSource`. SwiftUI callers can pass a view to `SwiftUICaptureSource`; that adapter renders the explicit subtree, while a hosted root view can be captured through its UIKit/AppKit host window. UI rendering happens on the main actor; PNG encoding and bundle writes happen after the rendered `CGImage` crosses to the recorder actor. The resulting `.vtrace` directory contains a JSON manifest, append-only JSONL timeline, and PNG keyframes. Reads tolerate an incomplete trailing line from an interrupted append while rejecting malformed complete records.

UIKit capture reads `view.traitCollection.displayScale` on every capture, including
when the source is a `UIWindow`. Unspecified traits retain UIKit's renderer default.
This is the display's rendering scale in pixels per point, not a request to resample
to `UIScreen.nativeScale`. Capture the containing window for visual effects that
depend on content behind them. `drawHierarchy` does not guarantee system-compositor
fidelity for blur, glass, system overlays, or GPU-backed content; a successful capture
only establishes that UIKit rendered the hierarchy. Compare against a system screenshot
before using material pixels as a regression oracle.

The [UIKit capture fixture](Examples/UIKitCaptureFixture/README.md) provides a
repeatable native-scale and materials check on iOS Simulator.
The [glass capture investigation](docs/validation/glass-research-2026-10-09/README.md)
compares public hierarchy/snapshot paths. The follow-up [physical Air experiment](docs/validation/air-2026-10-09/README.md)
measures substantially closer glass/menu pixels through an opt-in ScreenCaptureKit
session on iOS 27, with manually granted recording permission.

For an experimental SDK session, use a **physical iOS 27 device** with an SDK
that includes ScreenCaptureKit. Retain the capture object until it stops:

```swift
#if os(iOS) && canImport(ScreenCaptureKit) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
if #available(iOS 27, *) {
    let screener = Screener()
    let traceURL = try await screener.startSession(
        name: "materials", appBundleID: "com.example.app", tracesDirectory: tracesDirectory
    )
    let capture = ScreenCaptureKitSession(screener: screener)
    do {
        try await capture.start() // Waits for the user's system permission choice.
        // Exercise the app while retaining capture; semantic markers use screener.mark().
    } catch {
        // Rejection, task cancellation, and startup errors clean up the capture session.
    }
    await capture.stop() // Drain accepted samples before closing the trace.
    let captureFailure = capture.failure // Also check errors after an automatic stop.
    try await screener.stopSession()
}
#endif
```

The [SDK Air session report](docs/validation/screen-capture-session-2026-10-09/README.md)
preserves the recorded menu, timeline, and MCP contact sheet.

The caller owns the trace lifecycle. `start()` requires an active trace and each
capture object is single-use. Only one Screener picker owner may run in the app;
an already-active system picker is rejected. The session captures the current app
without audio, microphone, or camera, samples roughly once per second plus a final drain, retains only
the newest pending sample, and stops after 180 seconds including permission time.
`stop()` is idempotent and waits for startup, stream stop, writes, and a final drain.
Check `state`/`failure` for automatic termination and close the trace afterward.
Always stop explicitly before releasing the capture object; there is no async
cleanup guarantee on deallocation or process termination.

Frames are converted to orientation-corrected RGBA8 sRGB PNGs at the stream's
default resolution. Metadata includes source PTS (`capture.presentationSeconds`),
pixel format, orientation, and available content geometry. Timeline timestamps
describe recorder entry, **not** the original sample time; source PTS is a separate
clock domain. YCbCr conversion is not pixel-identical to a system RGB screenshot.
This bounded keyframe backend does not establish transition-rate or performance
coverage. The type is absent on Simulator, Mac Catalyst, macOS, and SDKs without
the iOS framework; existing hierarchy capture remains available there.

Run the interactive macOS fixture with:

```sh
swift run --package-path Examples/ScreenerFixture
```

Use **Start recording**, advance the fixture state, capture a frame, and stop the session. Bundles are written under the fixture app's Caches directory.

## Codex skill and plugin

The project-local [$screener-visual-trace skill](.agents/skills/screener-visual-trace/SKILL.md)
selects capture evidence and verifies a Debug recording. It covers UIKit as the
default, UIKit trace plus `simctl` screenshots for Simulator materials, and a
manually approved ScreenCaptureKit session on physical iOS 27. It checks the
consumer's actual SDK pin before using the experimental API.

The [Codex plugin manifest](.codex-plugin/plugin.json) exposes that same skill
folder for reuse across apps. This is a skills-only Codex package: it does not
automatically register or launch the MCP server. Connect the built local server
using the instructions below when needed. Plugin versioning is independent of
SDK release versioning; installing this skill does not update an app's dependency.
The layout follows the supported [Codex plugin format](https://developers.openai.com/plugins/build/plugins).

Codex discovers the project skill under `.agents/skills`; if it does not appear,
start a new chat or restart the app. Example:

```text
Use $screener-visual-trace to verify PhotoCompressor's Debug menu in Simulator
with a UIKit trace and a matching system screenshot.
```

To use only the skill in another project's workspace, copy its entire directory
(including references) into that project's `.agents/skills/`. Review an existing
same-named skill before replacing it. The [repo marketplace](.agents/plugins/marketplace.json) exposes `screener` from
this repository root under the **Screener** source. Refresh/restart the host and
install it from that source when using the plugin; creating these files alone
does not install it. For CLI distribution after merge, register the source with
`codex plugin marketplace add SoundBlaster/Screener`, then install
`codex plugin add screener@screener-local`. Avoid installing both a standalone
copy and the plugin into the same consumer.

## Build and test

```sh
swift test
```

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
