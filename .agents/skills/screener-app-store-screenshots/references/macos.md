# macOS window batches

Use this adapter for a real macOS app; the Simulator runner remains the iOS/iPadOS path.
This adapter is an experimental extension validated on BuildHunter: two UI tests
and three paired whole-window checkpoints completed at native 2x on macOS 27.0.
Read the current [validation record](validation.md#macos-consumer-buildhunter)
for the checked matrix, startup repairs and remaining limits.
Keep existing working Screener traces and fixtures. Add only the checkpoint handoff
needed for reproducible stills. No Screener SDK API change is needed.

## Integrate

Prerequisites: an Apple Silicon Mac, Xcode, Python 3.10+, a shared app scheme
and a macOS UI-test target. The actual display must fit the configured whole
window at its native backing scale. For an existing integration, keep its
scenario/configuration and skip installation.

```sh
python3 /path/to/skill/scripts/install.py --platform macOS --root /path/to/app \
  --app-sources App/Screenshots --test-sources AppUITests
```

It adds the macOS Swift
adapters, `ScreenshotRunner.entitlements`, `run_macos.py`, and the shared collector/preparer with SHA provenance.
It does not wire project sources/settings or generate a scenario/configuration.
Use project tooling to add an opt-in `SCREENER_SCREENSHOTS` configuration with
an isolated bundle ID. Link ScreenerKit to the screenshot target; preserve any
existing dependency scope. Do not create an extra Xcode project or build cache.

For the screenshot UI-test target/configuration, set `CODE_SIGN_ENTITLEMENTS` to
the copied `ScreenshotRunner.entitlements`. Xcode's macOS UI runner is sandboxed;
the template grants write access to the selected output root and the isolated
app's checkpoint cache. The runner passes normalized `SCREENER_OUTPUT_ROOT` and
`SCREENER_APP_BUNDLE_ID` build settings used by that template. Keep these grants
on the screenshot test target. Review the actual signed runner entitlements,
including expanded paths, when diagnosing file transport. The supplied template
assumes a sandboxed target app; adapt its cache path for an unsandboxed app.

Read Apple's [temporary exception path rules](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html):
both absolute and home-relative entitlement paths start with `/`; directories
end with `/`. A missing leading slash or unresolved `..` can invalidate the grant.

Attach `MacScreenshotProbe(isReady: appPolicyResult, presentation: "main")` in
the relevant view's background, with `.allowsHitTesting(false)`. Each window has
an explicit presentation identifier; the shared recorder never chooses the first
process window. Attach a second probe for a separate diagram/details window.
Readiness still belongs to the app: completed fixture/model work and no pending
transition. The recorder adds 800ms stable geometry and checks the requested
window is visible, key, active and entirely within its screen's visible frame.
Keep the macOS probe accessible: the helper reads `screener.capture.directory`
from it to resolve the app's sandbox cache. Do not copy the iOS example's
`.accessibilityHidden(true)` modifier onto this probe.

In a screenshot-only XCTest class, call `MacScreenshotScenario.run { app, capture in … }`.
Navigate real controls, assert the expected content, query the specific window, then
`try capture.checkpoint("01-main", presentation: "main", window: mainWindow)`.
Do not pass `app` or a desktop screenshot in place of the window. The helper obtains
the app's sandbox-resolved cache path via a transparent accessibility probe, captures
the paired system PNG with `window.screenshot()`, stops/drains the trace and exports
the run to the runner's output directory. Partial runs are retained when possible.

An app can relaunch without windows. Supply `MacScreenshotScenario.run(prepare: …)`
with app-specific real menu navigation to open the requested window before the
probe lookup. The helper does not infer an arbitrary app's New Window command.
For deterministic SwiftUI appearance, apply the capture profile at the owning
root views using the app's policy framework and `preferredColorScheme`. A late
`NSWindow.appearance` change alone can leave SwiftUI and AppKit in mixed themes.

### Minimal consumer scenario

Replace these window identifiers/buttons with the app's actual accessibility
identifiers and navigation. Match checkpoint names/order to the config below.
The installer provides `MacScreenshotScenario`, not this consumer test class.
For apps needing a fixture, configure its launch inputs and readiness before capture.

```swift
import XCTest

@MainActor
final class AppScreenshotTests: XCTestCase {
    func testScreenshots() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        try MacScreenshotScenario.run { app, capture in
            let main = app.windows.matching(identifier: "app.main.window").firstMatch
            XCTAssertTrue(main.waitForExistence(timeout: 20))
            XCTAssertTrue(main.buttons["Open details"].exists)
            try capture.checkpoint("01-main", presentation: "main", window: main)
            main.buttons["Open details"].click()
            let details = app.windows.matching(identifier: "app.details.window").firstMatch
            XCTAssertTrue(details.waitForExistence(timeout: 10))
            try capture.checkpoint("02-details", presentation: "details", window: details)
        }
    }

    func testRuntimeOptOut() throws {
        guard ProcessInfo.processInfo.environment["SCREENER_TEST"] == "1" else {
            throw XCTSkip("Use the screenshot runner")
        }
        let app = XCUIApplication()
        // A valid UUID alone must not activate capture.
        app.launchEnvironment = ["SCREENER_RUN_ID": UUID().uuidString]
        app.launch()
        app.activate()
        defer { app.terminate() }
        XCTAssertTrue(app.windows.matching(identifier: "app.main.window")
            .firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)
            .matching(identifier: "screener.capture.directory").firstMatch.exists)
    }
}
```

There is no macOS `verifyRuntimeOptOut` helper. Adapt the explicit opt-out test to
the app's fixture/window setup, retaining the assertion that capture stays off.
If relaunch needs New Window navigation, reuse that setup in the opt-out test and
pass it to `MacScreenshotScenario.run(prepare: ...)` in the batch test.
Assert language-specific content for localized runs; launch defaults alone do
not establish the rendered language.

## Configuration and command

Put this example at `screenshots/capture.json`, replacing project/product/target
names, profiles and launch fixture inputs with the consuming app's values:

```json
{
  "projectRoot": "..",
  "platform": "macOS",
  "project": "App.xcodeproj",
  "scheme": "App",
  "buildConfiguration": "ScreenerScreenshots",
  "bundleID": "example.app.screenshots",
  "appProduct": "App.app",
  "testTarget": "AppUITests",
  "testClass": "AppScreenshotTests",
  "derivedData": ".build/DerivedData",
  "generate": ["xcodegen", "generate", "--spec", "project.screenshots.yml"],
  "commandPrefix": [],
  "locales": ["en-US"],
  "orientations": ["window"],
  "checkpoints": ["01-main", "02-details"],
  "windowPoints": [1280, 800],
  "nativeWindowPixels": [2560, 1600],
  "appearance": "light",
  "launchArguments": [],
  "launchEnvironment": {},
  "minimumFreeGiB": 5
}
```

These example dimensions require a native 2x display with enough visible space
for the whole 1280×800 point window. Use the actual backing scale and record it;
do not resize an encoded capture to satisfy a pixel target. The current runner's
build destination is Apple Silicon macOS. A different architecture needs an
explicit adapter change and its own validation.
`projectRoot` is relative to the config file; other project/build/output paths
are relative to that resolved root. Remove `generate` if no generator is used.
The example screenshot spec must define the configuration and add the app/test
sources and screenshot-only runner entitlements. Existing project/cache conventions
win; optional local config overrides may select an already established cache.
Each point/pixel profile and appearance is a separate invocation; locales iterate
within it. No Simulator runtime/device fields or `--simulator` option apply here.

```sh
python3 screenshots/tools/run_macos.py --config screenshots/capture.json
python3 screenshots/tools/run_macos.py --config screenshots/capture.json --skip-build
python3 screenshots/tools/run_macos.py --prepare-output screenshots/output/RUN
```

Build is the default; `--skip-build` requires the intended existing app/xctestrun
plan and does not include unbuilt edits. Once the process finishes, regenerate
the normal project if needed, e.g. `xcodegen generate --spec project.yml`; the
runner does not restore it. Ignore the `screenshots/output/` directory in Git.

The runner prints the successful gallery path. Under `screenshots/output/RUN`,
review `manifest.json` (`state: complete`), `metrics.json`, `review.html`, each
`<locale>-test-summary.json`/xcresult and `prepare.log`. Prepared system candidates
are `png/system/<locale>/window/<checkpoint>.png`; hierarchy comparisons are under
`png/screener/`. `raw/`, `traces/` and `collected/` preserve captured evidence.
Preparation-only recovery needs complete collection; partial scenarios need a
new capture run. The normal command does not upload any files to Apple.

The runner uses one shared DerivedData, refuses an active xcodebuild, checks the
isolated app bundle, records binary/tool/package identities and validates the fresh
xcresult summary. It rejects missing/repeated/reordered checkpoints, unclosed
traces, changed raw PNGs, and non-native window dimensions. Compilation and runtime
opt-in are separate gates. Add an opt-out test appropriate to the consuming app.

Build the macOS test runner with local ad hoc signing (`CODE_SIGN_IDENTITY=-`,
no development team), as the supplied runner does. `CODE_SIGNING_ALLOWED=NO`
can leave Xcode's copied runner with an invalid resource seal. Verify the resulting
runner with `codesign --verify --deep --strict` when debugging startup. A valid
signature alone does not establish that XCTest starts; retain startup failures
and diagnose developer/automation permissions separately.

### Host automation setup

Before a first UI run, check `DevToolsSecurity -status`. If developer mode is
disabled, explain the required host change and obtain authorization before
running `DevToolsSecurity -enable`; the user may need to confirm the administrator
dialog. XCTest can separately request **Enable UI Automation** even when developer
mode is already enabled. Let the user confirm that prompt, then retry; do not
enable unattended automation authentication as a workaround.

The supplied harness allows 16 checkpoints in one 180s session, 12s per eligibility
wait and 800ms stable geometry. The helper waits up to 20s for acknowledgements;
the runner's UI-test command timeout is 360s per locale. When diagnosis needs new
budgets, distinguish those limits from system startup/permission failures.

## Capture evidence

Screener captures the frame view enclosing `contentView` with explicit window
background completion, including the title bar. This public view relationship
is checked against the actual window size; AppKit hierarchy capture can still
differ from the compositor for materials. The separate XCTest window reference
must match the requested native dimensions exactly, including chrome.

### GPU limits

The supplied macOS adapter uses AppKit hierarchy capture, not compositor capture.
A separate Dreams pilot on 2026-10-12 found complete MTKView omission at all 14
checkpoints even though AppKit PNG geometry was correct. A consumer-local macOS
ScreenCaptureKit probe matched native system screenshot RGB pixels exactly at
1280×880, 2×, including production `framebufferOnly=true`. That probe is not
part of this runner. Screener main includes an optional macOS window-still
ScreenCaptureKit product; using it here requires an explicit adapter
integration and a fresh screenshot-runner validation. The BuildHunter batch uses
AppKit/XCTest; the Dreams probe does not establish this runner's GPU fidelity.

For Metal/RealityKit, examine the paired system PNGs for actual content. Do not use
AppKit images as a GPU oracle. A compositor backend needs explicit integration and
its own permission/readiness checks. RealityKit, HDR/EDR, protected content and
sustained capture have not been tested. Evidence is preserved in the Screener
repository under `docs/validation/metal-2026-10-12/` with the platform matrix at
`docs/capture-capabilities.md`.

No desktop crop, shadow removal, scaling, or ScreenCaptureKit recording is performed.
The batch still depends on macOS UI automation permissions. A timeout enabling
automation mode means the scenario may not have executed; inspect the fresh
xcresult and do not label a build as a successful UI run.

Review every chosen system PNG in the gallery. Synthetic fixture data and Debug
controls must be identified before selecting store assets. A valid PNG batch does
not establish App Store acceptance. See [validation](validation.md) for the exact
BuildHunter pilot matrix and observed limits.
