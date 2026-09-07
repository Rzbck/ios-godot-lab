# iPhone Lab V2 — current feature scope

This branch turns the bootstrap probe into a reusable iPhone capability lab.

## UI / UX
- persistent page menu: Overview / Telemetry / Sensors / GPS / Network / Device;
- vertical page scrolling is intentionally allowed to begin over cards and labels; interactive controls use `MOUSE_FILTER_PASS` so drag gestures can bubble to the page `ScrollContainer`;
- dark near-black terminal-inspired visual system with compact information density;
- controls keep a 44 pt iOS touch target even when the visible treatment is compact;
- restrained glass treatment is reserved for navigation/status surfaces; content cards remain opaque dark surfaces so hierarchy and legibility stay clear;
- Godot boot image is disabled in `project.godot`.

The design direction follows Apple HIG guidance for Dark Mode, typography, accessibility and materials: high contrast, minimum readable text sizes, sufficiently large touch targets, and Liquid Glass used as a functional navigation/control layer rather than as decoration on every content surface.

## Live telemetry
V2 now includes an explicit opt-in telemetry mode intended for real-time debugging from Windows PowerShell.

- WebSocket is the recommended transport;
- HTTP POST is available as a fallback;
- endpoint is entered by the user and may be a LAN or Tailscale address;
- rates: 1 / 2 / 5 / 10 Hz;
- every packet carries a sequence number and the PowerShell receiver returns an ACK so RTT can be measured;
- `tools/Receive-IOSLabTelemetry.ps1` accepts WebSocket and HTTP on the same TCP port and prints compact copy/paste-friendly diagnostics.

Telemetry payloads use `ioslab.telemetry.v1` and include build identity, page/FPS, touch, motion sensors, latest GPS fix, BLE state, Apple capability probes, battery/system information and local IP addresses.

Privacy boundary: no Apple ID, UDID/private device identifier, signing/pairing material, clipboard contents, camera frames or microphone audio are included. There is no hard-coded collector and nothing is sent until the user starts the stream.

See `docs/TELEMETRY_POWERSHELL.md`.

## iPhone APIs
- direct Godot: touch/drag, accelerometer, gravity, gyroscope, magnetometer, haptics, camera feed, microphone level, clipboard;
- native `IOSLab` bridge: CoreLocation, BLE discovery with CoreBluetooth, ARKit availability, LiDAR scene-reconstruction availability, NFC reader availability and battery state;
- GPS page includes a small OpenStreetMap tile viewer and Apple Maps handoff.

## Networking
The Network page is intentionally generic for creative-computing use:
- HTTP/HTTPS with editable method, URL, headers and body;
- WebSocket/WSS connect/send/receive;
- raw UDP;
- OSC message with one string argument.

This can target a reachable LAN address, Tailscale peer, TouchDesigner service, SIGNAL endpoint, Python service, or public test endpoint. Plain HTTP/WS is enabled for this personal lab build; prefer HTTPS/WSS outside a trusted network.

## Validation
Nothing in V2 is classified as validated on iPhone until an exact-SHA IPA from this branch passes CI, is installed on the real phone, and the user observes the behavior.

Telemetry transport, UX and native capability code can be BUILD-validated by CI, but their real iPhone behavior must remain separately classified until device testing is completed.
