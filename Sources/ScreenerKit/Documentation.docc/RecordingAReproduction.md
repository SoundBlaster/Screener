# Recording a reproduction

Capture a short sequence from an existing window and close the resulting trace.

## Add the SDK

Add `https://github.com/SoundBlaster/Screener` in Xcode's Package Dependencies,
select version `0.1.0`, and link the `ScreenerKit` product to your app target.
Keep recording behind `#if DEBUG`; recording is an explicit development action.

## Capture an iOS window

Call this helper from a Debug action while your window is visible, and reproduce
the issue during the loop. Use a window belonging to the current scene.

```swift
#if DEBUG && canImport(UIKit)
import UIKit
import ScreenerKit

@MainActor
func recordUI(in window: UIWindow) async throws -> URL {
    let recorder = Screener()
    let trace = try await recorder.startSession(
        name: "ui-reproduction",
        appBundleID: Bundle.main.bundleIdentifier ?? "example.app",
        tracesDirectory: URL.documentsDirectory.appending(path: "ScreenerTraces")
    )
    let capture = ScreenerCaptureSession(screener: recorder)
    do {
        try await recorder.mark("Reproduction.started")
        for index in 0..<20 {
            try await capture.capture(
                from: UIKitCaptureSource(view: window), reason: "sample-\(index)"
            )
            try await Task.sleep(for: .milliseconds(100))
        }
        try await recorder.stopSession()
        return trace
    } catch {
        try? await recorder.stopSession()
        throw error
    }
}
#endif
```

The sleep is a pause between captures. Rendering and PNG writes take additional
time, so this does not promise ten frames per second. Add markers at meaningful
points in your own flow, for example `try await recorder.mark("Menu.opened")`.

## Capture a macOS view

The following statement belongs inside an active recording flow on `MainActor`,
where `capture` is a `ScreenerCaptureSession` and `view` is an `NSView`:

```swift
try await capture.capture(
    from: AppKitCaptureSource(view: view), reason: "menu-visible"
)
```

The default background mode fills a window content view with its window's
background color; subviews retain transparency. This is a view capture and does
not include unrelated system windows or menus outside that hierarchy.

## Verify the result

A successful reproduction has readable PNG frames, the expected markers, and a
`sessionEnded` record. Closing a trace with no frames is not evidence of capture.
Always close the recorder on failure; report the original error instead of treating
an empty trace as success. Continue with <doc:InspectingWithAnAgent>.
