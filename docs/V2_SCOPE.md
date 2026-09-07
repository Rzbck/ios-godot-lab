# iPhone Lab V2 — current feature scope

This branch turns the bootstrap probe into a reusable iPhone capability lab.

## UI
- persistent page menu: Overview / Sensors / GPS / Network / Device;
- vertical page scrolling is intentionally allowed to begin over cards and labels; interactive controls use `MOUSE_FILTER_PASS` so drag gestures can bubble to the page `ScrollContainer`;
- Godot boot image is disabled in `project.godot`.

## iPhone APIs
- direct Godot: touch/drag, accelerometer, gravity, gyroscope, magnetometer, haptics, camera feed, microphone level, system/locale and clipboard;
- native `IOSLab` bridge: CoreLocation, BLE discovery with CoreBluetooth, battery level/state, ARKit availability, LiDAR scene-reconstruction availability, NFC reader availability;
- GPS page includes a small OpenStreetMap tile viewer and Apple Maps handoff.

## Networking
The Network page is intentionally generic for creative-computing use:
- HTTP/HTTPS with editable method, URL, headers and body;
- WebSocket/WSS connect/send/receive;
- raw UDP;
- OSC message with one string argument.

This can target a reachable LAN address, Tailscale peer, TouchDesigner service, SIGNAL endpoint, Python service, or public test endpoint. Plain HTTP/WS is enabled for this personal lab build; prefer HTTPS/WSS outside a trusted network.

## Telemetry
Runtime telemetry is intentionally **not enabled yet**. Issue #2 tracks that separately. No Apple ID, UDID, pairing material or device identity is uploaded by this feature.

## Validation
Nothing in V2 is classified as validated on iPhone until an exact-SHA IPA from this branch passes CI, is installed on the real phone, and the user observes the behavior.
