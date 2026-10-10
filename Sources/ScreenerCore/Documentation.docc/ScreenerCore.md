# ``ScreenerCore``

Read and write the local trace format shared by the capture SDK and MCP reader.

## Overview

A `.vtrace` bundle is a directory containing `manifest.json`, an append-only
`timeline.jsonl`, and image or semantic blobs. The format version describes the
storage contract; `screenerVersion` identifies the producer SDK and is independent
of the app version and MCP reader version.

Use ScreenerKit to capture UI. Use this module when inspecting trace records or
building a tool that consumes existing bundles.

```swift
import Foundation
import ScreenerCore

func inspectTrace(at traceURL: URL) throws {
    let reader = TraceBundleReader(url: traceURL)
    let manifest = try reader.manifest()
    let timeline = try reader.timelineResult()
    print(manifest.name, timeline.records.count)
    print("Skipped optional kinds:", timeline.skippedOptionalKinds)
}
```

The reader rejects unsupported format versions and malformed complete records.
It ignores an unterminated trailing JSONL line, which can occur when writing is
interrupted. Unknown records may be skipped only when their header declares them
optional; use `timelineResult()` to inspect those skipped kinds.

The writer publishes blobs atomically before appending references. Use a new bundle
URL for each session. Closing a writer prevents further appends; the higher-level
ScreenerKit recorder is responsible for writing the session lifecycle records.

## Topics

### Bundle access

- ``TraceBundleReader``
- ``TraceBundleWriter``
- ``TraceBundleError``

### Trace model

- ``TraceManifest``
- ``TraceRecord``
- ``TraceTimeline``
