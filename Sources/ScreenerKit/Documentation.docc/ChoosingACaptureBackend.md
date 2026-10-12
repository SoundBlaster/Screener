# Choosing a capture backend

Select capture according to the UI evidence you need to inspect.

## Hierarchy capture

`UIKitCaptureSource` renders an existing view or window at its current display
scale. It needs no screen-recording permission and works in Simulator and on a
physical device. Use a containing window for visual effects, then verify actual
PNG pixel dimensions and recorded `scale` metadata.

`AppKitCaptureSource` captures an existing `NSView` on macOS.
`SwiftUICaptureSource` renders an explicit SwiftUI subtree; its default scale is
1, so pass a suitable scale when pixel fidelity matters. Capture a SwiftUI hosting
window through UIKit or AppKit when you need the existing window's state.

These sources are available only on platforms that provide the corresponding
framework. This documentation is compiled separately for iOS and macOS.

## Glass and system materials

Hierarchy rendering may differ from the system compositor for glass, blur, GPU
content, overlays, and animation presentation states. On Simulator, pair the trace
with `xcrun simctl io SIMULATOR_UUID screenshot screenshot.png` to compare materials.
A screenshot is an additional observation, not a replacement frame in the trace.

## GPU surfaces

Hierarchy capture can omit an entire GPU surface while producing a valid PNG.
In the local Dreams pilot on macOS 27.0, AppKit omitted the MTKView region at all
14 checkpoints. A consumer-local macOS ScreenCaptureKit screenshot path matched
the system window screenshot's RGB pixels exactly at 1280×880, 2×, including a
production `framebufferOnly=true` profile.

That finding applies to the tested SDR Metal window. RealityKit, HDR/EDR,
protected content, occlusion and sustained capture remain unverified; macOS evidence
does not establish iOS-device or Simulator GPU fidelity. Use matched system references
and inspect content, not just PNG geometry. The historical pilot used a consumer-local adapter. The working source now
supplies the optional ScreenerScreenCaptureKit product for macOS 14+ window stills,
feeding the same `recordFrame` API. It is unreleased; older pins do not gain it
when a plugin or reader is updated. A fresh packaged-adapter pilot repeats the
14 native comparisons; RealityKit/HDR/continuous capture remain unverified.

The repository preserves measurements and identities under
`docs/validation/metal-2026-10-12/` and platform routing in
`docs/capture-capabilities.md`. Custom source inputs are covered in <doc:CustomFrames>.

## Experimental ScreenCaptureKit

`ScreenCaptureKitSession` is an opt-in backend for a physical iOS 27 device. It is
excluded from Simulator and Mac Catalyst, and this implementation is not a macOS
ScreenCaptureKit backend. The user must manually approve the system sharing picker.

Start the trace first, retain the capture session, and await its `start()` method.
Reproduce while it records; do not restart capture just to coordinate a menu.
Await `stop()` before closing the trace, then inspect `failure`, frame records,
and actual images. A permission timeout does not prove that recording began.

It samples roughly once per second, with a bounded latest-frame handoff and a
final drain. A 180-second session bound includes time spent awaiting permission.
This backend targets materials and stable states, not fast transient animations.
Keep its SDK availability, application build, and MCP reader version distinct.

## Evaluate three questions separately

- **Scale:** do PNG dimensions match view bounds multiplied by the display scale?
- **Materials:** do blur and glass match a system screenshot of the same state?
- **Transitions:** were the relevant intermediate states actually sampled?

A correct result for one question does not establish the other two.
