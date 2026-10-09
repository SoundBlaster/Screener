# Capture workflows

Read only the mode relevant to the task. Commands use placeholders resolved from
current device/project/container discovery; do not copy a prior run's UUIDs.

## UIKit Debug capture

Capture the containing `UIWindow` for effects that depend on content behind them.
Render on MainActor; Screener performs PNG encoding and writes away from the UI.
Adapt this to the app's existing Debug lifecycle rather than copying a fixture's
bundle ID, fixed view coordinates, or polling loop.

```swift
#if DEBUG
let recorder = Screener()
let traceURL = try await recorder.startSession(
    name: "menu-check", appBundleID: bundleID, tracesDirectory: traceDirectory
)
let capture = ScreenerCaptureSession(screener: recorder)
try await recorder.mark("Menu.before-open")
try await capture.capture(from: UIKitCaptureSource(view: window), reason: "base")
// Exercise the app; capture again after the desired state has rendered.
try await capture.capture(from: UIKitCaptureSource(view: window), reason: "menu")
try await recorder.stopSession()
#endif
```

For a complete Debug integration, put stop/cleanup on error paths too; the snippet shows
API shape, not a complete app controller. Decode stored PNGs and compare their
width/height with the captured view's point size × current trait scale. Check both
axes, window bounds, orientation, and trait changes before diagnosing a scale bug.
A passing renderer call is not evidence of exact glass/blur.

## Simulator materials reference

Identify the intended booted Simulator by UDID and OS; do not use `booted` when
multiple simulators are running. Reproduce and keep the app state steady, capture
its UIKit keyframe, then obtain an independent system screenshot:

```sh
xcrun simctl list devices available --json
xcrun simctl io SIMULATOR_UDID screenshot /absolute/evidence/menu-system.png
xcrun simctl get_app_container SIMULATOR_UDID APP_BUNDLE_ID data
```

Use the returned app-data container and the app's configured trace subdirectory
to copy the selected `.vtrace` after completion. Do not assume `Documents/Captures`
for every consumer. Keep system PNGs beside the trace as comparison evidence;
do not relabel them as UIKit frames. Match the exact menu state/appearance and
crop to comparable app/material regions. Status bars and system overlays may
legitimately differ from a current-app/window capture.

## Physical ScreenCaptureKit session

Verify the intended connected device is physical (`isSimulator: false` where the
tool exposes it) and eligible in Xcode, cross-checking the exact UDID. For a named
Air, use the user's selected physical Air, not a Simulator with a similar name.
Preserve signing, package trust, and bundle IDs; use the app's normal signing
configuration. If the selected device is unavailable, report that state before
switching targets. A device-interaction service rejecting the phone does not
prove CoreDevice/Xcode cannot run it; check the same physical destination there.

Guard compile-time framework availability and runtime iOS version:

```swift
#if DEBUG && os(iOS) && canImport(ScreenCaptureKit) && !targetEnvironment(simulator) && !targetEnvironment(macCatalyst)
if #available(iOS 27, *) {
    let recorder = Screener()
    let traceURL = try await recorder.startSession(
        name: "materials", appBundleID: bundleID, tracesDirectory: traceDirectory
    )
    let capture = ScreenCaptureKitSession(screener: recorder)
    do {
        try await capture.start() // User manually approves the current-app picker.
        // Retain capture while exercising and marking base/menu states.
        // Return here from an explicit Stop control or after automatic termination.
    } catch {
        // Surface denial/cancellation/startup errors to the development UI/log.
    }
    await capture.stop()
    let captureFailure = capture.failure
    try await recorder.stopSession()
}
#endif
```

Implement this as a retained development controller/task with a Stop control;
placing these lines consecutively with no app interaction would immediately stop
recording. Observe `state`/`failure` for automatic termination. The SDK object is
single-use, requires an already-active trace, rejects an active picker, disables
audio/microphone/camera, and requests stop after 180 seconds including permission
time. `stop()` is idempotent, waits for startup and in-flight writes, and drains
the final pending complete frame. Explicitly stop before releasing the object.

Frame conversion uses orientation-corrected RGBA8 sRGB PNG at the stream's default
resolution. One newest pending sample bounds the backlog. Source PTS is
`capture.presentationSeconds`; trace timestamps describe recorder entry. Check
actual resolution/scale from the saved frame metadata and decoded image, not the
UIKit reference dimensions. YCbCr source conversion can differ from system RGB.
Do not copy macOS-only settings such as `minimumFrameInterval`, `queueDepth`, or
`pixelFormat` to the current iOS SCStream configuration.

After a bounded run, copy the app's configured trace location using CoreDevice:

```sh
xcrun devicectl list devices
xcrun devicectl device copy from --device PHYSICAL_UDID \
  --domain-type appDataContainer --domain-identifier APP_BUNDLE_ID \
  --source Documents/APP_TRACE_SUBDIRECTORY --destination /absolute/evidence/device-traces
```

If UI automation is used, wait a bounded interval for human approval and preserve
screenshots/hierarchy before and after menu/stop. Use a fresh `.xcresult` summary;
a build-only test or a permission timeout does not establish a successful capture.

## Inspect .vtrace and use MCP

The app must write a real `.vtrace` before the read-only MCP server can expose it.
Resolve the built `screener-mcp` product path from actual build output; SwiftPM
product paths differ across toolchains. Configure a local MCP host with that
absolute executable and `--traces-dir /absolute/path/to/copied-traces` when needed.
The plugin's skill does not itself install/build/start a server. Follow the host's
normal configuration only when requested.

Verify manifest/session ID, contiguous timeline sequence, backend metadata and
referenced image files. Check `screen-capture.stopped` then `sessionEnded`, and
inspect any capture failure separately: completion records alone do not prove
that every write or stream stop succeeded. On an interrupted trace, distinguish
an incomplete trailing JSONL record from malformed complete data.

`screen-capture.stopped` belongs to `ScreenCaptureKitSession`. UIKit and older
consumer-local adapters can use different markers; inspect their lifecycle
contract rather than rejecting a valid trace for lacking this SDK-specific event.

MCP order: list sessions, select the actual recorded ID, inspect timeline, then
request a contact sheet or a frame by returned record ID. Use pagination when
needed. A contact sheet proves decoded history, not frame-rate coverage; inspect
full-resolution material/menu PNGs for fidelity. Keep screenshots and source PTS
alongside trace times to identify the same settled state without equating clocks.

## Evidence identity and replay pitfalls

These checks came from a real large-button/context-menu pilot; apply them when
the same ambiguity arises rather than copying that app's flags, paths or budgets.

- **Separate three identities.** Preserve the consuming `Package.resolved` pin
  (or equivalent), the installed app binary/build identity, and the MCP executable
  path/hash plus initialize response. In the alpha.1 pilot the SDK resolved to
  `10ba0dd` while both the trace manifest and an older reader reported `0.1.0`.
  This was not evidence that the old SDK had been installed. Recheck a new pin
  against actual adapter changes; a release tag alone does not improve glass.
- **Separate capture availability from UI automation.** A connected physical
  Air was rejected by an interaction service that exposed only simulators, while
  CoreDevice successfully installed/launched/copied its trace. Use manual actions
  when needed and label them. If a prepared UI session expires with “Session not
  found”, reacquire it once, recapture hierarchy and verify the target/app PID;
  repeated unchanged failures are a tool blocker, not proof of an app crash.
  A tool's `NotRun` response is not a successful UI-test result; retained runtime
  screenshots/hierarchy can still provide narrower observation evidence.
- **Coordinate bounded capture with the person.** Discover the current trace
  and trigger mechanism after launch. For a file-triggered app pilot, wait for
  consent/running state before requesting a burst; capture the base, then ask the
  person to leave the menu open before requesting the next burst. Keep the same
  approved stream. Arming may expire while waiting for a reply; inspect lifecycle
  instead of writing controls to an already-closed trace. Do not impose that
  app's file polling or burst budget on the SDK session API.
- **Inspect actual samples.** Decode PNGs, count frames/failures, and check final
  lifecycle and referenced blobs. A closed zero-frame trace is not a capture
  success. Some local adapters repeatedly publish the latest complete image;
  frame count then does not establish distinct source samples or temporal coverage.
  Full-resolution base/menu frames expose material differences hidden by a small
  contact sheet. Inspect the opening too if the reported defect is transient;
  a clean settled menu cannot rule out an earlier outline or jump.
- **Limit fidelity claims to the comparison.** The pilot produced native 3×
  UIKit traces with visibly incorrect menu backdrops; scale success did not fix
  glass. Physical stream captures showed coherent glass, but without a matched
  independent device screenshot they established appearance observations, not a
  numerical match. Keep light/dark, Reduce Transparency, older-OS fallbacks and
  device/layout profiles separately checked or explicitly unverified.
- **Keep replay portable.** Reuse the consumer's project and prescribed build
  cache; keep copied traces, selected PNGs and run metadata outside disposable
  build products. A complete handoff identifies backend/SDK/app/reader, target/OS,
  launch/control steps, manual actions, frame dimensions/scale, failure counts,
  termination, representative record IDs and raw artifact location. Avoid
  reconfiguring a global MCP host just to inspect one trace: an existing reader
  can be invoked through its actual stdio protocol, labeled as such rather than
  presented as a registered connector.
