# ADR-0007 — Opt-in MCP window recording

Status: Accepted for the experimental macOS window-recording mode
Date: 2026-11-10

## Context

The read-only MCP server in ADR-0001 cannot initiate a trace of a running
external application. A user wants to correlate meaningful game-state changes
with compositor-level snapshots and inspect them through Screener. Existing
window capture and trace-writing APIs provide the necessary building blocks.

## Decision

Keep the existing server read-only by default. A separately configured
`--recordings-dir` opts into macOS window recording and adds tools for finding
windows of one named application, starting a session for an explicit window and
process, capturing a named checkpoint, and stopping that session. Captures are
request-driven: starting a session does not start a timer or take screenshots.
An application or test can request a capture after an observed state change.
The server does not infer game semantics from pixel differences.

The configured directory is also a trace catalog root. MCP callers cannot pass
filesystem paths, substitute the desktop, prompt for screen-capture access, or
select windows without an explicit application filter. The existing window
source checks the window ID and process ID together on each capture. The mode
supports one active session with a bounded number of captures. Concurrent
state transitions fail explicitly. A missing OS grant, vanished window, failed
capture or interrupted session must remain observable; no synthetic image is
substituted. Normal capture and record timestamps are distinct from any source
game-state timestamp supplied as a marker.

This extends the read-only MCP decision in ADR-0001 only for the explicitly
enabled mode. It does not authorize arbitrary app control, unrestricted screen
recording, background capture, audio capture, or code execution. Sparse stills
do not prove animation smoothness or reproduce every rendered frame.

## Verification

Test default tool compatibility, argument validation, lifecycle and concurrent
requests with a controlled capture provider. Check trace visibility using the
existing catalog. Verify real window capture separately with actual macOS
permission and the target application; successful mocks are not that evidence.
