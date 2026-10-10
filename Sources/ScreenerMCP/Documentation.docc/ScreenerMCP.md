# ``ScreenerMCP``

Expose local visual traces to an agent through read-only MCP tools.

## Overview

Most users should run the `screener-mcp` executable. This module provides the
catalog and server implementation for embedding the reader in another Swift tool.
It reads trace files on the host Mac; it does not record UI or control an app.

## Tools

| Tool | Result |
| --- | --- |
| `screener.sessions` | Sessions discovered beneath configured roots |
| `screener.timeline` | Ordered records with offset-based pagination |
| `screener.contact_sheet` | A numbered PNG grid and frame identifiers |
| `screener.frame` | A PNG or JPEG image selected by session and record UUID |

Timeline pages default to 500 records and allow up to 2,000. Contact sheets default
to 24 cells in four columns, allow at most 24 cells and six columns, and downsample
images for overview. Follow `nextOffset` until absent; use the cell's record ID to
request the full individual frame. Contact-sheet offsets count image records,
whereas timeline offsets count all timeline records.

## Configure the catalog

```swift
import Foundation
import ScreenerMCP

let catalog = TraceCatalog(roots: [
    URL(fileURLWithPath: "/Users/you/ScreenerTraces", isDirectory: true)
])
let sessions = catalog.sessions()
```

An individual frame is limited to 32 MiB by default. The reader checks blob paths
and rejects references outside the trace bundle, including symlink escapes.
Unreadable or incompatible bundles are omitted from session discovery, so an empty
session list can mean a wrong root or an invalid manifest, rather than no recording.
Image errors must be investigated; an empty contact sheet is not capture success.

## Topics

### Catalog and pagination

- ``TraceCatalog``
- ``TraceSession``
- ``TraceTimelinePage``
- ``TraceContactSheetCell``
- ``TraceContactSheetPage``
- ``TraceContactSheetResult``
- ``TraceCatalogError``

### Server and transport

- ``ScreenerMCPServer``
- ``CodexCompatibleStdioTransport``
- ``MCPInitializeCompatibility``
