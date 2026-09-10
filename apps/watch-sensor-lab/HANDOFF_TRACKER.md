# HANDOFF — Watch Tracker v0.4

Date: 2026-09-10

## Objective

Continue Watch Tracker as one native iPhone + Apple Watch activity tracker with the Watch as the single active-workout authority. v0.4 is the post-field-test quality/product version: metric correctness, diagnostics, richer live data, weather/environment context, persistent history, auto-pause, improved Auto and multisport.

The user explicitly requires that all field-test feedback be tracked and implemented unless a real Apple/platform/hardware limitation is demonstrated. Do not silently drop requirements.

Read before changing behavior:

- `apps/watch-sensor-lab/V040_SCOPE.md` — authoritative requirement/status ledger;
- `apps/watch-sensor-lab/FIELD_TEST_2026-09-10.md` — first real field-walk findings;
- `apps/watch-sensor-lab/RESEARCH_TRACKING_2026-09-10.md` — Apple/product research;
- `apps/watch-sensor-lab/V040_HARDWARE_TEST_2026-09-10.md` — first v0.4 hardware checkpoint.

Statuses move only with evidence: `TODO -> IMPLEMENTED -> CI_VALIDATED -> PHYSICALLY_VALIDATED`; partial foundations remain `PARTIAL`.

## Repository / worktree / branch

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-v040-20260910`
- confirmed Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`
- worktree was confirmed clean and on the expected branch before the first v0.4 hardware install.
- branch HEAD immediately before the documentation checkpoint was `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`.
- the hardware-checkpoint documentation commit moved remote HEAD to `cfa341a13722791ec699800dbc63868b5702164f`; this HANDOFF update moves it again. Always re-fetch before new code work and keep docs HEAD distinct from the tested application SHA.

## Immutable v0.3.1 physical baseline

- tested app SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- artifact id: `10141689980`
- exact IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\1bbd803f4916\WatchSensorLab-companion-unsigned-1bbd803f4916.ipa`
- IPA SHA-256: `8a8478b7b9ead0afdec7ad17dc3105f41d8e220ca39266ceb75ba9fa9fd6d4b6`
- installed iPhone bundle observed after iLoader signing: `com.rzbck.watchsensorlab.59858TV9N2`

First real field corpus:

- preserved PC ZIP: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- main session: `1789026745407`
- short pre-walk session: `1789026601777`
- user manually used Pause during the real walk.

Do not delete or rewrite this corpus.

Key baseline defects measured from the real walk:

- false max-speed summary ~30.2 km/h;
- D+/D- too noise-sensitive;
- all logged gyro values zero;
- dynamic Auto HealthKit semantics incomplete;
- Watch->iPhone motion otherwise very continuous;
- iPhone GPS generally good;
- Auto remained Walking for the whole walk with no false Run/Cycle switch.

## Current physically installed v0.4 candidate

Exact app candidate installed on real hardware:

- application SHA: `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`
- CI run: `34468523258` — SUCCESS
- artifact id: `10148601361`
- artifact name: `watch-sensor-lab-companion-3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`
- artifact digest: `sha256:34b5170d3ef5ffb706f2be509c15707f843f3f69ac4d604c14d92db8a7567dc9`
- downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\3efcc2cd313f\WatchSensorLab-companion-unsigned-3efcc2cd313f.ipa`
- local IPA SHA-256: `07b8aa7bec9e0716b569f6f5ec925c8299d4d3056405acd10a5451f8f1dc798f`

## Physical checkpoint already reported for `3efcc2cd...`

Validated on real hardware:

- iPhone app opens successfully;
- Apple Watch companion opens successfully;
- preserved existing activity history is visible on iPhone after upgrade;
- therefore this upgrade did not silently erase the v0.3.1 field activity.

Do NOT overstate this checkpoint. The user has not yet tested the new v0.4 workout behavior in this candidate.

Still not physically validated:

- recording a new v0.4 workout;
- live calories iPhone/Watch;
- weather/network capture;
- Watch recent-history screen/sync;
- gyro non-zero output;
- barometric D+/D-;
- speed-spike rejection;
- cadence/steps;
- auto-pause;
- post-STOP summary;
- Health/Fitness type, route and deletion;
- Auto Walk -> Run -> Walk and Cycle tests;
- manual/automatic multisport and triathlon.

## Legacy calories observation

The preserved v0.3.1 activity appears in v0.4 history but has no calorie value.

This is expected from the old storage schema: v0.3.1 `TrackerSummary` did not store active energy. v0.4 adds optional `activeEnergyKcal` and remains backward-compatible.

New explicit user requirement: enrich legacy history from the matching app-managed HealthKit workout when the match is unambiguous, especially calories and other trustworthy contextual values. Do not fabricate values or overwrite the preserved raw v0.3.1 evidence. If no trustworthy match exists, show the metric as unavailable.

## v0.4 code already CI-validated

The complete status is in `V040_SCOPE.md`. Major implemented/CI-validated foundations include:

- backward-compatible session/history schema with build/algorithm identity;
- iPhone persistent activity history + route detail;
- post-STOP summary presentation;
- persistent segment summaries;
- compact recent-history sync to Watch and Watch `Activités récentes` UI;
- live active calories, cadence and steps foundations;
- startup acquisition placeholders;
- compact iPhone status UI and unobstructed map;
- horizontal Watch live metric pages;
- sport-aware GPS plausibility filtering;
- Watch `CMAltimeter` elevation with GPS fallback;
- Watch gyro via `CMDeviceMotion.rotationRate`, raw gyro fallback, source logging;
- bounded event logging and Watch GPS forwarding;
- optional Watch-owned auto-pause foundation;
- conservative Auto Walk/Run/Cycle;
- manual HealthKit triathlon foundation;
- post-session Health contextual reader;
- provider-agnostic environmental snapshots using Open-Meteo currently;
- environmental analyzer with temperature/apparent temperature/humidity/pressure/wind/gusts and descriptive headwind/tailwind component.

Weather is a mandatory first-class requirement. It must remain stored with outdoor sessions because temperature, humidity and wind/headwind materially affect interpretation of walking/running/cycling effort. Never treat Watch wrist temperature as ambient temperature.

## Major remaining mandatory work

Do not call v0.4 finished until `V040_SCOPE.md` mandatory items meet their acceptance criteria. Important unfinished work includes:

- dynamic Auto HealthKit correctness if sport changes after workout start;
- reliable richer segment semantics across disconnections;
- activity-specific auto-pause settings and field tuning;
- hiking inference and Auto confidence/provenance UI;
- automatic triathlon transitions;
- general mixed master session such as bike -> walk -> run -> bike;
- automatic mixed-sport detection;
- richer per-segment metrics;
- zones/time-in-zone and explicit pause totals in summaries;
- legacy-history HealthKit enrichment for calories/context;
- all physical validations listed above;
- later roadmap: splits, haptics, rolling pace, exports, session comparison and data-quality indicators.

## Architecture constraints

- Watch remains the single active-workout authority.
- iPhone sends requests; Watch owns state/revisions and broadcasts authoritative state.
- HealthKit workout mirroring coordinates workout state.
- WatchConnectivity remains bootstrap/durable-context/fallback/sample transport.
- Preserve session/revision stale rejection.
- Preserve distinction between raw sensor value, accepted/filtered metric and displayed metric.
- Preserve provenance for Watch GPS, iPhone GPS, HealthKit, Core Motion and external weather.
- Do not modify iLoader/isideload absent a concrete signing/install failure.

## Exact-SHA workflow

Reuse the existing `.github/workflows/watch-sensor-lab-bootstrap.yml` and `UPDATE_WATCH_SENSOR_LAB.ps1` exact-SHA workflow. Never confuse CI success, artifact creation, IPA download, iLoader installation and real-device behavior.

Current Windows v0.4 worktree is confirmed at:

`E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`

The installed app under test remains SHA `3efcc2cd...` even though documentation commits move branch HEAD.

## Next exact step

Do not add more classifier complexity before collecting one short controlled v0.4 hardware corpus.

Run a short outdoor v0.4 session and check, in order:

1. startup/acquisition UI stability;
2. live HR + active calories + cadence/steps;
3. plausible weather snapshot including temperature and wind;
4. manual Pause/Resume stability;
5. STOP opens the finished summary;
6. new activity appears in iPhone history with v0.4 calories/weather;
7. recent activity reaches Watch history;
8. extract the new session corpus and compare gyro, GPS, D+/D-, max speed, cadence and event logging against baseline `1789026745407`.

After this controlled test, advance statuses only from observed evidence and then resume Auto-pause/classification/multisport work.

## Do not modify

- `main`;
- unrelated apps/worktrees;
- baseline corpus files;
- historical activities during normal upgrade tests;
- validated iLoader/isideload provisioning/transport without a concrete failure;
- Watch bundle identity/companion relationship without a proven packaging reason.
