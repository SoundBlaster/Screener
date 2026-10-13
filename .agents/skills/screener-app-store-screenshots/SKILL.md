---
name: screener-app-store-screenshots
description: Integrate and run repeatable native iOS Simulator or macOS window screenshot batches using real XCTest navigation and flag-gated Screener checkpoints. Use for App Store screenshot automation, localized device/window matrices, PNG collection, or repeated layout capture.
---

# Screener App Store screenshots

![App Store screenshot workflow: prepare, capture, review](assets/hero-app-store-screenshots.png)

Deliver a repeatable local screenshot command and a labelled review gallery.
Use the bundled runner/adapters rather than rebuilding orchestration in each chat.
The first integration changes the consuming app; later runs reuse its scenario.

Choose the platform adapter before installing: the default UIKit/Simulator runner
uses device orientations; [macOS window capture](references/macos.md) uses AppKit,
explicit window queries and a fixed point/pixel profile. Both reuse collection,
pixel-preserving preparation and the review gallery. Do not substitute a desktop
screenshot for an explicitly selected macOS window.

## Establish scope

Inspect the app's instructions, project generator, scheme, package pin, fixture path,
UI-test target and existing accessibility identifiers. Choose actual screens, languages,
orientations and a Simulator profile with known native pixels. A configured profile
is not evidence that it was checked. Preserve existing source, icons and user simulators.

Keep app instrumentation behind `SCREENER_SCREENSHOTS` in an explicit build configuration,
plus runtime opt-in and a valid run UUID; the UIKit adapter also requires Simulator.
Use an isolated bundle identifier.
The normal app must remain unaffected. Debug-based configuration is appropriate when
using an existing Debug fixture; identify it honestly when selecting store assets.

## Integrate once

Read [integration](references/integration.md) for configuration and API details.
Run `scripts/install.py` with the consuming root and app/test source directories;
it copies the runner, PNG preparer and Swift adapters without overwriting files.
Record the ScreenerKit revision actually linked into the app. The plugin reader
and the app SDK can be different versions.

Add the app-owned readiness policy, presentation mapping, fixture setup and a short
XCTest scenario that uses `ScreenshotScenario.run` and named checkpoints. Keep product
policy in the consuming app's existing policy framework. `ScreenshotProbe` accepts
its Boolean result and presentation; it does not infer whether arbitrary app content
is ready. Add the source files/dependency/configuration through the project tooling.

The scenario must operate real controls. Assert the desired screen and language before
capturing; fixture injection is not evidence that the picker/import UI was exercised.
Do not fabricate entitlements or invoke billable providers to populate screenshots.

## Run and recover

Use the copied runner with the app's configuration. Build is the default;
`--skip-build` explicitly reuses an existing binary whose hash is recorded.
Use one project/DerivedData per consuming repository and serialize builds. The runner
rejects an already active `xcodebuild`; its lock does not control a GUI build started later.
Pass `--simulator <UDID>` only for a deliberately selected matching device. Otherwise the
runner reuses or creates its owned simulator. It never erases one.

Run asynchronously and wait on the actual process rather than issuing repeated screenshot
or status tool calls. Preserve failure logs and partial traces. Once collection is complete,
`--prepare-output <run>` can regenerate PNGs/gallery without repeating UI navigation;
it verifies raw hashes and closed trace timelines again.

## Inspect and report

Inspect `manifest.json`, `metrics.json`, XCTest results and `review.html`, then view the
actual selected PNGs. Require requested checkpoint count/order, unique orientations,
closed consecutive timelines, native dimensions and decoded pixel-preserving preparation.
The preparer preserves RGB8/RGB16 depth, source color space and raw files, applies EXIF
rotation without resizing, and rejects nonopaque pixels.

The adapters capture **both** Screener view-hierarchy and XCTest system reference PNGs.
UIKit omits system status chrome; UIKit/AppKit may differ for glass/compositor effects. Select and
review the system images for App Store use; native resolution alone does not establish
fidelity or Apple acceptance. For Metal/RealityKit, inspect actual GPU content: the Dreams pilot found complete
MTKView omission in AppKit despite valid native dimensions. Read the macOS guide's
GPU limits; no universal GPU fidelity is established. Neither Simulator backend
requires screen-recording consent.
The macOS window pilot uses XCTest automation rather than a ScreenCaptureKit recording
session; macOS automation permissions must still be available.
For physical-device traces, use the separate `screener-visual-trace` workflow.

Report the actual profile/theme/language/orientation matrix, binary/fixture/tool identities,
test outcomes, failures/recovery and unchecked screens. Separate integration cost from
repeat-run cost. Use per-operation timings; agent token/tool usage requires separate session
accounting and cannot be inferred from Screener frames. Apple upload is a separate action.

## Scope of the supplied adapters

The bundled UIKit/SwiftUI + XCTest adapters support portrait and landscapeLeft, paired
capture, 800ms geometry settling, a 12s eligibility wait, 180s session and 16 checkpoints
per orientation. Adapt these local budgets when justified; they are not SDK-wide promises.
Readiness/geometry do not prove map tiles, network content or every animation settled.
Automatic Duo unfolding, physical capture and App Store upload are outside this runner.
The macOS adapter uses a fixed whole-window frame, the window's own backing scale,
and app-owned readiness for each registered presentation. See its platform guide
for desktop fit, sandbox path handoff and window chrome limitations.

See [validation and reusable-example evidence](references/validation.md) for what was actually exercised.
