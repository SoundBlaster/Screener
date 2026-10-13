# Screener documentation

Screener has DocC catalogs for `ScreenerKit`, `ScreenerCore`, and `ScreenerMCP`.
ScreenerKit is the entry point, with a three-step tutorial and articles covering
capture, backend limits, export, and agent inspection.

## Capture evidence

- [Platform/backend capability matrix and GPU limits](capture-capabilities.md).
- [Historical Dreams Metal comparison](validation/metal-2026-10-12/README.md).
- [Packaged backend validation and source identities](validation/packaged-backend-2026-10-12/README.md).

## Build locally

With Xcode and Swift 6.1 or later selected:

```sh
python3 .github/scripts/build_documentation.py
python3 .github/scripts/validate_documentation.py
```

The build treats DocC warnings as errors. It generates two static sites beneath
`.build/docc-site`, including tutorial code diffs and API reference:

- `/Screener/`: iOS symbols, including UIKit capture.
- `/Screener/macos/`: macOS symbols, including AppKit capture.

Both sites contain ScreenerKit, ScreenerCore and ScreenerMCP. The macOS site
also includes the optional ScreenerScreenCaptureKit product and its window-still API. Conditional APIs reflect their build SDK;
for example, ScreenCaptureKitSession needs an iOS 27 SDK and is excluded from
Simulator symbol graphs. The tutorial's code is for iOS, including when viewed
in the macOS documentation.

To preview the static output with the same URL prefix as Pages:

```sh
mkdir -p .build/docc-preview
ln -sfn ../docc-site .build/docc-preview/Screener
python3 -m http.server 8000 --directory .build/docc-preview
```

Open `http://localhost:8000/Screener/` or its `macos/` subdirectory.

## CI check selection

Both workflows first inspect the complete Git diff on a small Linux runner.
They keep their existing check names and skip irrelevant jobs with job conditions,
so a prose-only PR does not wait for a macOS runner or Simulator startup.

| Changed inputs | Checks selected |
| --- | --- |
| README, skill instructions/UI metadata, images, historical evidence | No builds or tests; only changed-path selection. |
| Screenshot skill scripts and non-image adapter assets | Screenshot tool checks on Linux. |
| `Sources/**/Documentation.docc/**`, including tutorial snapshots | DocC build, tutorial validation and preview. |
| SDK/package inputs, `Tests/` or `Examples/` | Swift/package/Simulator/fixture checks and DocC. |
| CI files or an unclassified path | All checks. |

The selector uses PR merge-base-to-head or push-before-to-after changes and includes
deleted paths and both sides of renames. Missing diff inputs conservatively select
all checks; a failed selection job makes dependent checks fail rather than silently
accepting a skipped build. Manual workflow dispatch also selects the full pipeline.
No top-level path filter suppresses a required check. See GitHub's
[job condition behavior](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions).

The selector is `.github/scripts/ci_changes.py`, shared through
`.github/workflows/changes.yml`. When adding a new build input, keep the conservative
default or classify it explicitly. Changes to these CI rules run the full pipeline
once; subsequent prose/image-only changes skip its expensive jobs.

## GitHub Pages

For relevant changes, the documentation workflow builds both sites on pull requests and uploads a preview
artifact as a tar.gz archive (DocC symbol filenames can contain colons).
Only the default branch can deploy. Configure repository Pages settings
to use **GitHub Actions** before the first deployment.

After deployment, the expected entry URLs are
`https://soundblaster.github.io/Screener/` and
`https://soundblaster.github.io/Screener/macos/`.
A successful PR build alone does not establish that either URL is live.

## Swift Package Index

The root `.spi.yml` requests iOS documentation for ScreenerKit and macOS SwiftPM
documentation for ScreenerCore, ScreenerMCP and ScreenerScreenCaptureKit. This keeps the SDK's UIKit reference
available in the Index while generating the reader modules on their host platform.
The separate Pages site also provides ScreenerKit's AppKit reference.

The package still needs to be submitted through
[Add a Package](https://swiftpackageindex.com/add-a-package).
The repository URL is `https://github.com/SoundBlaster/Screener.git`.
The v0.2.0 release includes the iOS/macOS catalogs and examples added after v0.1.0.
Later documentation changes remain on the default branch until another release.
Do not move the existing v0.1.0 tag.

Follow [SPIManifest's documentation configuration](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Documentation.docc/CommonUseCases.md)
and validate `.spi.yml` with the [official validator](https://swiftpackageindex.com/validate-spi-manifest).
Add compatibility badges only once the package has actually been indexed.
