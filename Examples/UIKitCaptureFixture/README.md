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
