# HANDOFF — Watch Tracker v0.4

Date: 2026-09-10

## Objective

Continue Watch Tracker as one native iPhone + Apple Watch activity-tracking product with the Watch as the single live workout authority. v0.4 is the post-field-test quality/product version: metric correctness, diagnostics, richer live data, weather/environment context, history, auto-pause, improved Auto and multisport.

The user explicitly requires that **all field-test feedback be tracked and implemented**, unless a real Apple/platform/hardware limitation is demonstrated. Do not silently drop requirements.

Authoritative requirement/status ledger:

`apps/watch-sensor-lab/V040_SCOPE.md`

Detailed baseline field findings:

`apps/watch-sensor-lab/FIELD_TEST_2026-09-10.md`

Capability/product research:

`apps/watch-sensor-lab/RESEARCH_TRACKING_2026-09-10.md`

Read all three before changing tracker behavior. Every requirement moves through `TODO -> IMPLEMENTED -> CI_VALIDATED -> PHYSICALLY_VALIDATED`; partial foundations stay marked `PARTIAL` until their acceptance criterion is met.

## Repository / branches / worktrees

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- v0.4 branch: `feat/watch-sensor-v040-20260910`
- v0.4 first CI-validated code SHA: `b8702027f2546189326e747e8c842177120c303c`
- v0.4 CI run: `34464673739` — SUCCESS
- current branch HEAD after scope/HANDOFF documentation commits: verify from Git before work; docs commits are not new physical validation.
- old Windows worktree still belongs to the earlier tracker branch unless explicitly changed: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-tracker-recorder`
- a dedicated local v0.4 worktree has NOT yet been confirmed from Windows in this chat. Create/verify one before local code edits or exact-SHA sync; do not assume the old worktree switched branches.

## Immutable physical baseline

Physically tested application build:

- branch at time of test: `feat/watch-sensor-tracker-recorder-20260909`
- SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- artifact id: `10141689980`
- exact downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\1bbd803f4916\WatchSensorLab-companion-unsigned-1bbd803f4916.ipa`
- IPA SHA-256: `8a8478b7b9ead0afdec7ad17dc3105f41d8e220ca39266ceb75ba9fa9fd6d4b6`
- installed iPhone bundle observed after iLoader signing: `com.rzbck.watchsensorlab.59858TV9N2`

User completed a real outdoor walk successfully and manually used Pause. Preserve this as the before-v0.4 reference.

Extracted corpus:

- root: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806`
- ZIP: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- main session: `1789026745407`
- short pre-walk session: `1789026601777`

Do not delete/rewrite this corpus. Normal upgrades must preserve historical activities.

## Baseline field findings

Key measured results from `1789026745407`:

- wall span ~1h09m29s; active duration ~58m33s; ~10m56s excluded/paused;
- Watch-authoritative distance ~5.798 km;
- iPhone integrated GPS distance ~5.931 km; delta ~2.29%;
- Auto remained Walking for the whole walk with no false Run/Cycle switch;
- Watch->iPhone motion ~4.89 samples/s with one notable ~14 s gap;
- iPhone GPS median horizontal accuracy ~5.1 m;
- HR functional;
- objective defects: ~30.2 km/h false max-speed summary, D+/D- too noise-sensitive, all logged gyro values zero, Auto HealthKit type semantics wrong for a dynamic Auto session.

All user UI/product feedback and acceptance criteria are enumerated in `V040_SCOPE.md`; that file is the completion contract.

## v0.4 code already CI-validated at `b8702027...`

The first v0.4 implementation batch compiled and packaged successfully on exact SHA `b8702027...` in run `34464673739`.

Implemented foundations include:

- richer backward-compatible session summaries/history schema with build/algorithm identity;
- iPhone activity history + detail route view;
- weather context model and coarse outdoor snapshots including temperature, apparent temperature, humidity, pressure, wind speed/direction/gusts and provider provenance;
- Open-Meteo provider for now to avoid adding an unvalidated WeatherKit entitlement to the signing pipeline;
- compact iPhone UI with redundant Watch badge removed from the map header;
- horizontal live metric ribbon on iPhone;
- live calories, cadence and steps surfaces;
- startup acquisition gating/placeholders;
- horizontal Watch effort metrics page nested inside the existing vertical workout navigation;
- sport-aware GPS plausibility filtering;
- Watch barometric relative-altitude accumulation via `CMAltimeter`, GPS fallback;
- Watch gyro pipeline preferring `CMDeviceMotion.rotationRate` with raw gyro fallback and source logging;
- lightweight event logging and Watch GPS sample forwarding for later comparisons;
- optional Watch-owned auto-pause foundation with sport-dependent delay and manual/auto distinction;
- conservative Auto Walk/Run/Cycle remains;
- triathlon `swimBikeRun` foundation with manual swim -> transition -> bike -> transition -> run progression.

These are **CI_VALIDATED only**, not physically validated. Refer to `V040_SCOPE.md` for items that remain partial despite the foundation.

## Important remaining work — do not lose

The complete list is `V040_SCOPE.md`. Major unfinished categories include:

- dynamic Auto HealthKit/multi-segment correctness when the detected sport changes after session start;
- hardware validation of speed filter, barometric D+/D-, gyro, cadence, weather, auto-pause and UI;
- actual Health/Fitness workout type/route/deletion validation;
- deliberate Walk -> Run -> Walk and Cycle Auto tests;
- proper immediate post-STOP summary polish;
- recent history on Watch;
- gait/asymmetry/step-length/double-support contextual HealthKit metrics where available;
- respiration handling without fabricating a live Apple respiratory stream;
- richer HR/running metrics and zones;
- environmental effort interpretation including headwind/tailwind correlation;
- activity-specific auto-pause settings/tuning;
- hiking inference;
- persisted first-class segment model;
- automatic triathlon transitions;
- general mixed outing master session, e.g. bike -> walk -> run -> bike;
- automatic mixed-sport transitions;
- splits, haptic alerts, rolling pace, exports, comparisons and sensor-quality indicators.

Do not call v0.4 finished until mandatory `V040-001` through `V040-034` meet the completion rule in `V040_SCOPE.md`.

## Architecture constraints

- Watch remains the single active-workout authority.
- iPhone sends requests; Watch applies state/revisions and broadcasts authoritative state.
- HealthKit workout mirroring coordinates Watch/iPhone workout state.
- WatchConnectivity remains bootstrap/durable-context/fallback/sample transport.
- Keep revision/session stale rejection.
- Never introduce independent competing workout state on iPhone.
- Preserve distinction between raw sensor value, accepted/filtered metric and displayed metric.
- Preserve provenance for Watch GPS, iPhone GPS, HealthKit, Core Motion and external weather.

## Weather principle

Environmental conditions are first-class activity context because the same pace/HR can represent different effort under heat/cold/headwind.

Current v0.4 storage captures temperature, apparent temperature, humidity, pressure, wind speed, wind direction, gusts, condition code, timestamp, location and provider. Future analysis should correlate route heading with wind direction to distinguish headwind/tailwind when evidence is sufficient.

Never treat Apple Watch wrist temperature as ambient temperature.

WeatherKit remains a possible future provider, but do not add its entitlement until the existing iLoader/isideload signing/provisioning path is explicitly validated for that capability. The session storage is provider-agnostic so the provider can be swapped later.

## HealthKit / multisport principle

- Auto must not save a knowingly false `.mixedCardio` workout for a simple detected walk/run/ride.
- Dynamic mixed Auto requires correct segment semantics; current v0.4 foundation is still partial.
- Triathlon should use HealthKit `.swimBikeRun` with swim/bike/run sub-activities and transition activities.
- General mixed outings such as bike -> walk -> run may need one Watch Tracker master session mapped to semantically correct HealthKit object(s), rather than pretending HealthKit supports arbitrary sub-activity combinations inside one triathlon workout.

## Exact-SHA build/install workflow

Preserve the existing workflow `.github/workflows/watch-sensor-lab-bootstrap.yml`; v0.4 branch support was added instead of creating a second pipeline.

The existing exact-SHA PowerShell/iLoader flow must be reused. Before local sync, first create/verify the correct v0.4 worktree and update `UPDATE_WATCH_SENSOR_LAB.ps1` parameters only if needed for the new branch; do not silently run the old `ExpectedBranch` value against the v0.4 branch.

Do not modify iLoader/isideload unless a concrete signing/install failure proves it necessary.

## Validation rules

Never conflate:

- Swift/Xcode compile;
- CI SUCCESS;
- IPA packaged;
- exact IPA downloaded;
- iLoader signed/installed;
- iPhone launched;
- Watch launched;
- physical behavior validated.

The first v0.4 CI proves only build/package success. Every relevant feature still needs real hardware confirmation and the ledger must be updated after each test.

## Next exact development step

1. verify remote v0.4 branch HEAD and create/verify a dedicated local Windows v0.4 worktree before local edits;
2. continue the mandatory ledger in `V040_SCOPE.md`, starting with unfinished correctness/segment semantics rather than cosmetic extras;
3. keep exact-SHA CI green after each coherent slice;
4. when a candidate is sufficiently complete, exact-SHA sync/install through the existing script+iLoader chain;
5. install as an upgrade, verify the baseline historical activity remains visible, then run focused hardware tests for speed/D+/gyro/cadence/weather/auto-pause/HealthKit route+delete/Auto transitions;
6. extract the new session corpus and compare it quantitatively to `1789026745407`;
7. advance `V040_SCOPE.md` statuses only from evidence.

## Do not modify

- `main`;
- `iphone-lab-v2`;
- baseline corpus files;
- validated iLoader/isideload transport/provisioning without a concrete failure;
- Watch bundle identity/companion relationship without a proven packaging reason;
- historical activities during normal upgrade testing.
