# HANDOFF — Watch Tracker v0.4

Date: 2026-09-10

## Objective

Continue Watch Tracker as one native iPhone + Apple Watch activity-tracking product. The Apple Watch remains the **single live workout authority**. v0.4 focuses on correctness, diagnostics, richer live/post metrics, weather, history, auto-pause, conservative Auto classification, multisport and correct HealthKit semantics.

Authoritative scope: `apps/watch-sensor-lab/V040_SCOPE.md`.
Baseline findings: `apps/watch-sensor-lab/FIELD_TEST_2026-09-10.md`.
Research: `apps/watch-sensor-lab/RESEARCH_TRACKING_2026-09-10.md`.
Hardware notes: `apps/watch-sensor-lab/V040_HARDWARE_TEST_2026-09-10.md`.

## Repository / worktree

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-v040-20260910`
- Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`
- verify `git status`, `git rev-parse HEAD` and remote branch before local work/install.
- do not modify `main`, `iphone-lab-v2`, baseline corpus, or iLoader/isideload unless a concrete failure requires it.

## Latest code milestone — mixed Auto HealthKit

Exact code SHA:

`7ed592b7b44473545f516857b2f6ad451b74d70f`

Validation:

- GitHub Actions run `34484069701` — **SUCCESS**.
- artifact id `10154989894`.
- artifact name `watch-sensor-lab-companion-7ed592b7b44473545f516857b2f6ad451b74d70f`.
- artifact digest `sha256:94dce10d0e3b462f896b840d4dae80e37f5d8b0e43b66557cb1429cfa6d842e1`.
- retained Godot prototype: success.
- iPhone build: success.
- watchOS build: success.
- HealthKit declarations: success.
- embedded companion assembly: success.
- exact-SHA IPA package/upload: success.
- **no physical validation yet for this code milestone**.

This HANDOFF documentation commit is expected to be ahead of the code SHA above. For installation, always use the current branch HEAD and its own exact-SHA SUCCESS artifact; BuildInfo will then identify that final candidate SHA even when the only delta after `7ed592b7...` is documentation.

## New HealthKit mixed-Auto architecture

Problem solved in code: Apple HealthKit does not support arbitrary Walk/Run/Cycle child activities inside a normal workout; only defined multisport such as `swimBikeRun` allows different child types. A dynamic Auto session must therefore not remain falsely typed as its initial Walking workout.

Implementation: `watch/Sources/WatchAutoHealthReconciler.swift`.

Behavior:

- live recording architecture is unchanged: Watch workout session remains active/authoritative during exercise and continues producing HR, energy, GPS, route and motion evidence;
- reconciler binds only to **Auto** classification and records effective-activity segment boundaries;
- segment plan is persisted in Watch `UserDefaults` for retry after relaunch;
- after STOP, it finds Watch Tracker-owned HealthKit workout/route by `com.rzbck.watchsensorlab.session_id`;
- if Auto remained one sport, it does nothing and keeps the original workout;
- if multiple sports were actually detected, it creates one correctly typed `HKWorkout` per segment using `HKWorkoutBuilder`;
- original app-owned associated HR, active-energy and distance samples are assigned to matching segment windows rather than synthesizing new physiology;
- original workout events are assigned by segment time window;
- original `HKWorkoutRoute` points are read and split into separate segment routes;
- every replacement carries the same master Watch Tracker `session_id`, plus segment index/count/activity, algorithm and exact build SHA metadata;
- reconciliation is transactional: original workout is deleted only after all replacement workouts/routes succeed;
- on any creation failure, newly created replacement objects are rolled back and the original stays;
- if the original workout/route is not durable yet, reconciliation retries; unresolved plans remain persisted for later retry;
- partial replacement leftovers can be cleaned/rebuilt when the original still exists;
- diagnostic events `health_auto_reconcile_failed`, `health_auto_reconcile_completed`, and `health_auto_reconciled` are sent reliably to iPhone session logs.

This is **CI_VALIDATED / PARTIAL**, not physically validated. Runtime tests must prove HealthKit accepts/re-associates the app-owned samples as expected and that Health/Fitness displays segment workouts/routes/calories/HR correctly. Failure safety must also be observed: if reconciliation cannot complete, the original workout must remain.

## Prior validated code milestone

`cf6b9550a54cb36f1111e94a5a2054384c3a1564`, run `34481920623` — SUCCESS, artifact `10154036552`.

It includes the accumulated v0.4 analytics/UI slice:

- per-sport auto-pause settings;
- Hiking inference;
- Auto confidence/provenance live + history;
- pause total/count/manual-vs-auto breakdown;
- HR zones/time-in-zone;
- richer per-segment active time, pauses, distance, calories, elevation, HR, max speed, cadence;
- delayed reliable Watch event/snapshot recovery;
- mandatory post-STOP activity confirmation/correction;
- weather/environment context and progression charts;
- recent Watch history.

## Immutable physical baseline

- tested SHA `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`, version `0.3.1 (4)`, run `34451272790` SUCCESS.
- main field session `1789026745407`.
- archive `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`.
- baseline measured: ~5.798 km Watch distance, ~5.931 km iPhone distance, ~10m56s pause/excluded, HR functional; defects included ~30.2 km/h false walking max, noisy D+/D-, zero logged gyro and wrong dynamic-Auto HealthKit semantics.
- never purge/rewrite this corpus.

## Existing physical v0.4 checkpoint

Candidate `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37` physically validated only for:

- iPhone launches;
- Watch launches;
- normal upgrade preserves existing iPhone history;
- baseline activity remains visible.

Everything added since then remains pending real-device validation.

## Next physical test candidate

Use the final current branch HEAD after this documentation update, only after its exact GitHub Actions run is SUCCESS. Sync/download through the existing script:

`apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1`

with:

`-ExpectedBranch 'feat/watch-sensor-v040-20260910'`

The script verifies clean branch/worktree, fast-forwards only this branch, resolves the exact-SHA run, downloads the exact companion artifact, validates metadata/companion presence/IPA SHA-256 and writes it under the repository artifact directory. Then use the existing iLoader flow for installation. Do not invent a second downloader/install workflow.

## Focused physical test order

1. Upgrade/install without purge; confirm old history still exists on iPhone and recent history on Watch.
2. Start a short **Auto** workout and verify startup, HR, calories, cadence/steps, GPS, D+/D-, Watch pages and background/Live Activity behavior.
3. Perform a deliberate **Walk → Run → Walk** with each phase held long enough to cross Auto dwell/hysteresis; optionally test Cycle separately.
4. Use one manual Pause/Resume and, separately if practical, let auto-pause trigger once.
5. STOP from Watch; confirm iPhone post-summary opens, requires activity confirmation, shows pauses, HR zones, Auto decision provenance, segment analytics, route and environmental context.
6. Open Health/Fitness. For a mixed Auto session, verify it no longer remains one falsely typed initial workout: expect correctly typed segment workouts sharing the same Watch Tracker master identity, with coherent time windows/routes and no duplicate original container.
7. If Health/Fitness still shows the original single workout, **do not delete/purge anything**. The transactional fallback should have preserved it; extract logs/corpus and inspect `health_auto_reconcile_*` events.
8. Extract the new session corpus and compare speed/D+/gyro/GPS continuity/Auto behavior against baseline `1789026745407`.

## Architecture constraints

- Watch remains the single active-workout authority.
- iPhone sends requests; Watch applies state/revisions and broadcasts authority.
- HealthKit mirroring coordinates live Watch/iPhone workout state.
- WatchConnectivity remains bootstrap/fallback/sample/durable transport.
- preserve revision/session stale rejection.
- preserve raw vs accepted/filtered vs displayed metric distinction.
- preserve provenance for Watch GPS, iPhone GPS, HealthKit, Core Motion, Watch Tracker inference and weather.
- general mixed Auto must never be mislabeled as triathlon merely to satisfy HealthKit restrictions.
- manual triathlon stays the existing `swimBikeRun` path; the new reconciler does not replace it.
- no release/main merge without explicit user approval.

## Next development step after the physical test

Use the observed device behavior and extracted corpus as the source of truth. First fix any HealthKit reconciliation/runtime issue, sync regression, speed/D+/gyro/cadence/weather defect, or false Auto transition found in the test. Only then continue lower-priority roadmap work (splits, haptics, rolling pace/speed, exports, comparisons, quality score, legacy HealthKit enrichment).
