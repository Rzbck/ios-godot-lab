# HANDOFF — Watch Tracker native product

Date: 2026-09-10

## Objective

Continue the real native iPhone + Apple Watch tracker as one shared session with Watch authority during an active workout. The next phase is no longer basic bring-up: it is data correctness, richer metrics, history, auto-pause and multisport, while preserving the exact-SHA deployment pipeline and the first real field-test corpus.

Detailed field-test findings and the evolving product backlog are in:

`apps/watch-sensor-lab/FIELD_TEST_2026-09-10.md`

Read that file before changing tracker behavior. Update TODO -> IMPLEMENTED -> CI_VALIDATED -> PHYSICALLY_VALIDATED explicitly.

## Repository / worktree / branch

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-tracker-recorder-20260909`
- Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-tracker-recorder`
- physically tested application SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- application version: `0.3.1 (4)`
- CI run for tested SHA: `34451272790` — SUCCESS
- CI artifact id: `10141689980`
- exact IPA SHA-256: `8a8478b7b9ead0afdec7ad17dc3105f41d8e220ca39266ceb75ba9fa9fd6d4b6`
- exact IPA path: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\1bbd803f4916\WatchSensorLab-companion-unsigned-1bbd803f4916.ipa`

Important: docs commits were added after the physically tested application SHA. Re-fetch branch and verify actual HEAD/status before code changes. Do not treat a docs-only HEAD as a new physically tested build.

## Current architecture

### Shared session

- Watch is the single authority while an Apple Watch workout is active.
- iPhone sends requests; Watch applies state, increments authority revision and broadcasts authoritative state.
- HealthKit workout mirroring is used for Watch/iPhone workout coordination.
- WatchConnectivity provides bootstrap/durable context/fallback and raw sample transport.
- stale authority/control state is rejected by revision/session sentinels.
- START / PAUSE / RESUME / STOP can be initiated from either side and should converge to one session.

### iPhone

- native SwiftUI + MapKit product UI;
- background Core Location route recording;
- Live Activity for Lock Screen / Dynamic Island;
- local durable session store under `Documents/Sessions/<session_id>/samples.jsonl` + `summary.json`;
- Watch HR/energy/motion ingestion;
- app-local purge command synchronized to Watch.

### Watch

- `HKWorkoutSession` + `HKLiveWorkoutBuilder` + `HKLiveWorkoutDataSource`;
- HealthKit workout saving enabled in `0.3.1 (4)`;
- `HKWorkoutRouteBuilder` route saving;
- Watch GPS, HR, active energy and motion;
- Auto currently conservatively classifies only Walk / Run / Cycle with 8-second stability and rejects low confidence;
- broad manual `HKWorkoutActivityType` catalog;
- `WKBackgroundModes`: workout processing + location.

## First real long field test — physically observed

The user completed a real outdoor walk on `1bbd803f...` and reports that the overall activity went well. Manual Pause was used during the outing.

Extracted field corpus is preserved on PC:

- `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806`
- `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- main session: `1789026745407`
- short pre-walk session: `1789026601777`

Do not delete this baseline corpus. It is the regression reference for algorithm/UI evolution.

Main measured results are recorded in `FIELD_TEST_2026-09-10.md`. Key points:

- long session logging completed without JSON corruption;
- active duration ~58m33s inside ~1h09m29s wall time, consistent with user manual pauses;
- Watch-authoritative distance ~5.798 km, iPhone integrated distance ~5.931 km (~2.29% difference);
- Auto stayed Walking for the full walking test with no false Run/Cycle switch;
- Watch->iPhone motion stream was ~4.89 samples/s against a 5 Hz target with one notable ~14 s gap;
- iPhone GPS quality was generally good (median horizontal accuracy ~5.1 m);
- HR stream was present and functional;
- data analysis exposed objective defects listed below.

## Current high-priority defects / next-version scope

Full checklist is in `FIELD_TEST_2026-09-10.md`. Do not lose these items:

1. Fix Auto HealthKit semantics: `automatic` currently creates a `.mixedCardio` workout even when effective activity is Walking.
2. Remove implausible Watch GPS/speed outliers; field summary reported ~30.2 km/h max during a walk.
3. Make elevation gain/loss robust; current accumulation is too sensitive to vertical GPS noise.
4. Diagnose gyroscope: all logged gyro axes were zero in the field corpus while accelerometer was valid.
5. Add bounded event logging for START/PAUSE/RESUME/STOP, authority revision, selection revision, Auto transitions, transport/reconnect and errors.
6. Log enough Watch GPS evidence to compare Watch and iPhone routes quantitatively.
7. Physically verify saved Health/Fitness workout type, HealthKit route and deletion of only Watch Tracker-created workout/route objects.
8. Perform deliberate Auto transition tests: Walk -> Run -> Walk, then Cycle.
9. Fix iPhone map being obscured by the redundant top-right Watch badge; compact GPS/Watch/Health status row.
10. Show live active calories on both iPhone and Watch.
11. Explore an additional horizontal Watch metric-page interaction while preserving glanceability and simple controls.
12. Research/implement feasible richer metrics: respiration-related data, gait/asymmetry/balance, cadence/step metrics, richer HR, barometric elevation and environmental context.
13. Add post-activity summary + persistent activity history on iPhone and useful recent-history access on Watch.
14. Preserve historical sessions across app upgrades; include schema/app/build/algorithm identity per session.
15. Add reliable weather/ambient-temperature context with provenance; never confuse wrist temperature with outdoor temperature.
16. Fix startup display jitter by gating/smoothing values and exposing acquisition state.
17. Add optional configurable activity-specific auto-pause with hysteresis and manual-control precedence.
18. Expand Auto conservatively, including hiking inference only if evidence supports it.
19. Design first-class multisport segments. Target triathlon swim -> bike -> run and general bike -> walk -> run outings in one coherent session, with manual transitions as reliable baseline and automatic transitions only when confidence is strong.

## HealthKit delete behavior

Current Watch code tags app-created HealthKit workout/route objects with private metadata and deletes matching route objects then matching workout objects during synchronized purge. This compiled in CI but deletion has NOT yet been physically validated. Do not claim it works until the user confirms in Health/Fitness.

## Exact-SHA sync / deployment workflow — preserve

Use existing script, do not invent a parallel downloader:

```powershell
& {
    $ErrorActionPreference = 'Stop'

    Set-Location 'E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-tracker-recorder'

    .\apps\watch-sensor-lab\UPDATE_WATCH_SENSOR_LAB.ps1 `
        -ExpectedBranch 'feat/watch-sensor-tracker-recorder-20260909' `
        -NoAutoBuild `
        -OpenFolder
}
```

The exact-SHA artifact then goes through the already validated iLoader/isideload Watch companion install path. Keep artifact/generated/install/physical-validation states distinct.

Observed installed iPhone bundle after iLoader signing for the tested build was `com.rzbck.watchsensorlab.59858TV9N2`; do not assume the suffix for every future install without querying the device.

## Tooling to preserve

Do not modify iLoader/isideload transport/provisioning unless a concrete signing/install problem requires it. The Watch companion/HealthKit install path is already validated. Do not touch `main` or `iphone-lab-v2`.

## Current validation boundary

Physically validated on the long field outing:

- app installed/launched on real iPhone + Apple Watch;
- long shared activity completed;
- user manually paused during activity;
- local iPhone session data survived and was extracted after the walk;
- GPS/HR/motion data streams exist in the extracted corpus;
- Auto did not falsely leave Walking during this walking test.

Not yet physically validated / not yet proven from this corpus:

- correct Health/Fitness activity type for Auto (known code issue: Mixed Cardio semantics);
- HealthKit route appearance/quality in Health/Fitness;
- deletion of app-created HealthKit workout + route;
- Run/Cycle Auto transitions;
- gyro functionality;
- trustworthy max speed / elevation gain;
- richer gait/respiration/environmental metrics;
- auto-pause;
- multisport.

## Next exact step

Before implementing the next version:

1. read `FIELD_TEST_2026-09-10.md`;
2. verify worktree clean/current branch/actual HEAD after the docs commits;
3. use the preserved field session as the regression baseline;
4. research current Apple capabilities for the requested richer metrics/multisport/background behavior;
5. implement the next version in prioritized slices, keeping field-test status updated after every CI/hardware milestone.
