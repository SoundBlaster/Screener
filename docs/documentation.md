# Screener documentation

Screener has DocC catalogs for `ScreenerKit`, `ScreenerCore`, and `ScreenerMCP`.
ScreenerKit is the entry point, with a three-step tutorial and articles covering
capture, backend limits, export, and agent inspection.

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

Both sites contain all three modules. Conditional APIs reflect their build SDK;
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

## GitHub Pages

The documentation workflow builds both sites on pull requests and uploads a preview
artifact as a tar.gz archive (DocC symbol filenames can contain colons).
Only the default branch can deploy. Configure repository Pages settings
to use **GitHub Actions** before the first deployment.

After deployment, the expected entry URLs are
`https://soundblaster.github.io/Screener/` and
`https://soundblaster.github.io/Screener/macos/`.
A successful PR build alone does not establish that either URL is live.

## Swift Package Index

The root `.spi.yml` requests iOS documentation for ScreenerKit and macOS SwiftPM
documentation for ScreenerCore and ScreenerMCP. This keeps the SDK's UIKit reference
available in the Index while generating the reader modules on their host platform.
The separate Pages site also provides ScreenerKit's AppKit reference.

The package still needs to be submitted through
[Add a Package](https://swiftpackageindex.com/add-a-package).
The repository URL is `https://github.com/SoundBlaster/Screener.git`.
Documentation added after v0.1.0 becomes available on the default branch after
merge; a new tagged release is needed for these catalogs to accompany a release.
Do not move the existing v0.1.0 tag.

Follow [SPIManifest's documentation configuration](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Documentation.docc/CommonUseCases.md)
and validate `.spi.yml` with the [official validator](https://swiftpackageindex.com/validate-spi-manifest).
Add compatibility badges only once the package has actually been indexed.
