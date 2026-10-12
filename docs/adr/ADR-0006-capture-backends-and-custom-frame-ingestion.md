# ADR-0006 — Optional capture backends and public frame ingestion

Status: Accepted; first implementation slice complete (unreleased)
Date: 2026-10-12

## Context

The consumer requires a Screener module implementing macOS ScreenCaptureKit capture,
while retaining the ability to supply custom frames, buffers and images.
The [Dreams pilot](../validation/metal-2026-10-12/README.md) establishes one useful
Metal capture path; it does not establish a released SDK backend or universal GPU fidelity.

Current source already separates the `Screener` recorder from the synchronous,
MainActor-bound `ScreenerCaptureSource` hierarchy renderer. The public
`recordFrame(_:reason:metadata:)` method accepts `CapturedImage` directly.
`CapturedImage` carries a CGImage and display scale. The recorder encodes PNG,
writes a blob and publishes a keyframe record through ScreenerCore.

The following package graph is implemented in the working source. Continuous
macOS capture remains a later slice; this implementation supplies async window stills.

## Decision

### Module dependencies

```text
ScreenerScreenCaptureKit ──→ ScreenerKit ──→ ScreenerCore
                              ↑                ↑
Custom source / converter ─────┘           ScreenerMCP
```

Arrows mean imports/dependencies, not frame flow.

| Module | Responsibility |
| --- | --- |
| ScreenerCore | Trace format, blobs, ordered records, bundle reader/writer; no UI or capture framework dependency |
| ScreenerKit | Recorder/session API, public image/frame submission, image conversion, existing hierarchy adapters |
| ScreenerScreenCaptureKit (optional target/product) | Apple SCK integration: explicit target selection, authorization, still capture and eventual bounded stream lifecycle |
| Consumer/custom adapter | Producing or converting application-owned images/buffers and submitting them through the public recorder API |
| ScreenerMCP | Read-only inspection of stored traces, independent of capture backend |

An app importing only ScreenerKit can submit frames without linking the SCK
product. ScreenerKit must not depend on ScreenerScreenCaptureKit: that would
create a cycle and make custom capture depend on the system capture integration.
Keep existing hierarchy adapters in Kit; this decision does not require a target
for every renderer or image type.

### One public ingestion path

Preserve the existing direct submission API and use it from the new backend:

```swift
// Existing API; caller has already started a trace.
let image = try CapturedImage(cgImage: customImage, scale: displayScale)
try await screener.recordFrame(
    image,
    reason: "renderer.checkpoint",
    metadata: ["capture.backend": "custom"]
)
```

SCK and custom sources converge before PNG encoding and trace publication. They
must share storage, metadata validation, ordering and errors. Do not create a
second writer/trace format for compositor frames. SCK target identifiers,
SCContentFilter and stream state stay inside the SCK module rather than entering
the recorder's common input type.

Custom sources can use direct push submission. They do not have to conform to
`ScreenerCaptureSource`, use MainActor, request recording permission, start a
system picker or implement a stream lifecycle. That existing protocol remains
the convenience boundary for synchronous UI renderers. Async still capture and
push stream callbacks must not be forced into its synchronous `capture()` method.

### Image and buffer conversion

Conversion entry points in Kit are documented in the DocC `CustomFrames` article.
`CapturedImage` supplies raw/encoded/CI/platform-image and pixel-buffer conversion;
`CapturedFrame` carries an image and optional source PTS, including conversion from
CMSampleBuffer. Its recorder overload preserves PTS separately from timeline time.
Buffer conversion is usable without the SCK product.

| Custom input | Common recording boundary |
| --- | --- |
| CGImage | Existing `CapturedImage` initializer and direct `recordFrame` |
| UIImage / NSImage / CIImage | Explicit rasterization with native geometry, scale, orientation and color information |
| CVPixelBuffer / image-bearing CMSampleBuffer | Validated format/plane/color conversion; preserve source PTS separately from recorder time |
| Owned raw pixel bytes | Typed dimensions, row stride, pixel format, alpha and color description; validate byte ranges and copy/retain safely |
| Encoded PNG/JPEG Data | Explicit decode to the common image path; never treat arbitrary bytes as raw pixels |
| Metal texture or another GPU resource | Consumer adapter establishes GPU completion and a stable image/buffer before submission; direct texture support is not promised by this ADR |

Buffer overloads need explicit contracts, not an `Any` parameter. Unknown pixel
formats, incompatible plane layouts, invalid lengths/stride, incomplete samples
and failed conversion must produce errors. Native dimensions and color information
must not be silently changed to satisfy an output profile. HDR/EDR preservation
requires its own format/conversion contract and evidence; the SDR pilot is not proof.

The `.vtrace` remains an image/keyframe format. Accepting a buffer does not imply
archiving its original raw/video representation or promising zero-copy recording.

### Ownership, concurrency and time

- Conversion must establish stable image contents before storage reads them.
  Retaining a mutable buffer alone does not prevent a producer/pool from reusing
  or changing its pixels. Copy where immutable ownership cannot be established.
- Document the safe reuse point for every input form. After successful awaited
  recording, the frame is encoded and published. On cancellation/failure, settle
  any owned conversion/storage work before permitting producer memory reuse.
- UI object access remains on MainActor. Conversion/encoding and file I/O must not
  impose MainActor isolation on arbitrary custom producers.
- Preserve native pixel dimensions, display scale, orientation handling, color
  conversion and backend provenance. Protect storage-derived metadata from overrides.
- Source timestamps/PTS and recorder timestamps are separate clock domains.
  Preserve source time explicitly; do not overwrite timeline time with stream PTS
  or reorder multiple producers by incomparable source clocks.
- Sequential callers can await each write for pacing. The current recorder is
  not a bounded ingress queue: actor serialization alone does not bound concurrent
  submissions. Callback/stream adapters must bound pending work, document any
  replacement/drop policy and expose its outcome. Do not create one unbounded Task
  per incoming frame or silently discard manually submitted checkpoints.

These are implementation obligations for new converters/backends, not claims
that unimplemented overloads already meet them.

### Backend lifecycle and permissions

The first macOS slice provides explicit window still capture using the tested
Apple path. Record the selected window identity; do not pick an arbitrary process
window or fall back to desktop capture. A future stream is a separate API with
bounded buffering, start/cancel/stop/failure semantics and drain behavior.

The app owns the trace lifecycle. Capture sources stop and drain accepted work
before the app closes the trace. Stop must be idempotent and failures observable.
Recording permission belongs to the chosen system backend. Custom image/buffer
submission must never start a system capture permission flow.

Keep macOS SCK, physical iOS SCK and host-driven Simulator screenshots explicit.
Check SDK/runtime availability per API; do not raise the entire package's minimum
OS simply because an optional backend needs a newer OS. No silent hierarchy
fallback for a requested GPU/compositor capture.

## Compatibility and incremental migration

1. Preserve the current `CapturedImage`, direct `recordFrame` and hierarchy APIs.
   Add buffer/image conversion at the common ingestion boundary.
2. Add the optional ScreenerScreenCaptureKit target/product and one macOS window
   still-capture path. Reuse Kit ingestion; move the Dreams probe to consume it.
3. Validate the same native Metal comparison against the packaged adapter, then
   exercise custom images/buffers without importing the SCK module.
4. Add continuous capture only with a separate lifecycle/backpressure proof matrix.

The current physical-iOS `ScreenCaptureKitSession` lives in ScreenerKit. Retain
that API during the first macOS slice. A later relocation into the optional module
requires an explicit source-compatibility/versioning decision: Kit cannot forward
into a module which depends on Kit. Do not introduce a dependency cycle or change
the iOS API incidentally while adding macOS capture.

## Completion evidence required for implementation

- Package graph: optional product imports Kit; Core and custom clients do not
  acquire a dependency on the SCK target.
- Existing direct CGImage path and new typed buffer/image conversions preserve
  geometry, provenance, errors and memory ownership through storage.
- macOS packaged adapter reproduces the settled Dreams profiles at native pixels;
  include production `framebufferOnly=true` and permission/target failure paths.
- Custom producer operates without SCK authorization; pooled/mutable input reuse,
  unsupported formats, cancellation and stop/drain have explicit evidence.
- Physical iOS compatibility and unavailable SDK/Simulator cases stay separately
  checked. RealityKit/HDR/continuous capture remain unknown until exercised.

## Implementation record

The first slice adds the optional product, native macOS 14+ window still source,
common typed conversions and CapturedFrame ingestion. Package minimums and the
physical-iOS session remain unchanged. Future continuous capture is not implemented.

The [packaged-backend report](../validation/packaged-backend-2026-10-12/README.md)
records source identities, builds and a fresh Dreams comparison. The historical
consumer-local pilot remains unchanged. Runtime coverage for custom inputs is
limited to raw BGRA8 in Dreams; the other converters have compilation evidence.
Ownership-reuse, invalid-input, permission-denial and cancellation application
tests were not added/run. Structural and documentation checks are separate evidence.

### UIImage review follow-up

PR #16 review identified a gap in the existing UIImage conversion contract:
renderable images need not expose either CGImage or CIImage backing. The converter
now draws that case at the source size/scale and applies orientation only once.
The public API and module boundaries are unchanged. See the
[focused UIKit validation](../validation/uiimage-fallback-2026-10-12/README.md).
Earlier Metal evidence stays bound to its recorded source hashes; this UIKit-only
change does not relabel those runs as evidence for the updated UIImage converter.
