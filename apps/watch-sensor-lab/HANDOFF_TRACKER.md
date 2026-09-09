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

## 2026-09-09 — one-click iPhone + Apple Watch deployment gate cleared

The separate tooling chantier has now reached the required physical milestone. The user physically confirmed that the same known-good regression IPA installs successfully on the iPhone and that the embedded Watch Sensor Lab companion installs and works correctly on the real Apple Watch through the one-click iLoader path.

Exact physically validated tooling chain:

- iLoader code SHA: `88ca24bbb6fd028f4f180a5f28a5683fba10e7f5`;
- pinned isideload SHA: `9d43554571360cb27c701efbe1fbd1f5456769ae`;
- iLoader workflow run: `34406032515`;
- first Windows attempt failed only while Tauri was downloading WiX (`os error 10054`) after the Rust/Tauri application binary had compiled;
- rerunning the failed jobs on the same exact SHA succeeded;
- Windows artifact: `windows-exe`, artifact ID `10125812841`;
- artifact ZIP digest: `sha256:739826aa9404bda38d666f6e10c7e0b1690b7d63918053d40e0f16bf5672da74`;
- exact local setup SHA-256: `4FE492056689602C9F02A35763959A14E11A522562825990C579C9390A74AEB9`;
- regression IPA used for the validation: `WatchSensorLab-companion-unsigned-f539fe4105df.ipa`.

Important failure progression before success:

1. the older one-click path failed at the initial Watch `StartForwardingServicePort` call with `device socket io failed`;
2. reconnecting CompanionProxy after the iPhone install advanced far enough to display the real Watch pairing/trust request;
3. after trust was accepted, the next blocker was forwarding `com.apple.mobile.installation_proxy`, again with `device socket io failed`;
4. the final isideload change switched to a fresh `com.apple.companion_proxy` service connection for each Watch forwarding start/stop command, matching the working pymobiledevice3 lifecycle;
5. with iLoader `88ca24b...` pinned to isideload `9d435545...`, the full one-click installation physically succeeded.

This strongly supports persistent CompanionProxy service reuse as the final transport-lifetime blocker. Earlier fixes for Watch provisioning/signing/routing and preserving the selected usbmux transport remain part of the validated chain; do not remove them merely because the last blocker was CompanionProxy lifetime.

The previous tracker isolation gate is therefore cleared. It is now appropriate to build and physically test this tracker branch with the same validated iLoader path.

### Next exact step

1. build the tracker branch with `.github/workflows/watch-sensor-lab-bootstrap.yml` at the exact tracker SHA;
2. require successful Godot/iPhone/watchOS/package verification before downloading the artifact;
3. use `apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1` from the tracker worktree with `-ExpectedBranch feat/watch-sensor-tracker-recorder-20260909` so the downloaded IPA is exact-SHA verified;
4. install that exact tracker IPA with the physically validated iLoader build above;
5. separately record iPhone tracker behavior and real Watch behavior. CI/build success must not be treated as physical validation.
