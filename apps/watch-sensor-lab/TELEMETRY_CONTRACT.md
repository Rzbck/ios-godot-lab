# Watch Sensor Lab — Telemetry contract

This file defines the permanent debugging contract for the iPhone + Apple Watch product.
Telemetry is product infrastructure, not a one-off diagnostic for one bug.

## Goal

A developer with the iPhone tethered to Windows must be able to understand what the app is doing without repeatedly asking for screenshots.
The telemetry stream must provide:

- user interaction context (screen/tab and taps, plus semantic actions where known);
- important state transitions;
- a bounded periodic full-state snapshot;
- connectivity / authorization state;
- workout lifecycle and selected/effective activity;
- post-session / finish-review state;
- HealthKit and historical-recovery diagnostics;
- errors and rejected operations;
- exact build SHA and process boot identity.

## Transport and storage

The canonical record format is one JSON object per line using schema `watch_sensor_lab_telemetry_v1`.
The unified device-log marker is:

`WSL_TELEMETRY|<json>`

The iPhone emits through unified logging and also keeps bounded local JSONL history.
The Windows receiver is:

`apps/watch-sensor-lab/LIVE_TELEMETRY.ps1`

It uses the existing `pymobiledevice3` USB path and writes host-side records under:

`artifacts/watch-sensor-lab/_TELEMETRY/`

including `LATEST_EVENT.json` and `LATEST_SNAPSHOT.json`.
USB is the normal development transport; same-Wi-Fi connectivity is not required.

## Record classes

- `lifecycle`: app/process/telemetry lifecycle.
- `action`: user or externally requested action.
- `event`: meaningful state transition/result.
- `snapshot`: bounded current state suitable for a complete debugger snapshot.
- `error`: failed operation with useful context.
- `relay`: structured telemetry relayed from the companion device.

Every record includes timestamp, monotonic uptime, sequence number, boot ID, platform and exact build SHA.

## Snapshot cadence

During normal foreground debugging, the iPhone publishes `app_state` approximately every 2 seconds and immediately on important transitions.
The snapshot is a current-state view, not an ever-growing event dump.
High-frequency raw sensor samples must not be printed continuously into unified logging. Raw sensor streams stay in the existing bounded/raw recorder paths and are summarized in telemetry.

## Required instrumentation for every future feature

A feature is not complete until its debug observability is considered. For every new user-facing function or state machine:

1. emit the user intent/action when it is invoked;
2. emit the resulting state transition, success, rejection or error;
3. add the durable current state needed to diagnose it to the appropriate snapshot;
4. include stable identifiers such as session ID / UUID where relevant;
5. never log secrets, credentials, authentication tokens or unrestricted personal payloads;
6. avoid unbounded arrays and high-frequency log spam;
7. keep telemetry non-blocking and never make product behavior depend on telemetry success.

If a new subsystem cannot reasonably fit in the root `app_state`, it must publish its own named bounded snapshot and be referenced by identifiers from root state.

## iPhone coverage

The iPhone root telemetry covers at minimum:

- current tab/screen and global tap coordinates;
- scene lifecycle;
- Watch reachability;
- Health authorization;
- workout phase/session ID;
- selected/effective activity;
- elapsed time, distance, speed, altitude/elevation;
- HR, energy, cadence, steps;
- GPS position/accuracy and route point count;
- pending command and status message;
- auto-pause state;
- finish-review requirement/suggestion;
- last workout summary;
- historical repair state;
- v4 recovery route/distance/HealthKit audit state;
- managed HealthKit workout audit records.

## Watch coverage

The shared telemetry core is compiled into the Watch target. Watch-specific semantic instrumentation and relay must use the existing `WCSession` owner rather than installing a competing delegate. It must remain low frequency and must not interfere with workout state messages.

Until direct Watch relay is enabled, Watch-derived workout state mirrored into `TrackerModel` remains visible in the iPhone snapshots. Direct Watch UI actions (for example finish-confirmation screens) must be added to the relay as part of the Watch telemetry extension, not diagnosed through a separate ad-hoc logger.

## Windows workflow

Normal live-debug command from the worktree:

```powershell
.\apps\watch-sensor-lab\LIVE_TELEMETRY.ps1
```

Optional full record printing:

```powershell
.\apps\watch-sensor-lab\LIVE_TELEMETRY.ps1 -Raw
```

The terminal can stay open while the user operates the app. The host JSONL is the artifact to inspect after a reproduction.

## Safety / performance

- Telemetry failure must never fail a workout or HealthKit operation.
- Device persistence rotates at a bounded size.
- Host captures are timestamped and bounded per manual debug run.
- Do not log every accelerometer/gyro/GPS/HR sample to unified logging.
- Prefer transition events plus summarized snapshots.
- Keep exact-SHA identity in every record so logs cannot be confused across IPA installs.
