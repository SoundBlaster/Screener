# UIKit capture fixture

A small iOS app for checking window resolution and backdrop-dependent materials.
It renders colored stripes behind `UIBlurEffect.systemMaterial`, `UIGlassEffect`
(iOS 26+), and a native Save menu. No Photos/Files/Share action performs an export.

Requires Xcode, an iOS Simulator, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
From the repository root:

```sh
xcodegen generate --spec Examples/UIKitCaptureFixture/project.yml
xcodebuild test \
  -project Examples/UIKitCaptureFixture/UIKitCaptureFixture.xcodeproj \
  -scheme UIKitCaptureFixture \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath .build/uikit-fixture
```

The app-hosted Swift Testing target runs the same UIKit regression tests as the
package. macOS `swift test` cannot execute UIKit tests.

Run the app on the same simulator and compare captures:

```sh
xcrun simctl install YOUR_SIMULATOR_UDID \
  .build/uikit-fixture/Build/Products/Debug-iphonesimulator/UIKitCaptureFixture.app
xcrun simctl launch YOUR_SIMULATOR_UDID dev.screener.UIKitFixture
xcrun simctl io YOUR_SIMULATOR_UDID screenshot /tmp/uikit-system.png
xcrun simctl get_app_container YOUR_SIMULATOR_UDID dev.screener.UIKitFixture data
```

The app records 60 window keyframes at two-second intervals, then closes the trace.
The data container's `Documents/Captures` contains the `.vtrace`, `latest.png`, and
`latest.txt` with actual pixel dimensions, scale, and window traits. A capture failure
is written to `error.txt`. Open Save and compare a settled menu capture with an
independent simulator screenshot while the menu stays open. Compare at the same
pixel size, excluding the system status bar and home indicator from app-window
fidelity claims. Geometry, scale, and material fidelity are separate checks.

This fixture intentionally retains unredacted local images; use its synthetic
content only. Relaunch to start another bounded recording.

## Glass capture research

Launch with `--capture-research` to compare public UIKit rendering paths. Optional
`--replaykit-probe` starts ReplayKit with microphone/camera disabled and retains
video frames only. This may display a system consent prompt on supported devices.
`--research-passes=4` shortens the run (clamped to 1–40 batches). The loop also stops
at a 120-second deadline checked between batches; rendering can extend the final batch.
ReplayKit is stopped after normal completion or a caught error/cancellation.

```sh
xcrun simctl launch YOUR_SIMULATOR_UDID dev.screener.UIKitFixture \
  --capture-research --replaykit-probe --research-passes=4
```

`Documents/CaptureResearch/latest-run.txt` identifies a unique run directory, which
holds the latest adapter, hierarchy (false/standard/extended),
layer, snapshot-hierarchy, and scene-windows PNGs. Old runs are kept separately;
copy only the selected run. Final ReplayKit counters are persisted after the stop
completion and any in-flight sink callback; `stopCompleted=false` flags a failed stop.
`latest.json` records completeness;
an incomplete snapshot PNG is diagnostic output, never a trace keyframe. Capture
base/menu batches and independent `simctl` screenshots as `base/system.png` and
`menu/system.png`. Copy each batch while that state remains static, then run:

```sh
python3 Examples/UIKitCaptureFixture/Research/compare-variants.py PATH_WITH_BASE_AND_MENU
```

The comparison needs Pillow and converts ICC-tagged images to sRGB. It excludes
incomplete snapshot output and avoids measuring the glass panel where the menu overlaps it.
See the [dated research report](../../docs/validation/glass-research-2026-10-09/README.md).

`Research/ScreenCaptureKitAPIProbe.swift` is excluded from the app target. It is a
device-SDK typecheck probe, not a runtime implementation:

```sh
xcrun --sdk iphoneos swiftc -typecheck -swift-version 6 \
  -target arm64-apple-ios27.0 \
  Examples/UIKitCaptureFixture/Research/ScreenCaptureKitAPIProbe.swift
```

## Physical iOS 27 ScreenCaptureKit probe

On a physical device with the ScreenCaptureKit module, launch with
`--screencapturekit-probe`. Manually approve the system screen-recording request.
The mode captures the current app only and adds Stop capture/status controls below
the material regions. It is excluded from Simulator builds and leaves the default
UIKit recording mode unchanged.

`Documents/ScreenCaptureResearch/latest-run.txt` identifies a unique run directory.
It contains latest/ring stream and adapter PNGs, source sample timestamps,
publication times, actual pixel format/geometry, lifecycle events, and final counters.
The stream ring has 32 slots; the adapter ring has 16. The whole experiment stops
after 180 seconds, including permission time, or through Stop capture. Reuse a
single approved session for base/menu comparisons rather than repeatedly relaunching.

The separate `UIKitCaptureAirResearch` scheme contains gated XCUITest research.
Set `TEST_RUNNER_SCREENER_AIR_RESEARCH=1` and
`TEST_RUNNER_SCREENER_AIR_PHASE=reconnaissance`, `capture`, or `cancel` when invoking
`xcodebuild`. Capture waits up to 60 seconds for manual approval; it never presses
a positive consent button. Cancel requires `TEST_RUNNER_SCREENER_AIR_CANCEL_LABEL`
from the observed system hierarchy. Always target the exact physical device UDID
and supply your normal local signing team; the standard fixture scheme does not
run these UI experiments.

See the [Air results and validation limits](../../docs/validation/air-2026-10-09/README.md).
Reproduce preserved color-managed metrics with Pillow:

```sh
python3 Examples/UIKitCaptureFixture/Research/compare-air.py docs/validation/air-2026-10-09
```


## SDK trace session on Air

Launch with `--screencapturekit-trace` to use `ScreenerKit.ScreenCaptureKitSession`
instead of the standalone research PNG sink. Manually approve recording once,
exercise base/menu states, then press **Stop capture**. The fixture waits for the
SDK drain before closing its trace. `Documents/ScreenCaptureTraces/latest-run.txt`
identifies the complete `.vtrace`; `error.txt` flags an SDK/persistence error.
The SDK samples one keyframe per second with a single pending frame and a
180-second total bound. Its source PTS and capture metadata accompany each PNG.

For the gated Air UI test, additionally set
`TEST_RUNNER_SCREENER_AIR_SDK_TRACE=1` with the existing research opt-in and
`TEST_RUNNER_SCREENER_AIR_PHASE=capture`. This waits for manual permission and
checks running → menu → stopped; it never grants permission automatically.
The normal app-hosted test scheme also checks SDK lifecycle preconditions on
physical iOS 27 without presenting a picker.
