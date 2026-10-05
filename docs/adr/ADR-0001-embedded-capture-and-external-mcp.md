# ADR-0001 — Embedded capture SDK + external macOS MCP server

Status: Accepted for MVP
Date: 2026-10-05

## Context

Screener needs to record transient UI states of iOS/macOS applications and make those states inspectable by a coding agent after the fact.

Two obvious designs exist:

1. record the whole screen from outside the application;
2. embed capture into the application and expose the resulting trace to an external agent-facing process.

A system recorder has compositor-level pixels but weak application semantics and normally requires screen-recording permission/content selection. An embedded recorder knows the app/scene/build and can accept semantic markers, but view-hierarchy snapshots may not faithfully capture every GPU/video surface.

The MCP server could also be embedded into the application, but that would couple a development protocol and transport lifecycle to an iOS app process, complicate device networking, and expose more attack surface inside the product process.

## Decision

Use two primary components:

- `ScreenerKit`: an embedded Swift Package that records app-owned visual/semantic trace data.
- `screener-mcp`: a separate macOS Swift executable that discovers and reads traces and exposes read-only MCP tools to coding agents.

For the MVP, the embedded capture backend uses native view/window rendering. ScreenCaptureKit is an optional future capture backend, not a required dependency.

The MCP process never needs to run inside the iOS application.

## Rationale

### Semantic proximity

The app can attach route/state/build/marker information at the exact timestamp that visual state is recorded.

### No primary screen-recording permission path

An app recording its own renderable hierarchy avoids requiring a global screen-capture permission flow for the common debugging path.

### Simpler Simulator development

The iOS Simulator's app data container can be resolved from the Mac using Apple developer tooling, making the first end-to-end version file-based rather than network-based.

### Failure isolation

If MCP crashes or is misconfigured, the host app continues to run and record. If the app exits, the completed trace remains inspectable.

### Protocol isolation

MCP can evolve independently from the SDK and trace format. Other readers/viewers can consume `.vtrace` without implementing MCP.

### Read-only agent boundary

The MCP surface can be intentionally limited to inspection. A coding agent does not gain arbitrary runtime control merely because it can inspect traces.

## Consequences

Positive:

- Native Swift stack end-to-end.
- Strong app semantics.
- Local file is a durable handoff artifact.
- Easy offline analysis.
- Agent inspection does not need to coincide with the UI event.
- Simulator MVP requires no bespoke network transport.

Negative:

- View rendering may miss AV/Metal/protected content.
- Capturing a UIKit/AppKit hierarchy can consume main-thread time.
- Physical-device access needs a later bridge.
- Two deliverables must be versioned: SDK and MCP reader.

## Alternatives rejected for MVP

### ScreenCaptureKit-only system recorder

Rejected as the primary path because it is broader than necessary, requires user-mediated capture permission/selection, and lacks the semantic proximity of embedded instrumentation.

Retained as a future backend for compositor-fidelity cases.

### Video recording + post-processing

Rejected because continuous video increases storage, decoding and temporal search cost while discarding semantic event structure.

### MCP server embedded directly in the iOS app

Rejected because MCP is an agent integration boundary, not an application-runtime concern. It would require device transport/discovery before the trace model itself is validated and would unnecessarily expose the app process to protocol traffic.

### Cloud session replay service

Rejected because local developer tooling is the primary use case; network/cloud dependency would increase privacy and operational complexity without solving the core temporal problem better.

## Implementation constraints

- `ScreenerKit` must not import the MCP package.
- `screener-mcp` may depend on the official MCP Swift SDK.
- The trace format is the integration contract between recorder and readers.
- Capture backend is a protocol/adapter boundary.
- Trace source/discovery is a protocol/adapter boundary.
- ScreenCaptureKit integration must not require a trace-format change.
