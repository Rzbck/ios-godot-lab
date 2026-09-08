# Remote telemetry, live output and background tracks

This document is the durable procedure for using iOS Lab away from the computer.

## Tailscale over Wi-Fi or cellular

Tailscale assigns a stable tailnet IP to each device. The same computer Tailscale IP can be used when the iPhone moves between Wi-Fi and cellular data.

For telemetry:

1. Keep Tailscale connected on both the iPhone and the computer.
2. On Windows, run `tools/Prepare-IOSLabRemote.ps1` once from an elevated PowerShell. It creates an inbound TCP rule for the telemetry port restricted to the Tailscale `100.64.0.0/10` address range.
3. Run `tools/Receive-IOSLabTelemetry.ps1 -Port 8787`.
4. In iOS Lab > Telemetry, enter the computer Tailscale IP or MagicDNS name plus `:8787`.
5. The app retries WebSocket with backoff and falls back to HTTP after repeated WebSocket failures.

The app does not assume that a transport failure means the phone is broken. Connection errors are cached locally in `user://telemetry-offline.jsonl`. After a later successful connection, recent cached diagnostics are sent as an `offline_diagnostics` telemetry event.

## Live Output

`More > Network` is now a live router instead of a manual message sender. It routes the current iPhone state continuously.

Supported output transports can be enabled simultaneously:

- WebSocket / WSS: JSON `ioslab.live.v1`
- UDP: one UTF-8 JSON datagram per sample
- OSC: JSON string at `<prefix>/json`
- HTTP / HTTPS: JSON POST

Profiles: `all`, `motion`, `location`, `touch`, `device`.

Rates: 1 Hz, 5 Hz, 10 Hz, 30 Hz.

No host, port or public service is hard-coded.

## Track Recorder

`Location > Track Recorder` records route points to `user://tracks/` as JSONL and continuously updates a summary file.

The summary includes point count, distance, elevation gain/loss, elapsed duration, moving duration, average speed and maximum speed.

Starting Track Recorder enables iOS background location mode through the native IOSLab bridge. This is an explicit user action. Stopping the track disables background location again.

The iOS build declares the `location` background mode. Background behavior remains subject to iOS permissions and system policy and therefore requires physical-device validation.

## Validation

CI parse/smoke proves only parsing and scene instantiation. iOS CI success proves export/Xcode build/IPA packaging at the exact SHA. Tailscale remote connectivity, background tracking, long-running cellular behavior and live routing remain non-validated until observed on the iPhone and receiver.
