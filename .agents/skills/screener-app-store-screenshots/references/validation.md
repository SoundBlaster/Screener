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

Nine focused tests cover installer SHA provenance, refusal to overwrite, all-target
preflight, path escape rejection, incomplete collection, trace closure/order,
checkpoint identity, missing stop acknowledgement, raw-capture mutation and
separate preparation metrics. Synthetic PNG headers exercise collection logic;
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

## SDK scope

This change adds skill/plugin resources and a consumer example. No ScreenerCore or
ScreenerKit API change is needed: awaited frame recording and stop/drain already
exist. A future SDK-level checkpoint API or Simulator backend may reduce adapters,
but neither is required for this first implementation.

No automatic Duo unfolding, physical-device screenshot run, Apple upload or
App Store acceptance was verified by this portable pilot. UIKit and compositor
references remain distinct. Geometry settling does not establish complete map tiles.
