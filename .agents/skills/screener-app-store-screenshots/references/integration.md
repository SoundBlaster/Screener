# Consuming application integration

## Copy reusable assets

```sh
python3 /path/to/skill/scripts/install.py --root /path/to/app \
  --app-sources App/shared/screener --test-sources AppUITests
```

The installer creates `screenshots/tools/run.py`, `prepare.swift`, app-side
`ScreenshotHarness.swift`, UI-test `ScreenshotScenario.swift` and a SHA provenance manifest.
It makes no project-file edits. Project source discovery/generation must include both Swift files.
`ScreenerKit` 0.1.0 is sufficient; preserve a compatible existing pin where appropriate.

Create a screenshot configuration with `SCREENER_SCREENSHOTS` on the app target and an
isolated bundle ID. A Debug-based configuration also needs inherited `DEBUG` if existing
fixtures use it. SDK-qualified compilation conditions can override unqualified settings;
inspect resolved settings and preserve the app's existing conditions.

## App adapter

Attach a hidden, noninteractive probe to the main screen:

```swift
#if SCREENER_SCREENSHOTS
.background {
    ScreenshotProbe(isReady: appPolicyResult, presentation: currentPresentation)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
}
#endif
```

Readiness is app-owned: loaded fixture, completed rendering inputs, no error or unwanted
cover, no in-flight work. For SpecificationCore applications, evaluate a named spec here.
The harness additionally checks active hosting scene, matching presentation and stable
window bounds/local trait scale. It does not use a process-wide first window.

A presentation change should be observable by the probe. A checkpoint's expected
presentation must match it. UI tests still assert the desired controls/content themselves.
Fixture launch arguments/environment are configured in JSON, not shell-interpolated text.
Keep personal content and secrets out of fixtures and manifests.

## UI scenario

```swift
@MainActor
final class AppScreenshotTests: XCTestCase {
    func testScreenshots() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        try ScreenshotScenario.run { app, capture in
            XCTAssertTrue(app.buttons["Open details"].waitForExistence(timeout: 20))
            try capture.checkpoint("01-main", presentation: "main")
            app.buttons["Open details"].tap()
            XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
            try capture.checkpoint("02-details", presentation: "details")
        }
    }
    func testRuntimeOptOut() throws {
        try ScreenshotScenario.verifyRuntimeOptOut(readyIdentifier: "Open details")
    }
}
```

`ScreenshotScenario` launches once per orientation with runtime opt-in/run UUID, resolves
XCTest's potentially relocated container, waits for acknowledgements, writes system PNGs
atomically, stops/drains the trace and terminates the app. Without `SCREENER_TEST=1`, tests skip.
Avoid relying on xcresult attachment export as the sole PNG transport.

## Configuration

Put `capture.json` under the consuming `screenshots/` directory:

```json
{
  "projectRoot": "..",
  "project": "App.xcodeproj",
  "scheme": "App",
  "buildConfiguration": "ScreenerScreenshots",
  "bundleID": "example.app.screenshots",
  "appProduct": "App.app",
  "testTarget": "AppUITests",
  "testClass": "AppScreenshotTests",
  "derivedData": ".build/DerivedData",
  "generate": ["xcodegen", "generate", "--spec", "project.yml"],
  "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-12GB",
  "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
  "nativePortraitPixels": [2064, 2752],
  "locales": ["en-US"],
  "orientations": ["portrait", "landscapeLeft"],
  "checkpoints": ["01-main", "02-details"],
  "launchArguments": [],
  "launchEnvironment": {},
  "appearance": "light",
  "minimumFreeGiB": 5
}
```

Remove `generate` when the project has no generator. Existing build/project conventions
win. `commandPrefix` optionally supplies a local wrapper, e.g. `["rtk", "proxy"]`;
it is not required by Screener. `output` defaults to `screenshots/output`, which should be ignored.
The runner requires macOS/Xcode, Python 3.10+ and the configured Simulator runtime.

```sh
python3 screenshots/tools/run.py --config screenshots/capture.json
python3 screenshots/tools/run.py --config screenshots/capture.json --simulator UUID --skip-build
python3 screenshots/tools/run.py --prepare-output screenshots/output/RUN
```

A Make target may wrap the first command with `$(SCREENSHOT_ARGS)`.
Creating a new Simulator requires 5GiB free. The configured headroom is a preflight,
not a capacity guarantee: repeated iOS wallpaper caches can grow by gigabytes. Inspect
cache ownership before clearing rebuildable data; preserve output, app data and user devices.
The runner disables large failure sysdiagnoses while retaining logs/xcresults/partial traces.
Xcode's project-relative Derived Data setting may append the project name. Check the
actual resolved output path before combining GUI and CLI builds; selecting the same
parent folder does not establish that both builds reuse the same cache.
If package macro trust blocks a fresh integration, inspect the exact resolved revision
and approve that target through Xcode with authorization; do not add a global validation
bypass to this runner.

## Artifacts and timing

Raw captures, `.vtrace`, system references and diagnostic copies remain separate.
Prepared PNGs remove only opaque alpha, normalize EXIF and retain native RGB depth/color space;
`prepare.log` confirms decoded equality. `manifest.json` records binary/config/tool identity,
raw/prepared hashes, geometry, scale and trace/record links. `review.html` is a labelled gallery.

`metrics.json` records total runtime and each subprocess duration (generation, build,
boot/install, each locale UI run, preparation, shutdown). Preparation-only recovery writes
`preparation-metrics.json` separately and preserves the original capture metrics.
Compare equal matrices/fixtures and distinguish build, integration, repeat capture and
human review time. A paired PNG batch has two files per UI state, not twice as many states.

## Failure contract

Fail on missing/duplicate/reordered checkpoints, unexpected runs/orientations, unclosed traces,
non-native geometry, changed raw hashes or failed PNG preparation. Preserve diagnostics;
never mark a failed original invocation as successful because recovery later succeeded.
An in-flight capture can finish after a budget; process termination can leave an unclosed trace.
The collector rejects it. Cancellation attempts to close the caller-owned session.
