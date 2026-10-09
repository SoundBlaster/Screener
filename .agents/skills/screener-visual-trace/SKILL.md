---
name: screener-visual-trace
description: Integrate or inspect Screener Debug visual traces on iOS, choose UIKit or opt-in ScreenCaptureKit capture, and compare system materials with Simulator screenshots. Use for layout, transient UI, glass/blur, capture scale, or .vtrace verification; not for general screen recording.
---

# Screener visual trace

Produce a bounded Debug recording with semantic markers, inspect its actual frames,
and state which backend and device supplied each piece of evidence. The consuming
app and Screener SDK are separate checkouts/dependencies; do not assume an app has
both capture modes merely because this skill is installed.

## Choose capture evidence

| Goal / target | Preferred path | Permission / limits |
| --- | --- | --- |
| Layout, gestures, state sequence on device or Simulator | UIKit window capture → `.vtrace` | No recording permission; app instrumentation still required |
| Glass/blur/menu pixels on Simulator | UIKit trace + matching `simctl` screenshot | No screen-recording picker; screenshot stays separate reference evidence |
| Current-app glass/menu pixels on physical iOS 27 | Opt-in `ScreenCaptureKitSession` → `.vtrace` | Manual system permission; experimental, device SDK required |

UIKit is the default. It uses the view's current `traitCollection.displayScale`
(including a UIWindow), not a hard-coded 1× or `UIScreen.nativeScale` resample.
`drawHierarchy` can miss compositor materials even when it reports success.
A system screenshot is a better comparison reference for the displayed materials,
not a guarantee of pixel identity or proof that the trace captured those pixels.

ScreenCaptureKit is absent from the current iOS Simulator SDK. Verify the local
SDK/availability before integrating it; never route Simulator to the physical
capture API or silently replace the requested physical device with a simulator.
The recorded Air experiment establishes portrait base/menu behavior, not rotation,
backgrounding, interruption, or performance coverage on other devices.

## Establish integration and target

- Inspect the consuming app's Debug capture entry point, package pin/revision,
  bundle ID, trace directory, launch arguments, and selected device. Preserve its
  existing mode flags rather than inventing a second integration.
- Inspect the actual Screener SDK source when available. `ScreenCaptureKitSession`
  is experimental; `v0.1.0-alpha.1` predates that SDK API. If the consuming pin
  lacks the symbol, report that gap and use UIKit unless an update is authorized.
- If source lookup is needed, use a user-provided checkout or `SCREENER_REPO`,
  then a matching workspace/local package checkout. Do not treat this skill's
  installed plugin-cache location as the consuming app or a writable source checkout.
- Keep new capture controls/instrumentation in Debug or an explicit development
  build. Prefer synthetic content for shareable artifacts; keep user content within
  the task's authorized evidence locations.

Read [capture workflows](references/capture-workflows.md) for the chosen mode's
API lifecycle, device commands, and evidence checks. Use available Xcode/device
skills or tools when appropriate; this skill does not require a particular MCP
provider and does not grant permission to automate system consent.

## Record once, inspect, and report

Record a bounded sequence such as base → menu/gesture → settled → stop, adding
semantic markers around the app actions. Reuse the same approved stream for all
states. ScreenCaptureKit `start()` waits for manual permission; never tap the
positive consent button automatically, repeatedly relaunch to obtain it, or
claim approval was automated. If the user is unavailable, stop at the permission
boundary and report that capture has not started.

Stop/drain capture before closing the trace. On cancel, timeout, or error, inspect
`state`/`failure` and still close the caller-owned trace. The SDK samples roughly
once per second plus a final drain; it is not video or guaranteed transition-rate
capture. Use appropriate faster evidence if the requested transition can occur
between keyframes.

If Screener MCP is connected, inspect `screener.sessions` → `screener.timeline`
→ `screener.contact_sheet` / `screener.frame` by returned IDs. Otherwise inspect
manifest/timeline and decode the referenced PNGs directly. Missing MCP is not a
reason to fabricate a tool result or reconfigure global connections automatically.

Report backend, exact target/OS, permission status, actual decoded PNG dimensions
and scale, state sequence, final lifecycle records, errors, and artifact paths.
Separate build success, runtime/UI success, material fidelity, and performance
claims. For screenshot comparisons match appearance, orientation, geometry, and
settled state; treat source PTS and recorder time as different clocks. Cite the
frame that actually contains the menu/transition, not merely a later screenshot.
