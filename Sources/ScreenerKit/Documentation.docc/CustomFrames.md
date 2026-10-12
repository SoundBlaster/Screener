# Recording custom images and buffers

Submit application-owned pixels independently of system capture.

## Overview

Custom sources use the public `Screener.recordFrame` API. They need only
ScreenerKit; importing the optional ScreenerScreenCaptureKit product or obtaining
screen-recording permission is unnecessary. Start a trace first and close it after
all producers have stopped and their accepted writes have completed.

A CGImage can use the existing `CapturedImage(cgImage:scale:)` initializer. Keep
externally backed pixels stable until awaited recording finishes. Raw/pixel-buffer
converters copy synchronously so the producer can reuse its buffer after conversion.

## Typed inputs

| Input | API | Interpretation |
| --- | --- | --- |
| CGImage | `CapturedImage(cgImage:scale:)` | No rasterization; caller owns stable source pixels |
| Raw Data | `CapturedImage(pixels:width:height:bytesPerRow:format:colorSpace:premultipliedAlpha:scale:)` | Owned copy; RGBA8/BGRA8, validated stride/count, explicit RGB color and alpha |
| Encoded Data | `CapturedImage(encodedImage:scale:)` | First image decoded, EXIF orientation applied; non-up orientation uses SDR RGBA8, up retains decoded depth |
| CIImage | `CapturedImage(ciImage:colorSpace:orientation:scale:)` | Finite integral extent, explicit RGB conversion, SDR RGBA8 |
| CVPixelBuffer | `CapturedImage(pixelBuffer:colorSpace:orientation:premultipliedAlpha:scale:)` | Synchronous read-locked copy; nonplanar BGRA8/RGBA8 only |
| CMSampleBuffer | `CapturedFrame(sampleBuffer:colorSpace:orientation:premultipliedAlpha:scale:)` | Complete image-bearing sample; copies pixels and carries numeric source PTS |
| UIImage | `CapturedImage(uiImage:)` | MainActor, source scale/orientation; UIKit drawing at source size/scale when no CG/CI backing is exposed; SDR sRGB |
| NSImage | `CapturedImage(nsImage:pixelWidth:pixelHeight:scale:)` | MainActor, explicit raster dimensions including vector sources, SDR sRGB |

Unsupported pixel formats, including YUV/planar and HDR buffers, throw an explicit
conversion error. CI/UIImage/NSImage conversion is SDR; do not use these helpers
as a claim of HDR/EDR or bit-depth preservation. No arbitrary `Any` or borrowed
pointer input crosses the recorder actor. Direct GPU textures need a custom
adapter which waits for GPU completion and snapshots pixels first.

## Raw pixels

```swift
import CoreGraphics
import Foundation
import ScreenerKit

func recordPixels(_ data: Data, width: Int, height: Int, stride: Int,
                  scale: Double, recorder: Screener) async throws {
    let image = try CapturedImage(pixels: data, width: width, height: height,
        bytesPerRow: stride, format: .bgra8,
        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, scale: scale)
    try await recorder.recordFrame(image, reason: "custom.checkpoint",
        metadata: ["capture.backend": "custom.raw-bgra8"])
}
```

## Source time and pacing

`CapturedFrame` associates an image with optional finite presentation seconds.
The corresponding `recordFrame(_:reason:metadata:)` overload stores source PTS
as `capture.presentationSeconds`. It protects that field from caller metadata and
does not replace recorder time or sort producers by incomparable source clocks.
A sample without numeric PTS omits that field.

Await sequential manual checkpoints. The recorder orders accepted operations but
does not bound an arbitrary number of concurrent calls. Callback producers must
bound their pending work and document drop/replacement policy; do not create an
unbounded Task for every incoming frame. Stop/drain producers before closing the trace.

The Dreams Metal pilot exercises the raw BGRA8 path. Compilation of other
converters is separate from runtime evidence for their format, orientation,
ownership and cancellation behavior; see repository validation records.
