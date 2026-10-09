# UIKit scale and materials — 2026-10-09

## Scope and outcome

The PhotoCompressor pilot used 402×874px, scale 1 window captures where the simulator
screenshot was 1206×2622px. Its baseline remains unchanged. This follow-up uses
Screener's synthetic [UIKit fixture](../../../Examples/UIKitCaptureFixture/README.md),
not a rebuilt PhotoCompressor.

On iPhone 17 Simulator, iOS 27.0 (24A434), the actual source window reports
`window.window == nil` and `traitCollection.displayScale == 3`. Reading the latter
fixes captures to **1206×2622px / scale 3**, recorded in both the image and trace
metadata. The rendering path remains `drawHierarchy(afterScreenUpdates: true)`.
This is display rendering scale, not `UIScreen.nativeScale` resampling.

**Glass fidelity remains unresolved.** At the corrected scale, the glass panel and
native menu still show stronger, sharper backdrop stripes than the independent
system screenshot. Standard `UIBlurEffect.systemMaterial` closely matches in this
specific fixture. Neither result establishes all-material or physical-device fidelity.

## Evidence

| State | UIKit adapter | Independent simctl screenshot |
|---|---|---|
| Materials | [PNG](materials-adapter.png) | [PNG](materials-system.png) |
| Settled native Save menu | [PNG](menu-adapter.png) | [PNG](menu-system.png) |

Both paths use 1206×2622 images. Captures were taken sequentially while each UI state
remained static. The agent opened the menu using its hierarchy hit point and verified
Share/Photos/Files, then dismissed it and closed the device interaction session.
No export was triggered. System status bar/home indicator are outside window capture.

The adapter PNGs carry Display P3 profiles; system screenshots declare sRGB. The
[comparison script](../../../Examples/UIKitCaptureFixture/compare.py) converts both
to sRGB in memory before measuring rectangular regions, including material edges
and labels. [Exact regions and results](comparison.json):

| Region | Mean absolute RGB difference (0–255) | Pixels with any channel difference >10 |
|---|---:|---:|
| Control stripes | 0.00 | 0.00% |
| Standard blur | 0.26 | 0.00% |
| Glass panel | 24.33 | 95.96% |
| System menu | 21.98 | 88.67% |

These measurements describe this capture pair; they are not CI fidelity thresholds.
Geometry agrees, while glass backdrop rendering differs. No layer-render fallback,
private API, or synthetic blur correction was introduced.

## Verification

- `swift test`: 29 macOS tests passed (9 Core, 9 Kit, 11 MCP).
- App-hosted UIKit tests: 3 tests / 5 cases passed, 0 failures or skips, verified
  from the fresh [xcresult summary](tests.json). Covers a visible scene window,
  scales 1/2/3, scale changes between captures, and empty bounds.
- Fixture built and ran on Simulator; physical devices were not used.
- Local full logs and `.xcresult` remain in `.build/validation` in the task worktree.
- The 52-frame trace `22C39A14-5AF3-4599-961F-3D2963CC00A2` is retained locally in
  `.build/validation/traces`. The subsequent test launch interrupted recording
  before its scheduled end; no `sessionEnded` claim is made for this trace.
- The real stdio MCP server returned sessions, the full timeline, all three contact
  sheet pages, and a full frame. [Reader identity](mcp-reader-identity.json) identifies
  the existing macOS binary; its build revision is unknown. This is MCP readback,
  not a claim about Codex registration. [Trace metadata and file hashes](identity.json)
  bind the evidence; full responses remain in `.build/validation/mcp`.

Initial dependency resolution hit disk exhaustion. Only this task's generated
build caches were removed, then existing dependency checkouts were reused. Initial
test setup also needed a visible scene window and `updateTraitsIfNeeded()` after
overrides; the final tests above include those corrections.

## Next validation

Pin PhotoCompressor to the reviewed fix and repeat its unchanged Save scenario.
Keep system screenshots/video as the material-fidelity reference until a separate
capture backend is proven to reproduce glass accurately. Native-scale PNGs contain
nine times as many pixels as 1x on this device; recording cost needs measurement
before claiming the original capture cadence is preserved.
