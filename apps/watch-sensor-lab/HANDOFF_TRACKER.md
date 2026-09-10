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
- first v0.4 CI-validated code SHA: `b8702027f2546189326e747e8c842177120c303c`
- first v0.4 CI run: `34464673739` — SUCCESS
- summary/segments/Health-context code SHA: `89e04aa508e978a21627a98cccc4a21e99f64278`
- CI run: `34467626579` — SUCCESS
- artifact id: `10148264237`
- Watch recent-history code SHA: `af38d7c7fc90f44873bdd4bf00e79960bd2c821c`
- CI run: `34468156004` — SUCCESS
- artifact id: `10148457809`
- artifact digest: `sha256:d2140e14b0750f1d606240adc0b96e8b0cce481e21c800c917b4e4a46a45f992`
- current branch HEAD may be later docs-only commits; verify branch before new code work and keep the exact tested code SHA distinct from docs-only HEAD.
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

## v0.4 implementation state

### First CI-validated slice — `b8702027...`

Implemented and compiled/packaged:

- richer backward-compatible session/history schema with build/algorithm identity;
- iPhone activity history + route detail;
- weather snapshots including temperature/apparent temperature/humidity/pressure/wind speed/direction/gusts/provider;
- Open-Meteo provider abstraction; WeatherKit entitlement intentionally not introduced yet;
- compact iPhone UI; redundant Watch map badge removed;
- horizontal iPhone metrics ribbon;
- live calories, cadence, steps;
- startup acquisition placeholders;
- horizontal Watch effort page inside vertical workout navigation;
- sport-aware GPS plausibility filtering;
- Watch `CMAltimeter` elevation with GPS fallback;
- Watch gyro via `CMDeviceMotion.rotationRate`, raw gyro fallback, source logging;
- event logging + Watch GPS sample forwarding;
- optional Watch-owned auto-pause foundation;
- conservative Auto Walk/Run/Cycle;
- manual HealthKit triathlon foundation with swim/transition/bike/transition/run.

### Second CI-validated slice — `89e04aa...`

Implemented and compiled/packaged:

- persistent segment summaries derived from durable Auto/multisport events at session finish;
- automatic just-finished summary presentation after STOP;
- summary includes route, core metrics, segments, weather/environment effort context and technical trace;
- HealthKit contextual reader for walking speed, step length, asymmetry, double support, Walking Steadiness, HR max/recovery, running speed/power/stride/ground-contact/vertical-oscillation and respiratory context where Apple has samples;
- environmental analyzer computes descriptive average conditions and route-heading vs wind-direction headwind/tailwind component.

The initial attempt at this slice (`505d9a467474864d5891b8de6875aa18084b37a6`, run `34467348676`) failed only because the `HealthContextReader.add` helper declared `detail` unlabeled while calls used `detail:`. This was corrected at `89e04aa...`; the corrected exact-SHA run is SUCCESS. Preserve this CI history rather than claiming the failed SHA was validated.

### Third CI-validated slice — `af38d7c7...`

Implemented and compiled/packaged:

- iPhone publishes compact digests for up to 8 recent activities to Watch through queued WatchConnectivity user info;
- Watch persists the received digests locally;
- Watch ready screen exposes `Activités récentes`;
- recent entries show activity/date/duration/distance/calories/D+.

Everything above is **CI_VALIDATED only**, not physically validated. `V040_SCOPE.md` remains authoritative for partial/remaining acceptance criteria.

## Important remaining work — do not lose

The complete list is `V040_SCOPE.md`. Major unfinished categories include:

- dynamic Auto HealthKit correctness when sport changes after session start;
- guarantee segment-event persistence across Watch/iPhone disconnection and add richer per-segment metrics;
- hardware validation of speed filter, D+/D-, gyro, cadence, weather, auto-pause, history sync and UI;
- actual Health/Fitness workout type/route/deletion validation;
- deliberate Walk -> Run -> Walk and Cycle Auto tests;
- pause totals/events and HR/pace/speed zones in finished summaries;
- activity-specific auto-pause settings/tuning;
- hiking inference + Auto confidence/provenance UI;
- automatic triathlon transitions;
- general mixed outing master session, e.g. bike -> walk -> run -> bike;
- automatic mixed-sport transitions;
- splits, haptic alerts, rolling pace, exports, comparisons and sensor-quality indicators;
- respiration remains contextual Health data unless an experimental workout-time estimator is explicitly built/labeled/validated.

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

Current v0.4 storage captures temperature, apparent temperature, humidity, pressure, wind speed, wind direction, gusts, condition code, timestamp, location and provider. Post-session analysis now derives a descriptive headwind/tailwind component from route heading and meteorological wind direction when enough data exists.

Never treat Apple Watch wrist temperature as ambient temperature.

WeatherKit remains a possible future provider, but do not add its entitlement until the existing iLoader/isideload signing/provisioning path is explicitly validated for that capability. The session storage is provider-agnostic so the provider can be swapped later.

## HealthKit / multisport principle

- Auto must not save a knowingly false `.mixedCardio` workout for a simple detected walk/run/ride.
- Dynamic mixed Auto requires correct segment semantics; current v0.4 foundation is still partial.
- Triathlon should use HealthKit `.swimBikeRun` with swim/bike/run sub-activities and transition activities.
- General mixed outings such as bike -> walk -> run may need one Watch Tracker master session mapped to semantically correct HealthKit object(s), rather than pretending HealthKit supports arbitrary sub-activity combinations inside one triathlon workout.
- Session segment summaries now exist, but reliable segment event delivery across disconnection is not yet proven/finished.

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

No v0.4 behavior has been physically validated yet. Every relevant feature still needs real hardware confirmation and the ledger must be updated after each test.

## Next exact development step

1. verify remote v0.4 branch HEAD; docs commits may be ahead of the last exact code artifact;
2. continue mandatory `V040_SCOPE.md` items, prioritizing Auto/multisport semantic correctness, segment reliability, activity-specific auto-pause, hiking/confidence and summary analytics before cosmetic extras;
3. keep exact-SHA CI green after each coherent slice;
4. before first v0.4 physical test, create/verify a dedicated Windows v0.4 worktree and preserve the existing exact-SHA sync+iLoader path;
5. install v0.4 as an upgrade, first verify baseline history survives, then run focused speed/D+/gyro/cadence/weather/auto-pause/history/HealthKit/Auto tests;
6. extract the new session corpus and compare quantitatively to `1789026745407`;
7. advance `V040_SCOPE.md` statuses only from evidence.

## Do not modify

- `main`;
- `iphone-lab-v2`;
- baseline corpus files;
- validated iLoader/isideload transport/provisioning without a concrete failure;
- Watch bundle identity/companion relationship without a proven packaging reason;
- historical activities during normal upgrade testing.
