# Multi-display Simulator: Duo

Use this reference for a manual Duo capture or a black/empty display diagnosis.
These observations came from PhotoCompressor Release1.1(14), Xcode27.1
(27A9275), iOS27.1 Simulator runtime24A94425 on 2026-10-26. Recheck the
installed toolchain; they do not establish behavior for every runtime or device.
The supplied screenshot runner does not automate folding.

## Runtime and display activation

- Inspect `xcrun simctl list runtimes --json` and `list devices --json` before
  booting. A preserved simulator may become unavailable after its runtime is
  removed; reinstalling a compatible runtime can make it available again.
  In this pilot, iOS27.0 rejected Duo as incompatible. Do not recreate/erase
  user simulators or repeatedly build the app to repair a missing runtime.
- Use the available Simulator frontend. This Xcode exposed DeviceHub at
  `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`; do not assume
  a standalone Simulator.app is installed. Inspect the actual accessibility tree.
- Activate **Closed** for the outer screen and **Open** for the inner screen
  with DeviceHub's supported controls. Boot/launch alone did not activate the
  inner display. Its initial native PNG was black; Open showed the running app.
  Capture the active display again before classifying missing rendering as a bug.
- DeviceInteraction hierarchy returned `cannotFindFrontApplications` while the
  app and Photos picker remained usable through DeviceHub accessibility controls.
  A tool discovery failure does not prove app failure. Use another supported UI
  route and verify each action; keep retries bounded and close sessions afterward.

## Native capture and review

The pilot captured native outer1398×2034 and inner2853×2007 PNGs. Treat these as
observed profile dimensions, not universal constants or permission to resize a
wrong capture. Record runtime, display/fold state, orientation and decoded geometry
for every selected image. Inspect actual pixels from both displays.

A right-side clock/network/battery rail also appeared in native Photos picker.
App actions could occupy that side area. Unfamiliar system chrome alone is not
proof of malformed layout: distinguish system UI from overlap, clipped app
content, stale/inactive displays and a genuine integration defect. Do not crop
away native chrome to conceal a suspected bug.

For glass/menu fidelity use the existing paired system-reference path when the
consumer has a Screener harness. This shipping Release had no capture hooks, so
manual native `simctl io <UDID> screenshot` captures were separate evidence,
not Screener traces or proof that the portable runner supports Duo unfolding.
Choose the active display using supported capture options discovered from the
installed command's help; a PNG from an inactive display can be valid but black.
DeviceInteraction screenshots may use point dimensions: verify decoded pixels.

On this host, direct CoreSimulator output to the external SSD failed with file
permission513. A bounded capture to a temporary local path followed by a verified
copy to the approved artifact disk worked. Remove only that task's temporary copy
after verification. DerivedData routing does not relocate runtime/device storage;
check their free space separately and do not silently move all CoreSimulator data.

## Shipping content and upload boundary

For user-photo store assets, operate the real Photos picker, verify selected
count/order and record binary/fixture identity. Do not substitute a synthetic
fixture or fabricate Pro entitlement. Twelve reviewed PNGs in this pilot covered
outer/inner × en-US/ru × batch/menu/fullscreen; this is not physical Duo acceptance.

Capture success and upload-tool support are independent. The installed asc5.3.3
rejected `APP_IPHONE_DUO` before mutation although remote Duo sets existed.
Inspect current CLI capabilities after an update; do not relabel Duo images as
another device type or delete old sets before a viable replacement path exists.
Updating to asc5.17.0 exposed Duo native sizes and validated all six EN PNGs
without warnings on the same host. This establishes local CLI support, not a
successful Apple upload.
Keep upload plans/receipts separate from capture evidence and verify final remote
order, checksums and delivery state after an authorized upload.
