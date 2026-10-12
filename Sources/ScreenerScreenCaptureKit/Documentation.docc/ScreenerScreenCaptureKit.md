# ``ScreenerScreenCaptureKit``

Capture explicit macOS windows through Apple's system compositor and store them in Screener traces.

## Overview

This optional product depends on ScreenerKit. Apps supplying custom frames do not
need to import or link it. The package minimum remains macOS 13; window still
capture requires macOS 14 or later. Its symbols are absent on iOS and Simulator.
The existing physical-iOS `ScreenCaptureKitSession` remains in ScreenerKit.

Start a Screener trace, then use `ScreenCaptureKitWindowSource` with an explicit
window ID and expected process ID. `record(to:reason:metadata:)` captures and
persists through the ordinary recorder, returning the image for comparison/export.
`capture()` returns an image without recording. The app owns trace stop/drain.

Capture requires existing Screen Recording access. `isAuthorized` only checks;
the app arranges manual authorization separately. There is no automatic prompt,
desktop fallback, hierarchy fallback, sampling loop or continuous stream.

Native dimensions derive from the system content rectangle and pixel scale.
The source excludes cursor and shadow and checks the returned dimensions. SDR
Metal success does not establish HDR/EDR, RealityKit or protected-content fidelity.
Inspect actual content against a matched system screenshot.
