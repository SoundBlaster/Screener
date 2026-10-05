# ADR-0005 — Main-actor render adapters with background trace encoding

Status: Accepted for M1
Date: 2026-10-05

## Decision

- Keep UIKit, AppKit, and SwiftUI rendering behind `ScreenerCaptureSource` adapters isolated to `MainActor`.
- UIKit captures a view hierarchy with `UIGraphicsImageRenderer` and `UIView.drawHierarchy(in:afterScreenUpdates:)`.
- AppKit captures a view and its descendants with `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`.
- SwiftUI supports explicit subtrees through `ImageRenderer`; capture a hosted root window through UIKit/AppKit when the full app environment is required.
- Return a `CGImage` from the synchronous render step. PNG encoding, atomic blob publication, and timeline append happen after the image is passed to the recorder actor.
- If UIKit reports an incomplete hierarchy, fail the capture rather than recording a misleading partial image.

## Rationale

Each platform has a native render path, while trace persistence remains independent of the UI framework. The SwiftUI adapter is useful for a specific view or preview; it does not claim to reproduce all host-window environment, representable, or compositor content. The application can choose a platform adapter without changing the trace format.

## Consequences

Capture rendering still consumes main-actor time and must be measured on representative app screens. This API is explicit capture only; it does not start a display-link-rate screenshot loop. GPU-backed, protected, or otherwise non-renderable content may be missing, and capture should report backend failures rather than silently claiming full fidelity.
