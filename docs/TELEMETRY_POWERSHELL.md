# Live telemetry to PowerShell

The V2 app includes an opt-in telemetry stream intended for real-time iPhone debugging from a Windows PC.

## Recommended transport

Use **WebSocket** for normal debugging:

- one persistent TCP connection;
- low overhead at 1/2/5/10 Hz;
- server ACK for every packet, so the app can display acknowledgement count and round-trip time;
- works over a reachable LAN address or a Tailscale address;
- the same receiver also accepts HTTP POST as a fallback.

The iPhone sends nothing until `Telemetry > START STREAM` is pressed.

## Windows receiver

From the repository root in PowerShell 7:

```powershell
pwsh -ExecutionPolicy Bypass -File .\tools\Receive-IOSLabTelemetry.ps1 -Port 8787
```

The receiver uses `.NET TcpListener` directly rather than `HttpListener`, so it does not need an HTTP URL reservation simply to bind the port. Windows Firewall can still block incoming TCP; if the iPhone times out, inspect the firewall before changing the app.

At startup the script prints any Tailscale IPv4 address it can discover, plus LAN IPv4 candidates. Example shape:

```text
TAILSCALE WS   = ws://100.x.x.x:8787/telemetry
TAILSCALE HTTP = http://100.x.x.x:8787/telemetry
```

In the app, entering only `100.x.x.x:8787` is enough. The app adds the appropriate scheme and `/telemetry` path.

## Packet schema

Schema identifier: `ioslab.telemetry.v1`.

Snapshot packets include:

- exact build metadata embedded by CI;
- current app page and FPS;
- touch/drag event count and last coordinates;
- accelerometer, gravity, gyroscope and magnetometer;
- latest CoreLocation fix and authorization state when available;
- BLE state and latest discovered peripheral metadata when available;
- ARKit, LiDAR and NFC availability probes;
- model/platform/locale, screen size, battery state and local IP addresses.

Event packets cover diagnostic state changes such as page changes, telemetry link state, CoreLocation authorization and BLE state.

The receiver replies with compact ACK JSON containing the packet sequence number and receiver timestamp. The app derives RTT from that ACK.

## Privacy boundary

This diagnostic stream intentionally excludes:

- Apple Account information;
- UDID or other private device identifiers;
- SideStore/iloader pairing or signing material;
- clipboard contents;
- camera frames;
- microphone audio.

The destination is user-entered. There is no hard-coded telemetry collector and no public cloud endpoint in the app.

## PowerShell output

Default output is compact so it can be copied back into ChatGPT during debugging:

```text
[12:34:56.123] SNAP #42 page=GPS fps=60 touch=83 ACC=(0.01,-0.04,-0.98) GYRO=(0.00,0.02,0.01) GPS=45.xxxxxx,6.xxxxxx ±4.2m BAT=71%
[12:34:56.305] EVENT #43 page_changed :: page → Network
```

Use `-Raw` to print the complete JSON payload instead.
