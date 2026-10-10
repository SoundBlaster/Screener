# Inspecting a trace with an agent

Move a completed trace to your Mac and connect the local MCP reader.

## Export from Simulator

Wait for recording to finish. Replace the placeholders with your Simulator UUID
and app bundle ID; obtain the UUID with `xcrun simctl list devices booted`.

```sh
APP_DATA=$(xcrun simctl get_app_container SIMULATOR_UUID YOUR_APP_BUNDLE_ID data)
mkdir -p "$HOME/ScreenerTraces"
cp -R "$APP_DATA/Documents/ScreenerTraces/." "$HOME/ScreenerTraces/"
```

For a physical device, export the app container through Xcode's Devices and
Simulators window and copy the same trace directory from its Documents folder.
The MCP process on your Mac cannot directly read an iPhone's app sandbox.

## Build and register the server

```sh
git clone --branch v0.1.0 https://github.com/SoundBlaster/Screener.git
cd Screener
swift build -c release --product screener-mcp
SCREENER_BIN="$(swift build -c release --show-bin-path)/screener-mcp"
codex mcp add screener -- "$SCREENER_BIN" --traces-dir "$HOME/ScreenerTraces"
```

Start a new agent session to load the registered server. Other MCP clients need
the absolute executable path, `--traces-dir`, and an absolute trace directory in
their stdio-server configuration. They must support displaying image results.

## Inspect the evidence

Ask the agent to list sessions, read the timeline, inspect a contact sheet, and
open the individual frames around a change. The tools are `screener.sessions`,
`screener.timeline`, `screener.contact_sheet`, and `screener.frame`.

Follow each result's `nextOffset` when present. A contact sheet is an overview;
use individual images to assess details and scale. Distinguish captured states
from inferred transitions and report missing frames or image errors explicitly.

The server reads local files and does not start recordings or drive the app.
Your MCP client's model and data-handling settings determine where images go
after the client reads them.
