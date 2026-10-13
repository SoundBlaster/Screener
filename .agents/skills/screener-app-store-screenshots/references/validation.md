# Validation and reusable example

## Origin: PhotoCompressor

The app-specific pilot supplied the starting mechanics: one iPad Pro 13-inch M5
Simulator (iOS 27), English/Russian, portrait/landscapeLeft, four UI checkpoints
per orientation. It produced 16 Screener and 16 system PNGs at 2064×2752 /
2752×2064, 2× scale. The former were RGB16, the latter RGB8.
The final preparer supports both source depths and verifies decoded pixel equality
after opaque-alpha removal and EXIF normalization. The initial RGB8-only guard
failed; preparation-only recovery succeeded without repeating navigation.

Measured prior repeat phases: capture 166s and PNG preparation 53s (~219s combined).
The earlier interactive eight-frame iPad sequence spanned 19 minutes, 32 UI tool
calls and 23 execution calls. These are historical observations of unequal
workflows, not a controlled speedup or a model-token measurement.

## Portable tools

Run from the Screener repository:

```sh
python3 .agents/skills/screener-app-store-screenshots/scripts/test_tools.py
```

Thirteen focused tests cover installer SHA provenance, refusal to overwrite, all-target
preflight, path escape rejection, incomplete collection, trace closure/order,
checkpoint identity, missing stop acknowledgement, raw-capture mutation and
separate preparation metrics, macOS adapter selection, host-relative XCTest plan
paths and exact window/native geometry. Synthetic PNG headers exercise collection logic;
they do not replace ImageIO pixel verification or a Simulator integration run.

The skill frontmatter passes the Codex skill validator. These checks do not prove
that arbitrary app readiness adapters or screenshots are correct.

## Second consumer: CityChain

The reusable runner and both Swift adapters were copied into SwiftDecision-Examples
with the installer. App-specific additions are a SpecificationCore readiness rule,
main/Atlas presentation mapping, a real-button XCTest scenario, an offline route
fixture argument, and an isolated ScreenerScreenshots build configuration.
The linked ScreenerKit release is 0.1.0, revision
`fd6cc12f37c875ed57f62454318363cbf3de8705`.

The first build stopped at SpecificationCore macro trust (2.1.0, revision
`9b5fc40c16677e868856d0b24b70019cd5ea4687`). Specific target trust was approved
through Xcode with user authorization. No global macro-validation bypass was added.
Disk preflight also rejected retries until rebuildable compiler caches were cleared.
These environment costs belong in the first-integration total.

Initial app integration before the first build took about 9m23s (13:47:50–13:57:13
UTC on 2026-10-11); tool extraction and documentation work are separate.

The scoped Simulator run passed both tests (runtime opt-out and real screenshot
scenario), generating four UI states / eight paired PNGs: English, light,
portrait/landscapeLeft, main and Atlas sheet, iPad M5 at 2× native pixels.
All eight prepared images were reviewed in a contact sheet; a full-size system
Atlas screenshot was also inspected. UIKit sources were RGB16, system sources RGB8.

Successful build invocation: **291.787s**, including 192.810s build, 63.473s UI-test
command and 15.287s preparation. End to end from app integration start to the
first complete package: about 29m17s, including the environment repairs above.
Repeat with the same binary and matrix, no build: **87.564s**, including 55.579s
UI-test command and 13.812s preparation. Both tests passed again. The repeat
included a cold Simulator boot, install and shutdown. No interactive UI tool
calls were needed after launching it.

The ~70% difference between those two commands measures build reuse. It does not
establish a manual-versus-automation speedup. No model-token savings were measured.
Preparation-only recovery then completed in **12.873s**, rechecking raw hashes
and closed timelines without building or launching the app. Original capture
metrics were preserved byte-for-byte.

Full manifests/metrics and verification limits are in the consuming repository's
`screenshots/README.md` and `screenshots/validation/2026-10-11/`.

## Matched interactive experiment

A later single-pair comparison reused the same CityChain binary, fixture,
harness, collector and preparer, with four UI states/eight native PNGs and no
builds. Interactive agent navigation took **111.571s**, configured automation
**78.744s**: **32.827s / 29.42% less elapsed time**. Agent-visible nested tool
calls were **33 versus 2** (launch and completion collection for automation).
Internal CLI subprocesses are not model/tool round trips. This is an equipped
agent versus a ready XCTest scenario, not a human-speed benchmark or token bill.

The first interactive attempt failed because DeviceInteraction screenshotPath
encoded1× point dimensions; the successful rerun used native simctl screenshots.
The automated reference uses XCUIScreen, so compositor implementations differ.
An automated disk-preflight failure/cache cleanup is also recorded separately.
Both completed batches pass native geometry, trace and pixel-preserving preparation
checks; all16prepared images were inspected in a comparison contact sheet.
One pair, cache/order effects and different shutdown scheduling limit inference.

Detailed timings, failed attempts and identities: SwiftDecision-Examples
`screenshots/validation/2026-10-11/ab/README.md` in
[the consumer PR](https://github.com/SoundBlaster/SwiftDecision-Examples/pull/67).
No model-token or billed-cost savings were measured.

## macOS consumer: BuildHunter

### Historical startup failures

BuildHunter already had AppKit diagram tracing, Debug mock states and real XCTest
navigation. The macOS adapter reuses these with a dedicated screenshot configuration,
isolated app bundle, app-owned SpecificationCore readiness, explicit presentation
windows and paired AppKit/XCTest whole-window PNG checkpoints. Its existing SDK pin
`e447751afd8815de0ad1ec50ba2e4ca7c469d68e` remains unchanged. Checkpoint metadata is
stored in a marker because that SDK's `recordFrame` has no extra metadata parameter.

The app and both test bundles build on macOS 27.0 / Xcode 27.1. A cached rebuild
took 5.508s after the initial dependency compilation. The requested profile is
English/light, empty → results → diagram, 1280×800 points at native 2×.
The fresh UI invocation failed after 346.258s with **“The test runner hung before
establishing connection.”** No screenshot test case executed and no PNG batch was
produced. This is runner startup failure, not a product-scenario failure.
`DevToolsSecurity -status` reported
Developer mode disabled; the user was asked before any system permission change.
Treat that as an environment observation, not a proven sole cause.

Do not claim a successful macOS PNG batch, pixel fidelity, repeat-run time or
screen-recording-permission outcome until the fresh UI result and PNGs are reviewed.
The portable tooling checks do not substitute for that runtime evidence.

The 2026-10-13 retry rebuilt successfully (166.143s) but timed out before test
startup. The copied XCTest runner had an invalid resource seal with signing
disabled. The macOS tool now uses team-free local ad hoc signing; a fresh rebuild
(10.610s) passed signature verification. XCTest still reported **The test runner
hung before establishing connection** after 344.725s, with no screenshot scenario
executed and no PNG batch. Signing fixes a concrete defect but is not established
as the startup hang's cause. Developer mode was disabled for both runs; enabling
it was separately authorized for another diagnostic retry. Evidence is retained
in BuildHunter's screenshot worktree at `screenshots/validation/2026-10-13/`.

After the user enabled developer mode, two same-binary retries reached the runner's
`Running tests...` log, then failed initialization with **Timed out while enabling
automation mode** after approximately 60s. No scenario or PNG batch executed.
The system reports UI Automation disabled and authentication required; this is a
separate gate from developer mode. Unattended automation authentication was not
enabled. Those runs did not establish macOS batch runtime support.

### Verified batch and repeat (2026-10-13)

After the user completed XCTest's UI Automation prompt, both test bodies executed.
The real scenario exposed sandbox file-write failures. The screenshot UI-test target
now uses the copied entitlement template, scoped to its isolated app checkpoint cache
and normalized output root. The app sandbox is retained. Directory paths need leading
and trailing slashes, including home-relative paths.

The consumer opens its main window through File → New BuildHunter Window when a
relaunch has no windows, using the helper's app-owned `prepare` closure. It applies
the requested SwiftUI theme at the root through SpecificationCore policy. Earlier
geometry-valid batches with mixed light/dark rendering are preserved as intermediate
results, not relabelled as accepted light-theme evidence.

Final light batch `20261013T170307215242Z` passed both scoped UI tests and produced
three states / six native RGB8 opaque PNGs at 2560×1600, 1280×800 points, 2x:
empty → completed fixture results → separate diagram window. Preparation verified
decoded pixel equality, raw hashes and closed consecutive trace timelines.
Elapsed command time was **44.849s**, including an incremental build. A same-binary
buildless repeat `20261013T170459869382Z` passed again in **35.972s**, with another
six PNGs. These are local command timings, not a manual-versus-automation benchmark.

Full-size selected system PNGs were reviewed for the actual light theme, text,
window content and diagram. This is an English/light Apple Silicon macOS 27.0
fixture pilot; it does not establish dark/localized matrices, arbitrary apps,
Metal/RealityKit fidelity, normal-release runtime or Apple acceptance. The Debug
mock-state toolbar remains visible in the pilot images.
Metrics, manifests, summaries, source hashes and PNG evidence are retained in
BuildHunter `screenshots/validation/2026-10-13/`.
After restoring the ordinary project, its Debug app build passed using the same
DerivedData. The remaining stale Rust-library path warning is documented in the
consumer report; normal runtime and Release behavior were not checked.

## SDK scope

This change adds skill/plugin resources and a consumer example. No ScreenerCore or
ScreenerKit API change is needed: awaited frame recording and stop/drain already
exist. A future SDK-level checkpoint API or Simulator backend may reduce adapters,
but neither is required for this first implementation.

No automatic Duo unfolding, physical-device screenshot run, Apple upload or
App Store acceptance was verified by this portable pilot. UIKit and compositor
references remain distinct. Geometry settling does not establish complete map tiles.
