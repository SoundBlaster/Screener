# UIImage missing-backing review fix

2026-10-12, [PR #16 discussion](https://github.com/SoundBlaster/Screener/pull/16#discussion_r4251242529).

## Contract and change

`CapturedImage(uiImage:)` promises SDR sRGB rasterization of a renderable UIImage.
The old guard required CGImage or CIImage backing, leaving draw-only representations
unsupported. The new fallback uses UIGraphicsImageRenderer with the source's size,
scale, transparent background and standard range, then converts to sRGB. UIKit
already applies orientation while drawing; the resulting raster is treated as up.
Finite positive size/scale are checked before creating the renderer. The existing
CG/CI path and public signature are unchanged.

## Runtime evidence

The app-hosted UIKit suite passed on **iOS 27.0 Simulator / iPhone Air**:
**7 test functions, 9 cases**, zero failures/skips. Source identities and original
result-bundle location: [identity.json](identity.json); exported [summary](summary.json)
and [test tree](tests.json).

New cases check a drawable UIImage with both backing properties nil (80×48 at 2×,
nonempty alpha), a real SF Symbol, a bitmap rotated right at scale 2 (8×12), and
an empty UIImage throwing invalidImage before renderer startup. Existing view/window
scale and empty-view cases also pass.

The first attempt assumed that star.fill would lack backing. On this runtime it
exposes a 56×54 grayscale CGImage, so that fixture assumption failed. A deterministic
draw-only UIImage subclass now covers the missing-backing boundary; the real SF
Symbol remains a positive case. Its fixture is immutable and drawing runs on MainActor.
The initial failed result bundle was preserved separately, not relabelled as passing.

Command from the SDK repository (regenerate the existing project with XcodeGen):

```sh
rtk proxy xcodegen generate --spec Examples/UIKitCaptureFixture/project.yml
rtk proxy xcodebuild test -quiet \
  -project Examples/UIKitCaptureFixture/UIKitCaptureFixture.xcodeproj \
  -scheme UIKitCaptureFixture \
  -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_UDID' \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/DerivedData/SourcePackages \
  -resultBundlePath /absolute/new-result.xcresult \
  -only-testing:UIKitCaptureFixtureTests/UIKitCaptureTests
```

The generated project and a single DerivedData are reused. The task-owned simulator
was removed after recording results. Original result bundles remain outside the cache.

## Limits and environment

The test link reported SDK XCTest/Testing minimum-OS warnings (test framework 17,
fixture deployment 16), and Xcode logged invalidDigitCount for the SDK build number.
The fresh result summary reports Passed and zero runtime warnings. These toolchain
messages are not evidence that the assertions were skipped; the test tree names them.

After the successful run, a further command hit ENOSPC. Only regenerable compiler
cache directories were removed; the successful result and native Metal evidence
were preserved. No success is attributed to that failed follow-up command.

The historical Metal reports remain bound to their older full-source hashes;
macOS backend/raw converter code is unchanged by this UIKit-only fix. Physical
devices, other iOS releases, every vector representation and HDR are not covered.
