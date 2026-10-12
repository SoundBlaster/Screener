# Capture capabilities and GPU surfaces

Evidence snapshot: 2026-10-12. Select a capture backend separately from the trace
writer and MCP reader: a valid `.vtrace` does not prove the displayed pixels were captured.

## Platform and backend matrix

| Target | Path | Permission / availability | What is established |
| --- | --- | --- | --- |
| macOS, ordinary views | Screener `AppKitCaptureSource` | In-process hierarchy capture; no screen-recording prompt | Existing AppKit fixtures; materials may differ from compositor |
| macOS 14+, Metal window | Optional `ScreenerScreenCaptureKit` → Kit recorder | Working source, unreleased; explicit window/PID and existing Screen Recording access | Packaged Dreams MTKView pilot, 14 checkpoints, native 2×; matches system RGB screenshot |
| Physical iOS 27 | Screener `ScreenCaptureKitSession` | SDK with iOS framework; manually approved current-app system picker | Air base/menu capture; not a Metal or RealityKit test |
| Physical iOS / Simulator | Screener `UIKitCaptureSource` | In-process hierarchy capture; no screen-recording prompt | Native rendering scale; glass and GPU fidelity are not guaranteed |
| iOS Simulator | Mac host `simctl io <UDID> screenshot` or XCTest system screenshot | Host-driven Simulator display capture; no iOS recording picker | Native screenshot pipeline exercised in PhotoCompressor/CityChain; GPU scenes not tested here |
| Mac Catalyst | Platform-appropriate existing hierarchy adapter | Current Screener SCK session is explicitly excluded | No SCK consumer pilot here |

Apple's macOS ScreenCaptureKit framework and Screener's shipped adapter are distinct.
The historical Screener 0.1.0 pin has **no macOS SCK adapter**. The working source
now provides the optional product; the fresh Dreams probe consumes it through an
explicit local package path. This does not establish a tagged release or availability
in applications still pinned to 0.1.0.

Apple documents [current-app capture on iOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios)
for a physical iOS 27+ device. In the locally installed **iPhoneSimulator 27.1 SDK**,
`System/Library/Frameworks/ScreenCaptureKit.framework` is absent. The current
Screener compile guard also excludes Simulator and Mac Catalyst. Recheck the
selected SDK and the consumer's actual pin on future toolchains; this snapshot
is not a permanent statement about every Simulator release.

Capturing the Simulator window with macOS ScreenCaptureKit is another host-side
option with its own permission model; it does not make the iOS session available
inside Simulator. The supplied screenshot runner uses system screenshots instead.

## GPU finding and limits

The [Dreams Metal pilot](validation/metal-2026-10-12/README.md) used the real
RainRenderer in a native 1280×880, 2× window on macOS 27.0. AppKit captured the label
and background but omitted the entire MTKView region in every checkpoint.
Transparent, opaque, repeated fixed, live-between-checkpoints and production
`framebufferOnly=true` profiles all reproduced this limitation.

For the same 14 settled checkpoints, macOS ScreenCaptureKit matched the system
window screenshot's RGB pixels exactly: MAE 0, maximum difference 0, 100% exact
pixels. This establishes that **this Metal surface survives compositor capture**.
It does not establish that all GPU surfaces work without problems. The system
screenshot and SCK may share implementation, so equality is agreement with the
system reference rather than independent colorimetric proof.

Still unverified: RealityKit, HDR/EDR, protected content, sustained recording,
frame drops under CPU/GPU load, occlusion, multiple displays and resolution changes.
The live profile advances rendering between checkpoints and pauses for each paired
capture; it does not prove continuous motion capture. macOS results do not establish
iOS-device or Simulator GPU fidelity.

## Target SDK architecture

[ADR-0006](adr/ADR-0006-capture-backends-and-custom-frame-ingestion.md) records the
accepted direction: an optional ScreenerScreenCaptureKit module uses ScreenerKit's
public frame ingestion. Custom images and typed buffers retain that same ingestion
path without depending on the SCK module. The first slice is implemented and
[validated locally](validation/packaged-backend-2026-10-12/README.md); continuous
macOS capture remains future work.

## Routing and evidence requirements

1. Use hierarchy capture for ordinary layout/state traces. Inspect the actual pixels.
2. For Metal, RealityKit or compositor materials, obtain a matched system reference
   at native pixels. Do not accept a PNG solely because dimensions/lifecycle pass.
3. If hierarchy capture loses content, choose a compositor path explicitly. On
   macOS use the optional product when present in the resolved SDK; on physical iOS verify SDK,
   availability and manual permission before using `ScreenCaptureKitSession`.
4. Keep hierarchy, system-reference and SCK frames labelled with their actual
   sources. Record SDK/app/reader identity, native geometry, permission state,
   scene readiness and failure/stop records. Preserve unsupported cases as unknowns.

The separate BuildHunter macOS screenshot runner pilot remains blocked before
XCTest scenario startup. The Dreams direct-app probe does
not promote that runner to runtime-validated status.
