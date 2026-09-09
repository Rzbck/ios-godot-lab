# HANDOFF — Watch Tracker native product

Date: 2026-09-09

## Objective

Build a real, compact, polished iPhone + Apple Watch activity tracker. The two devices are two views/controllers of the same live session, not two independent sensor demos.

Required product behavior:

- START / PAUSE / RESUME / STOP from either iPhone or Apple Watch must converge to one shared session;
- iPhone: responsive native UI, Apple Map, live GPS trace, elapsed time, distance, speed, pace, altitude, elevation gain/loss, heart rate and session persistence;
- Apple Watch: glanceable workout UI, live metrics, heart rate, route map, terrain/elevation page and large controls;
- heart rate comes from a real HealthKit workout on Apple Watch;
- raw motion remains auxiliary recorded data, not the primary UI.

## Repository / worktree / branch

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-tracker-recorder-20260909`
- Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-tracker-recorder`
- native product code commit: `3c536fdc5b0fd0556b9017e425e7f610693890be`
- commit message: `feat(tracker): build native iPhone and Watch workout UI`
- parent: `5174f1e8e97493a1dd6821ed02f0f19139329edc`

This HANDOFF update is a docs commit on top of the native product code. Re-fetch the branch and verify the actual HEAD before doing any work; do not assume the code commit above is still branch HEAD.

## What was physically validated before the native product pivot

The previous tracker scaffold at `5174f1e...` was built and installed successfully on the real iPhone and Apple Watch through the validated iLoader path. The user confirmed that it technically worked, but explicitly rejected the product/UI quality:

- iPhone interface could drift / feel badly framed left-right and was not convincingly designed for iPhone;
- the screen looked like a sensor/debug recorder rather than a real tracker;
- Watch UI was essentially raw sensor/debug information;
- there was no real shared-map / shared-workout product experience.

That observation is the reason for the native product pivot. Do not regress to the old debug UI.

## Validated one-click deployment chain — preserve it

Physically validated tooling:

- iLoader SHA: `88ca24bbb6fd028f4f180a5f28a5683fba10e7f5`;
- pinned isideload SHA: `9d43554571360cb27c701efbe1fbd1f5456769ae`;
- iLoader workflow run: `34406032515`;
- Windows artifact: `windows-exe`, artifact ID `10125812841`;
- artifact ZIP digest: `sha256:739826aa9404bda38d666f6e10c7e0b1690b7d63918053d40e0f16bf5672da74`;
- exact local installer SHA-256: `4FE492056689602C9F02A35763959A14E11A522562825990C579C9390A74AEB9`;
- installer path: `E:\_Project\IOS APP\_Tools\iloader-watch\artifacts\88ca24bbb6fd028f4f180a5f28a5683fba10e7f5\nsis\iloader_2.3.1_x64-setup.exe`.

Physical result with the known-good regression IPA `WatchSensorLab-companion-unsigned-f539fe4105df.ipa`: iPhone installed/worked and the embedded Watch app installed/launched/worked.

Important tooling failure history before that success:

1. original nested Watch packaging / companion identifier problems;
2. direct Watch provisioning/signing and direct streaming_zip_conduit diagnostics proved the signed Watch bundle itself was valid;
3. one-click path then failed at the first CompanionProxy forwarding call;
4. reconnecting after iPhone install advanced to a real Watch pairing/trust prompt;
5. after trust was accepted it advanced again but failed forwarding `com.apple.mobile.installation_proxy`;
6. final fix used a fresh `com.apple.companion_proxy` service connection for each forwarding start/stop operation;
7. one-click iPhone + Watch install then physically succeeded.

Do not remove those tooling fixes just because the final blocker was CompanionProxy lifetime.

## Native product pivot in `3c536fdc...`

The product shell is now native SwiftUI on iPhone and native SwiftUI on watchOS. The old Godot recorder remains in the repository only as a retained prototype/regression reference; it is no longer the intended product UI.

### Native iPhone

New tree: `apps/watch-sensor-lab/iphone/`

Implemented:

- XcodeGen native iOS target, same bundle ID `com.rzbck.watchsensorlab`;
- full-screen MapKit SwiftUI map with user location and live `MapPolyline` route;
- safe-area-driven layout instead of the old fixed 390x844 product canvas;
- responsive bottom metrics/control panel;
- current elapsed time, distance, speed, pace, heart rate, altitude and elevation gain;
- large Start, Pause/Resume and Finish controls;
- Watch/GPS/Health readiness state;
- Core Location with navigation-level accuracy, point filtering and simple speed smoothing;
- route accumulation, distance, maximum speed and elevation gain/loss;
- WatchConnectivity receiver and sender;
- shared `tracker_state` and `tracker_control` messages;
- start/pause/resume/stop from iPhone mirrored to Watch;
- Watch-started session can create the matching iPhone recorder session;
- `HKHealthStore.startWatchApp(toHandle:)` used to wake/start the Watch workout from iPhone;
- `workoutSessionMirroringStartHandler` installed early so a Watch-started mirrored workout can wake the iPhone app and keep the mirrored session alive;
- durable native session log under `Documents/Sessions/<session_id>/samples.jsonl` plus `summary.json`;
- Watch heart-rate / energy / motion data ingestion.

### Native Apple Watch

Updated tree: `apps/watch-sensor-lab/watch/`

Implemented:

- HealthKit `HKWorkoutSession` + `HKLiveWorkoutBuilder` + `HKLiveWorkoutDataSource`;
- live current and average heart rate;
- active energy;
- HealthKit walking/running distance contribution;
- Core Location GPS, route, speed, altitude and elevation gain/loss;
- Core Motion auxiliary samples;
- WatchConnectivity shared session state/control;
- start from Watch and start from iPhone;
- iPhone workout configuration handled through `WKApplicationDelegate`;
- Watch workout starts mirroring to companion iPhone;
- watchOS-specific vertical paged UI using the Digital Crown pattern:
  1. primary metrics page — time, distance, heart rate, speed, ascent;
  2. route page — live map / route polyline;
  3. terrain page — altitude, ascent, descent, average HR;
  4. controls page — Pause/Resume and Finish;
- compact idle screen with readiness state and large Start button.

Bundle relationship remains unchanged:

- iPhone: `com.rzbck.watchsensorlab`
- Watch: `com.rzbck.watchsensorlab.watchkitapp`
- `WKCompanionAppBundleIdentifier = com.rzbck.watchsensorlab`
- `WKRunsIndependentlyOfCompanionApp = false`
- `WKApplication = true`

## UI/UX research basis

The implementation was deliberately based on current Apple platform guidance rather than making another arbitrary debug layout:

- watchOS should prioritize glanceable information and shallow interactions, with the Digital Crown used for vertical navigation;
- workout controls must be easy to find and hit while moving;
- iOS/watchOS controls are sized around Apple touch-target guidance;
- MapKit for SwiftUI is used for the native map and polyline route;
- HealthKit workout sessions/builders are used for real Watch heart-rate workout data and multi-device workout behavior;
- current Strava iPhone/Watch recording patterns were reviewed only for information hierarchy (map, live metrics, HR, elevation), not copied visually.

Design notes are in `apps/watch-sensor-lab/PRODUCT_UX.md`.

## Data schema

`apps/watch-sensor-lab/DATA_SCHEMA.md` is now schema v2 for the native product:

- location / route metrics;
- Watch heart rate;
- Watch motion;
- shared `tracker_state`;
- shared `tracker_control`;
- native session storage.

## Workflow changes

`.github/workflows/watch-sensor-lab-bootstrap.yml` now builds the native iPhone SwiftUI product plus the existing native watchOS companion, while still headless-verifying the retained Godot prototype.

The packaging contract is intentionally preserved:

- unsigned iPhone app;
- unsigned Watch app;
- Watch app embedded in `Watch/`;
- exact bundle/companion identity checks;
- exact-SHA IPA artifact naming compatible with the existing sync/deployment workflow.

The workflow also verifies that HealthKit and location usage declarations are present.

## IMPORTANT — current validation boundary

The native product commit `3c536fdc...` is **NOT YET CI-VALIDATED and NOT YET PHYSICALLY VALIDATED** at the time of this HANDOFF update.

Do not claim any of the following until evidence exists:

- Swift/iOS build success;
- Swift/watchOS build success;
- HealthKit compile/signing success;
- IPA packaging success;
- iPhone layout on physical device;
- Watch layout on physical device;
- real GPS trace quality;
- bidirectional START/PAUSE/STOP behavior on hardware;
- real heart-rate value on Watch or iPhone.

## HealthKit provisioning risk — likely next tooling boundary

The native targets declare `com.apple.developer.healthkit` and Health privacy usage strings.

However, the currently validated isideload backend does not yet have general entitlement/capability handling. Its signing flow largely uses entitlements from the generated provisioning profile. Therefore an unsigned CI build succeeding does **not** prove the final iLoader-signed app will retain a valid HealthKit entitlement.

If the exact native IPA fails during signing/install or HealthKit authorization does not work physically, investigate this before changing app UI:

- detect HealthKit entitlement in the iPhone/Watch bundles;
- enable the corresponding Apple App ID capability generically for each required App ID;
- regenerate the correct provisioning profiles;
- preserve the already validated Watch provisioning/routing/signing/streaming_zip_conduit logic;
- build a new exact-SHA isideload + iLoader pair and physically validate it.

Do not hard-code this application/team into generic tooling.

## Known script issue

`apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1` has a small control-flow/output bug discovered on the previous exact build: after it dispatched and successfully waited for a workflow, output from `gh workflow run` leaked from `Wait-ForExactBuild`, and the caller later received an unexpected object, causing:

`The property 'databaseId' cannot be found on this object.`

The actual workflow was successful; this was only the local sync script. Fix by suppressing the command output from `gh workflow run` while preserving its exit-code check. Do not replace the exact-SHA workflow with a competing downloader.

## Next exact step

1. fetch/fast-forward the tracker worktree and verify clean branch/HEAD;
2. run `.github/workflows/watch-sensor-lab-bootstrap.yml` for the exact current branch HEAD;
3. inspect/fix any Swift/HealthKit/MapKit build error without weakening the product UI architecture;
4. after CI success, download the exact-SHA IPA and install it with the physically validated iLoader build;
5. on hardware test both directions separately:
   - START on iPhone -> Watch joins, HR appears, both controls sync;
   - START on Watch -> iPhone joins the same session, map/route starts, controls sync;
6. record exact physical behavior and any error in this HANDOFF before further changes.

## Do not modify

- `main`;
- `iphone-lab-v2`;
- validated iLoader/isideload transport logic unless HealthKit provisioning specifically requires a tooling change;
- Watch bundle identity/companion relationship without a proven packaging reason;
- old physically validated tooling artifacts.
