# Roadmap after 0.2.0

Status: Proposed implementation plan; all items below are unimplemented.
Reviewed: 2026-10-18.
Source baseline: [0.2.0](https://github.com/SoundBlaster/Screener/releases/tag/v0.2.0),
commit `085252854d22dcc344d494d38496b402a92b308f`.

This roadmap turns source-reviewed gaps into bounded implementation slices.
It proposes order and acceptance criteria, not release dates or new accepted
API contracts. The [PRD](PRD.md) describes the broader product direction;
[capture capabilities](capture-capabilities.md) and the consumer validation
records remain the evidence for actual platform behavior.

## Starting point

- The SDK records explicit semantic markers and supplied frames. The physical
  iOS ScreenCaptureKit session also has its own bounded frame handoff; this does
  not provide adaptive recording for the ordinary UIKit/AppKit paths.
- MCP exposes sessions, timeline, frame and contact sheet. Timeline selection
  uses offset/limit, without time/marker filters or a visual-diff tool.
- Screenshot runners produce paired native images and a review gallery.
  Locales/orientations iterate inside a configured device/window profile;
  preparation can resume after complete collection, but capture cells cannot.
- The installer copies assets with SHA provenance and refuses overwrites.
- An optional macOS compositor module exists; the macOS screenshot harness
  still uses AppKit hierarchy capture.

## Delivery order

Sizes are relative planning estimates, not measured effort or commitments.
Dependencies apply to the minimal slice, not every future enhancement.

| Phase | ID | Outcome | Size | Dependency |
| --- | --- | --- | --- | --- |
| A: repeatable operation | RM-01 | Diagnose integration before expensive work | S | None |
| A: repeatable operation | RM-02 | Run and resume a device/theme/language matrix | M | None; reuse RM-01 diagnostics when available |
| A: integration maintenance | RM-03 | Update copied tools without losing consumer edits | M | None |
| B: visual investigation | RM-04 | Compare frames and review screenshot baselines | M | None |
| B: visual investigation | RM-05 | Query frames around a time or semantic event | S–M | None; composes with RM-04 |
| B: backend coverage | RM-06 | Select compositor capture in macOS screenshot batches | M | Existing macOS SCK product |
| C: bounded recording | RM-07 | Enforce storage budgets and safe cleanup | M | None; required before RM-08 |
| C: bounded recording | RM-08 | Record useful visual changes adaptively | L | RM-07; reuse RM-04 metric primitives where appropriate |

Start with RM-01, then RM-02. RM-03 can follow independently when another
consumer needs an adapter upgrade. RM-04 is the next user-facing analysis feature;
RM-05 and RM-06 can then proceed independently. Complete RM-07 before enabling
the longer-running automatic recording in RM-08.

## RM-01 — Integration diagnostics (`doctor`)

**Gap:** checks for disk headroom and an active build exist, but diagnosis of
SDK pins, build configuration, runner signing and automation permissions is manual.
See the [macOS runner](../.agents/skills/screener-app-store-screenshots/scripts/run_macos.py)
and [MCP command](../Sources/screener-mcp/main.swift).

**Minimal slice:** a diagnostic entry point for an existing capture config.
Check selected project/scheme/configuration, installed runtime or window profile,
existing bundle identity, linked SDK identity, cache/output locations and relevant
host permissions. Command names and output schema need an implementation contract.

**Done when:**

- Human-readable output and structured results distinguish ready, unavailable
  and unknown; each blocker identifies a concrete next action.
- Available existing products can be checked without starting a capture run.
- Diagnosis does not build, install, change permissions or modify the project.
  Missing build products are reported as such rather than treated as a pass.
- The consuming repository's selected build/cache location is respected;
  no fallback cache is created as a diagnostic side effect.
- Simulator runtime mismatch, malformed runner signature, missing macOS UI
  Automation approval and unsupported SDK API are distinct outcomes.

## RM-02 — Capture matrix and cell-level resume

**Gap:** [run.py](../.agents/skills/screener-app-store-screenshots/scripts/run.py)
and [run_macos.py](../.agents/skills/screener-app-store-screenshots/scripts/run_macos.py)
operate on one device/window profile and appearance per invocation. Recovery
only regenerates prepared PNGs after collection has completed.

**Minimal slice:** one plan expands profiles, appearances, locales and orientations
into named capture cells, with an aggregate manifest and review gallery. Reuse
the existing platform runners and their evidence checks.

**Done when:**

- Each cell reports pending, running, verified or failed independently.
- Resume reuses a verified cell only when its configuration, binary, fixture
  and tool identities still match that cell's inputs.
- Failed cells rerun from a known app/fixture state. Resume does not promise to
  continue an arbitrary UI test from its last interaction.
- An incomplete/unclosed trace never becomes a successful cell. Failure and
  recovery records remain distinguishable.
- Shared builds and capture on one host remain serialized; incompatible build
  configurations do not accidentally reuse one another's products.
- The summary identifies missing cells and links each selected PNG to its cell.

## RM-03 — Versioned adapter updates

**Gap:** [install.py](../.agents/skills/screener-app-store-screenshots/scripts/install.py)
supports initial installation and refuses existing destinations, so fixes must
be synchronized across consuming apps manually.

**Minimal slice:** inspect installed provenance against a selected skill revision
and produce an update plan. Apply updates to unchanged copied files only after
an explicit update action; report locally modified files separately.

**Done when:**

- The plan shows old installed identity, current consumer hash and proposed
  source identity, including mixed-version or missing files.
- Dry-run leaves consumer files and provenance unchanged.
- Unmodified copies can be updated; local edits are preserved and surfaced for
  review. Missing baseline contents do not produce a fabricated merge.
- App-owned readiness rules and navigation scenarios stay outside automatic
  replacement. Updated provenance describes the actual resulting files.
- A failed update cannot leave new provenance claiming a fully applied version.

## RM-04 — Visual diff and approved baselines

**Gap:** the gallery supports manual inspection, while the
[MCP server](../Sources/ScreenerMCP/ScreenerMCPServer.swift) has no diff tool.

**Minimal slice:** a deterministic comparison primitive shared by read-only MCP
frame comparison and screenshot-batch comparison. Return metrics, an overlay/diff
image and changed-region information. Add explicit masks for known dynamic regions.

**Done when:**

- Inputs retain original pixels and hashes; derived comparisons are separate
  artifacts and identify both input frames, masks and comparison settings.
- Geometry, scale and color handling are explicit. Incompatible profiles are
  reported instead of silently resized into a misleading comparison.
- Identical inputs have a stable result; masks exclude only their declared regions.
- A comparison report can be reviewed against an explicitly selected baseline.
  Baseline acceptance requires an explicit local action and is not an MCP mutation.
- Metric thresholds support review and regression detection; they do not assert
  semantic UI correctness, compositor fidelity or App Store acceptance.

## RM-05 — Time and marker queries

**Gap:** [TraceCatalog](../Sources/ScreenerMCP/TraceCatalog.swift) paginates records
and frames by offset, requiring agents to scan pages to locate an event.

**Minimal slice:** bounded queries by time interval and marker name, including
frames immediately before/after a selected marker. Reuse these selections for
timeline, contact sheet and frame-pair comparison.

**Done when:**

- Existing offset-based callers remain supported.
- Time domain, inclusive/exclusive boundaries and repeated marker selection are
  defined; ambiguous event names do not silently select an arbitrary occurrence.
- Missing surrounding frames and an active/incomplete session are reported.
- Ordering, pagination and cell-to-frame mapping remain deterministic.
- A consumer scenario can locate and compare frames around a named UI event
  without downloading every full-resolution frame in the session.

## RM-06 — Compositor capture in the macOS screenshot runner

**Gap:** the [macOS harness](../.agents/skills/screener-app-store-screenshots/assets/ScreenshotHarnessMac.swift)
uses AppKit even though
[ScreenCaptureKitWindowSource](../Sources/ScreenerScreenCaptureKit/ScreenCaptureKitWindowSource.swift)
already supplies compositor stills. Hierarchy capture omitted MTKView in the
recorded Dreams pilot.

**Minimal slice:** explicit backend selection with a consumer-supplied capture
boundary. Wire the existing compositor source through public frame ingestion;
retain the separate system reference and accurate source labels.

**Done when:**

- Capture area is agreed first: the current profile covers the whole window,
  including chrome. A backend must match the declared area or require a distinct
  profile; implicit cropping/resampling cannot conceal a mismatch.
- Window/owner identity, native geometry and backend provenance survive collection.
- Missing Screen Recording access is actionable; no silent desktop/hierarchy fallback
  or automatic permission change occurs.
- The current hierarchy path remains available to consumers that do not select
  the optional compositor backend.
- Fresh runner evidence includes a matched native Dreams Metal case. RealityKit,
  HDR/EDR and other GPU surfaces keep independent coverage/unknown status.

## RM-07 — Retention and storage controls

**Gap:** [Screener](../Sources/ScreenerKit/Screener.swift) and
[TraceBundleWriter](../Sources/ScreenerCore/TraceBundleWriter.swift) expose no
trace age/byte budget or public cleanup policy.

**Minimal slice:** app-configurable budgets, usage reporting and explicit cleanup
within recorder-owned storage. Define active writer/export/reader protection
before automatic deletion is enabled.

**Done when:**

- Limits and deletion order are observable and configurable.
- Cleanup only targets owned completed sessions; active/protected sessions and
  unrelated files remain untouched.
- Reaching a budget produces explicit admission/degradation results. Disk-full
  failures do not become successful frame records or crash the host app.
- Image loss and best-effort semantic recording are distinguishable; no promise
  to persist markers is made when storage cannot accept any writes.
- Bounded behavior is demonstrated under a representative long recording and
  concurrent reads/exports before RM-08 depends on it.

## RM-08 — Adaptive flight recorder

**Gap:** the ordinary UIKit/AppKit integration supplies frames explicitly.
The [recorder](../Sources/ScreenerKit/Screener.swift) serializes writes but does
not implement heartbeat sampling, visual-change selection or settled keyframes.

**Minimal slice:** opt-in low-rate thumbnails, bounded bursts around semantic
events and keyframes after significant change or stable end states.

**Done when:**

- Capture/encode queues have explicit bounds, coalescing and observable drop counts.
- Geometry/scene changes reset comparison context; frames from unrelated windows
  are not used as one visual-delta sequence.
- Storage uses RM-07 budgets; semantic markers have a defined priority distinct
  from optional image samples.
- Existing explicit capture APIs remain useful and tracing can be disabled.
- A delayed-image layout-change fixture can be investigated from its recorded
  history without another reproduction.
- Main-actor capture cost, queue/memory peak, bytes per minute and dropped samples
  are measured on declared consumer profiles. Budgets are evidence-based,
  not guarantees inferred from native PNG dimensions.

## Completion and evidence

Each item needs its own reviewed contract, implementation and source-bound
validation before its status changes to complete. Additive CLI/API examples here
are proposed interfaces, not commands already available in 0.2.0.

Record the actual source/tool/binary identities, profile matrix, failed attempts,
recovery and unchecked behavior. Reusing an old PNG batch or passing structural
checks does not establish runtime behavior after a change. Update the relevant
skill instructions and consumer guidance alongside delivered behavior.

The validation points above are future acceptance work. Creating this roadmap
does not run builds/tests, grant host permissions, upgrade consumers or schedule
implementation automatically.
