# MCP window capture: macOS fixture

On macOS arm64, the experimental `screener-mcp` process was started with an
explicit TB5 recordings directory and controlled over its stdio MCP transport.
An independently running Screener Fixture window was selected by bundle ID,
window ID and process ID. An initial attempt with source `ab05569` terminated
with `CGS_REQUIRE_INIT` in `SCContentFilter.init(desktopIndependentWindow:)`;
its partial trace contains only the session-start event.

Initializing `NSApplication.shared` on the main actor before the window capture
resolved this failure in a second run. The process listed the fixture's windows,
started a trace, captured one requested checkpoint, returned it through the MCP
timeline and frame tools, and stopped the trace. The stored PNG visibly showed
the fixture's `Loading profile` state. The trace is in the TB5 build tree at
`runtime/fixture-traces/45D7C9D9-326A-496F-A901-AC8CABD00B07.vtrace`.

A separate VCMI-side bridge run then used a synthetic JSONL event with the
same real fixture and MCP executable. Its resulting trace contained exactly
`sessionStarted`, one `vcmi:123:1:200` keyframe, and `sessionEnded`; the PNG
showed the same fixture state. That trace is at
`runtime/bridge-fixture-check/173967F9-F4D0-4C9C-A8E4-C4897181C31C.vtrace`.
These runs used existing screen-capture access and did not test VCMI's SDL
window, continuous video, animation timing, or capture without permission.
