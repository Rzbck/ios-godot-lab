# HANDOFF — Watch Sensor Tracker recorder branch

Date: 2026-09-09

## Objective

Prepare the first product-facing tracker/recorder layer while the separate iLoader/isideload one-click Watch installation validation continues.

The iPhone is the durable recorder. The Watch is a sensor companion. All samples must keep a timestamp and source so iPhone, Watch and derived data can share one session timeline.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-tracker-recorder-20260909`
- base commit: `82346d85db303e982b09c9486cdaf91ad7685516`
- base branch: `feat/watch-sensor-lab-bootstrap-20260909`
- existing Windows worktree for the bootstrap branch remains `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-lab`

This product branch was intentionally created separately so it does not change the exact IPA currently used to validate the iLoader tooling fix.

## Prepared in this branch

### iPhone recorder core

- append-only local session storage under `user://sessions/<session_id>/`;
- `samples.jsonl` for high-frequency samples;
- `summary.json` when a session is finalized;
- generic sample envelope with `timestamp`, `elapsed_ms`, `source`, `kind`, `payload`, `quality`;
- 20 Hz iPhone motion capture using Godot mobile input sensors;
- session start/stop UI;
- live iPhone accelerometer/gyroscope display;
- last-session summary display;
- generic `ingest_external_sample(...)` entry point reserved for native GPS/Watch/HealthKit bridge samples.

### Watch preparation

- retain existing WatchConnectivity activation and real-time motion sending;
- align outgoing Watch messages with the tracker schema (`source=watch`, `kind=motion`, timestamp, sequence, nested payload);
- include gravity and attitude from Core Motion device motion when available;
- preserve the existing native Watch application structure that was already physically launched successfully on the real Watch.

### Data schema

`apps/watch-sensor-lab/DATA_SCHEMA.md` documents the v1 session envelope and planned location/Watch/derived records.

## Important validation boundary

NOT yet validated for this tracker branch:

- Godot headless parse/import;
- iPhone unsigned build;
- watchOS unsigned build;
- embedded companion packaging;
- physical iPhone tracker behavior;
- physical Watch behavior with the updated tracker payload;
- GPS/location bridge;
- iPhone WatchConnectivity receiver;
- route/map rendering;
- speed/altitude derived metrics from real GPS;
- HealthKit/workout metrics.

Do not call the tracker feature complete yet.

## Current tooling isolation rule

For the current iLoader regression test, continue using the previously known Watch Sensor Lab IPA from the bootstrap branch / known functional app code. Do NOT switch the tooling test to this tracker branch until the one-click iPhone + Watch deployment path has been physically validated.

## Next product steps after initial branch CI

1. run the existing Watch Sensor Lab GitHub Actions workflow manually against this branch;
2. fix any Godot/Swift build issue without changing the validated packaging model;
3. implement the native iPhone bridge for `CLLocationManager` GPS/speed/altitude and `WCSessionDelegate` Watch message reception;
4. feed both into `ingest_external_sample(...)`;
5. add session review graphs/route rendering from persisted records;
6. only later add HealthKit/workout heart-rate data with explicit user authorization.

## Do not modify

- iLoader/isideload from this product branch;
- `iphone-lab-v2`;
- `main`;
- current exact-SHA tooling test artifacts;
- Watch bundle identity/companion relationship unless a new packaging failure proves it is necessary.
