# ScreenCaptureKit on physical iPhone Air — 2026-10-09

## Result

The device-only ScreenCaptureKit experiment substantially reduces the UIKit adapter's
glass and native-menu mismatch on this fixture. It delivers native 3× app frames and
supports clean stop and declined permission. It is an opt-in research implementation,
not a new ScreenerKit backend or a promise of lossless screenshots on every device.

**Positive screen-recording permission was granted manually by the user.** The initial
UI test's `Record Screen` tap did not establish automated approval. After the user
clarified this, the test was changed to wait up to 60 seconds for manual permission.
That final test adjustment was compiled with `build-for-testing`, without another
device run or permission request. Repeated research launches prompted again; future
interactive experiments should reuse one approved session across fixture states.

## Device and execution

- Physical iPhone Air (`iPhone18,4`), UDID `00008150-000208290280401C`;
  Xcode destination `isSimulator=false`, CoreDevice reality `physical`.
- iOS 27.0 (24A435), Xcode 27.1 (27A9269), device SDK 27.1.
- Window 420×912 points, traits scale 3; delivered buffers **1260×2736**.
- Current-app picker; microphone/camera controls hidden, audio capture disabled,
  only `.screen` output registered. No Photos/Files/Share action exports anything.
- Dark material appearance on Air; each comparison uses this Air's own system
  screenshot. Simulator light-appearance numbers are not a device baseline.

The device-interaction service rejected the physical UDID despite Xcode/CoreDevice
seeing it as connected and eligible. The fallback used signed Xcode builds and
XCUITest on the exact physical destination. Signing team was supplied as a local
build argument; project bundle ID/signing settings were not changed. The first
build exposed a Swift 6 filter-transfer diagnostic, resolved with a narrowly scoped
immutable selection wrapper.

The successful capture test waited for `running`, preserved base and settled Save-menu
screenshots, dismissed the menu through its no-op Files action, and tapped Stop capture.
An independent reviewer inspected the screenshots and hierarchies: labels were readable,
no unintended overlap/clipping was observed, PID 3268 remained stable, and final
status was `finished`.

## Paired measurements

All images are 1260×2736; ICC-tagged images are converted to sRGB with Pillow.
No spatial resampling or alignment correction is applied. Regions exclude the system
status bar/home indicator. The menu's 120,454–370,588 point bounds come from the
observed accessibility hierarchy. Paired frames were selected by publication time
within static UI states; this is not a synchronized same-instant capture.

Mean absolute RGB error, 0–255:

| Region/state | UIKit adapter | SCStream |
|---|---:|---:|
| Control stripes, base | 0.00 | 2.66 |
| Standard blur, base | 0.46 | 0.72 |
| Glass panel, base | **26.90** | **0.95** |
| Native menu, settled | **22.81** | **1.00** |

The stream is not pixel-identical to the reference. Actual buffers use `420f`
(8-bit bi-planar full-range YCbCr 4:2:0), then Core Image converts them to 8-bit sRGB
PNG. Chroma subsampling and conversion are plausible contributors to the nonzero
control error; this experiment does not isolate their individual contributions.

- [Base: system](base/system.png), [UIKit](base/adapter.png), [stream](base/stream.png).
- [Menu: system](menu/system.png), [UIKit](menu/adapter.png), [stream](menu/stream.png).
- [Exact metrics](comparison.json), [pair identities and source hashes](identity.json),
  [comparison script](../../../Examples/UIKitCaptureFixture/Research/compare-air.py).

## Lifecycle and encoding

The capture run received **199 complete frames/callbacks** and published 12 PNGs.
The sink retains at most one pending complete buffer, publishes at approximately
one-second intervals, and keeps a 32-slot stream PNG ring; the hierarchy comparator
keeps a 16-slot ring at two-second intervals. A 180-second deadline includes time
waiting for permission. These are research bounds, not a production throughput design.

[Events](events.txt) confirm `started isCapturing=true`, then `stopped isCapturing=false`
and `finished pickerActive=false`. The hierarchy task's logged `CancellationError`
is expected when Stop capture cancels its sleep. [Summary](summary.json) contains counters.

The declined-permission run reached `picker-cancelled`, deactivated the picker,
and produced **0 callbacks/frames/PNGs**: [cancel evidence](cancel/events.txt),
[cancel counters](cancel/summary.json). It does not prove every interruption/error path.

Observed Core Image conversion plus PNG encoding time across 12 publications was
0.153–0.263 s, median 0.174 s. Timing ends before PNG file writes and metadata writes;
this is not end-to-end capture latency or a sustained performance benchmark.
The receiver did not report a `videoOrientation` attachment in preserved metadata;
portrait geometry matched the system images. Rotation, backgrounding, interruptions,
and other pixel formats were not exercised.

## Validation scope

[Fresh xcresult summaries](test-results.json) preserve all four runs:

- Reconnaissance: passed, 1 test. User approved before the first captured hierarchy;
  that capture alone did not show the permission UI.
- Initial capture attempt: failed because the test required an unconfigured consent
  selector. Its hierarchy supplied exact `Record Screen` / `Don’t Allow` labels.
- Capture retry: passed, 1 test; human-assisted approval, base/menu/stop verified.
- Decline/cancel: passed, 1 test; cancellation and zero frames verified.

The final manual-permission test revision was build-only. Executed source hashes are
in [source-digests.json](source-digests.json), final revision hashes in
[final-source-digests.json](final-source-digests.json). The app capture implementation
is unchanged between the successful runtime experiment and final build.
Existing Simulator/package tests remain the CI validation; no library code changed.

## Integration consequence

`SCStream` is a viable material-fidelity candidate on this physical iOS 27 device,
but its user-granted recording session has a different lifecycle from synchronous
`UIKitCaptureSource.capture()`. Keep it an explicit opt-in session owner feeding
`Screener.recordFrame`, rather than silently replacing the default UIKit source.
Preserve sample timestamps independently of publication time and expose start/stop,
denial/errors, frame status, and actual buffer geometry. Next work is a bounded
ScreenerKit session prototype with one approval per active recording session, followed
by orientation/interruption and encoding-cost checks.
