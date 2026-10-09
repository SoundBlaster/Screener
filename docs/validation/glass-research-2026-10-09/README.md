# Glass capture research — 2026-10-09

## Result

The tested UIKit variations do not resolve the glass mismatch from the native-scale
pilot. Changing `afterScreenUpdates` or renderer color range leaves the glass panel
and settled native menu substantially different from independent system screenshots.
`CALayer.render` loses visual effects; rasterizing a `snapshotView` reports an incomplete
hierarchy. Capturing the scene's visible windows gives the same result in this one-window
fixture. This is evidence for these paths on this simulator, not a proof that every
possible UIKit technique fails on every OS/device.

At the time of this simulator investigation, ScreenCaptureKit's asynchronous
`SCStream` was a device-only candidate with compile-only evidence; all physical
iPhones were unavailable. Later the same day, the user connected Air and the
[physical-device follow-up](../air-2026-10-09/README.md) established substantially
closer glass/menu pixels, native 3× buffers, clean stop, and cancellation. Positive
recording permission was manually granted. The simulator evidence below is unchanged.

## Simulator experiment

Xcode 27.1 (27A9269); iPhone 17 Simulator, iOS 27.0 (24A434),
`9665FC01-1F2B-4018-B5F1-0E5E857A6235`; all images 1206×2622 at 3×.
Synthetic stripes, standard blur, glass panel, and Save menu are unchanged from PR #9.
The agent inspected hierarchy hit points, opened Share/Photos/Files, and dismissed
the menu before closing its device session. Simulator was shut down after the probe.

The paired system screenshots were taken sequentially while each UI state was static.
ICC-tagged renderer PNGs are converted to sRGB before comparison. The control stripe
region matches exactly for every complete variant. [Exact regions and measurements](comparison.json)
come from [compare-variants.py](../../../Examples/UIKitCaptureFixture/Research/compare-variants.py).
Menu overlaps the glass panel, so panel metrics use the base state only.

Mean absolute RGB error, 0–255:

| Path | Standard blur | Glass panel | Native menu |
|---|---:|---:|---:|
| Existing UIKit adapter | 0.26 | 24.33 | 21.98 |
| Hierarchy, afterScreenUpdates=false | 0.26 | 24.33 | 21.98 |
| Hierarchy, standard range (8-bit) | 0.00 | 24.30 | 21.89 |
| Hierarchy, extended range (16-bit) | 0.26 | 24.33 | 21.98 |
| Visible scene windows (count=1) | 0.26 | 24.33 | 21.98 |
| CALayer.render | 60.55 | 63.65 | 58.28 |
| snapshotView → drawHierarchy | incomplete | incomplete | incomplete |

Small changes from 16-bit/P3 conversion rounding are distinct from the much larger
material error. No fidelity threshold was added to CI.

Images for every path are in [base/](base/) and [menu/](menu/), with each batch's
`latest.json` completeness metadata. Snapshot PNGs are incomplete black diagnostics;
they are excluded from metrics and were never written as `.vtrace` keyframes.

## ReplayKit probe

On the same simulator, `isAvailable` was true and `startCapture` completion succeeded.
No consent prompt appeared. A second, instrumented run completed four batches and
stopped successfully, with **0 callbacks, 0 video callbacks, 0 pixel buffers, and 0
converted frames** over 14.30 seconds between start/stop status writes.
[Counters](replaykit/replaykit-summary.json),
[start status](replaykit/replaykit-status.txt), and [stop status](replaykit/replaykit-stop.txt)
are preserved. This establishes failure to deliver samples in this environment;
it does not establish ReplayKit behavior on physical devices.

The material batches predate the added callback counters and deadline; rendering
logic is unchanged. The final instrumented fixture was rebuilt and run separately.
Builds succeeded with implicit compiler modules. Initial build/install attempts hit
disk exhaustion; rebuildable Screener compiler caches were reclaimed, and installation
then succeeded. Package/library behavior was not modified; the research mode is opt-in.
[Runtime details](runtime.json) and [source/image identities](identity.json) preserve
the evidence scope. A later cleanup correction makes stop-status writes best-effort,
so a full disk cannot prevent calling `stopCapture`; that correction does not affect pixels.

## Public API findings

| API | Installed iPhoneOS 27.1 SDK | Installed Simulator SDK |
|---|---|---|
| UIView.drawHierarchy / snapshotView | Available | Available; measured above |
| ReplayKit | Deprecated in iOS 27, replacement is ScreenCaptureKit | Available, but probe delivered no samples |
| ScreenCaptureKit SCStream | Available from iOS 27 | Framework/module absent |
| SCScreenshotManager | Explicitly unavailable for iOS | Framework/module absent |

The device-SDK [API probe](../../../Examples/UIKitCaptureFixture/Research/ScreenCaptureKitAPIProbe.swift)
successfully typechecked with Swift 6 and target `arm64-apple-ios27.0`. It configures
the current-application picker, receives a selected `SCContentFilter`, starts a
screen-only stream, and provides stop/picker cleanup primitives. It is excluded
from the app target and does not prove a working runtime implementation.

The installed SDK exposes `width`/`height` on iOS 27, but marks
`minimumFrameInterval`, `queueDepth`, and `pixelFormat` unavailable for iOS. A future
Screener receiver must inspect actual buffers and thin frames before encoding;
macOS configuration examples cannot be copied unchanged. Availability declarations
are included in [SDK evidence](sdk.json) without copying proprietary implementation.

Primary sources:

- [Apple: Capturing screen content on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
  describes the picker and explicitly requires a device running iOS 27+.
- [Apple: presentForCurrentApplication](https://developer.apple.com/documentation/screencapturekit/sccontentsharingpicker/presentforcurrentapplication())
  limits the selected content to the current app.
- [Apple: snapshotView](https://developer.apple.com/documentation/uikit/uiview/snapshotview(afterscreenupdates:))
  returns a stand-in view; this experiment tests the additional bitmap conversion.
- [Apple: UIVisualEffectView](https://developer.apple.com/documentation/uikit/uivisualeffectview)
  requires capturing the containing window or screen for effect snapshots.

## Screener integration boundary and next validation

`ScreenerCaptureSource.capture()` is synchronous and main-actor isolated. A
consent-driven `SCStream` should be owned by a separate capture session that feeds
`Screener.recordFrame`; changing the UIKit adapter to wait for stream frames would
misrepresent its contract. The session must own picker authorization, start/stop,
stream errors, frame status, orientation/scale, and bounded buffering. Actual sample
timestamps should remain distinguishable from PNG publication time.

The next bounded experiment is to connect the Air, capture this synthetic fixture
through the current-app picker, and compare delivered stream frames to independent
device screenshots for the same settled base/menu states. Validate sample resolution,
orientation, stop/cancel behavior, and encoding cost before proposing a library backend.
No public compositor-fidelity promise follows from this investigation yet.
