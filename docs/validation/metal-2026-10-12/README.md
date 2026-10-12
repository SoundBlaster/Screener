# Dreams: Screener / Metal capture boundary

Local pilot, 2026-10-12. Branch `codex/screener-metal-pilot`, base `c55774a`.
Exact source hashes, SDK pin and environment: [identity.json](identity.json).
This is a preserved consumer experiment, not a Screener SDK integration test.
The evidence below was copied from Dreams without changing measurements or images.

## Finding

**Screener 0.1.0 AppKitCaptureSource captures the AppKit label and background,
but omits the entire MTKView image in this fixture.** The result looks like a valid
window screenshot, so checking dimensions or PNG existence alone misses the failure.

An experimental macOS ScreenCaptureKit capture, recorded through Screener's existing
`recordFrame`, preserves the Metal surface. All **14 checkpoints** match the native
`screencapture -l <windowID>` RGB pixels exactly: MAE 0, maximum difference 0,
100% exact pixels, **1280 × 880 at 2×**. No images were resized for measurement.

![AppKit omits Metal; ScreenCaptureKit preserves it](comparison.png)

| Profile | Checkpoints | Result |
| --- | ---: | --- |
| Transparent, first run | 2 | AppKit omits Metal; SCK matches system |
| Transparent, repeat | 2 | Same result; repeated fixed screenshot is identical |
| Opaque black surface | 2 | Same result |
| Live renderer between checkpoints | 6 | Increasing frame count and changing Metal pixels; same capture result |
| Production `framebufferOnly=true` | 2 | Same result without GPU readback |

AppKit's Metal-region color variance is zero in every checkpoint; the system
comparator contains the glyphs and glow. Live checkpoints hold the renderer paused
while taking both screenshots: advancing frames must not be mistaken for capture
error. Frame counts before/after capture agree; actual rendering resumes between
checkpoints. This is not a continuous 30 fps recording test.

## Reproduce

The probe lives in the Dreams worktree
`/Users/egor/Development/GitHub/.worktrees/Dreams-metal-pilot`, branch
`codex/screener-metal-pilot`. Run there (not in the Screener checkout):

```sh
rtk proxy make capture-metal-pilot
# Optional pixel analysis, using Python with Pillow and numpy:
rtk proxy /Users/egor/Development/GitHub/Dreams/.venv/bin/python \
  scripts/analyze-metal-pilot.py artifacts/metal-pilot/<run-directory>
```

The first command builds the opt-in executable, launches/closes the fixture window
five times and saves native PNGs, completed `.vtrace` bundles, manifests and timings.
Use `python3 scripts/metal-capture-pilot.py --skip-build` only while the cached
binary is still the pilot build; the wrapper rejects a normal cached binary.

The fixture uses the actual RainRenderer/MatrixRain implementation, fixed seeded
simulation, an isolated empty feed and a blue AppKit background. Instrumentation is
compiled only with `DREAMS_METAL_PILOT=1` in the package environment and runs only
with `--capture-metal-pilot`. Screener remains a test-only dependency for normal
Dreams builds. The ordinary release configuration also compiled successfully
(7.91s), without the pilot flag. No application settings, hooks or TCC grants changed.
The original `feature/tvos-clock` checkout remained clean.

## Evidence

- [Pixel measurements and native PNG hashes](analysis.json).
- [Build, run timings and executable identity](run.json).
- Per-profile manifests and complete timelines are saved beside this document.
- Native originals and full traces remain under the absolute run path in identity.json.
- The production-surface trace was copied unchanged into the standard Screener
  catalog and inspected using MCP sessions → timeline → contact sheet → full frame:
  `3CF9C0C9-FA04-4FF0-B247-25275F39FA69` (four keyframes plus start/end).

Capture-call samples here: AppKit approximately 1.4–4.6ms; ScreenCaptureKit
approximately 28–39ms after the first call, first calls approximately 70–81ms.
These are a small local sample, not a performance budget or CPU/GPU benchmark.
All five runs excluding compilation took about 14.4s; see exact values in run.json.

## SDK implication and limits

The pinned Screener SDK's ScreenCaptureKitSession is conditional on physical iOS;
there is no macOS ScreenCaptureKit adapter in that version. This pilot calls Apple's
[SCScreenshotManager](https://developer.apple.com/documentation/ScreenCaptureKit/SCScreenshotManager/captureImage(contentFilter:configuration:completionHandler:))
directly and feeds the result into Screener. It does not implement or release a new
Screener SDK backend.

Screen recording permission was already available to this process. The fixture
checks `CGPreflightScreenCaptureAccess` and records a skip if absent; it never
requests permission or captures the desktop. Capture targets only its own window.
Existing permission does not prove a permission-free workflow for another host/app.

GPU reference images are diagnostic readbacks of the actual drawable. The readback
profiles temporarily use `framebufferOnly=false`; the final production-surface
profile proves the capture finding also holds with `true`. Transparent raw GPU
pixels do not include the AppKit background, so they are not used as the pixel
equality comparator for the composed window.

Both system screenshot and SCK observe the compositor; they may share internal
implementation. Equality establishes agreement with the system screenshot here,
not an independent colorimetric proof. HDR/EDR, sustained capture, CPU/GPU load,
occlusion, multiple displays, resolution changes and RealityKit remain unchecked.
No CI, App Store asset acceptance or release validation was performed.

See the [capture capability matrix](../../capture-capabilities.md) for platform
routing. A macOS Screener backend and an Oracle/RealityKit pilot remain future work.
