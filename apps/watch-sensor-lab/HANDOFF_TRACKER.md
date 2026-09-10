# HANDOFF — Watch Tracker v0.4

Date: 2026-09-10

## Objective

Continue Watch Tracker as one native iPhone + Apple Watch activity-tracking product with the Watch as the single live workout authority.

v0.4 is the post-field-test correctness/product version: trustworthy metrics, diagnostics, weather/environment context, persistent history, activity review, auto-pause, conservative Auto classification, multisport/triathlon and semantically correct HealthKit representation.

The user explicitly requires that all field-test feedback remain tracked. Do not silently drop a requirement because a partial implementation exists.

Authoritative requirement/status ledger:

`apps/watch-sensor-lab/V040_SCOPE.md`

Baseline field findings:

`apps/watch-sensor-lab/FIELD_TEST_2026-09-10.md`

Research/capability notes:

`apps/watch-sensor-lab/RESEARCH_TRACKING_2026-09-10.md`

First v0.4 hardware checkpoint:

`apps/watch-sensor-lab/V040_HARDWARE_CHECKPOINT_2026-09-10.md`

## Repository / branch / worktree

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-v040-20260910`
- dedicated Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`
- never assume the local worktree has pulled the latest remote commit; verify `git status`, `git rev-parse HEAD` and `origin/feat/watch-sensor-v040-20260910` before local work/install.

### Latest exact CI-validated code milestone

- code SHA: `cf6b9550a54cb36f1111e94a5a2054384c3a1564`
- CI run: `34481920623` — **SUCCESS**
- artifact id: `10154036552`
- artifact name: `watch-sensor-lab-companion-cf6b9550a54cb36f1111e94a5a2054384c3a1564`
- artifact digest: `sha256:d5e663f41a53eed23357a8d7565dde53c97ba891bbadf6db3783c249c120dbaa`
- CI validated: retained Godot prototype, unsigned iPhone build, watchOS build, HealthKit declarations, embedded companion assembly, exact-SHA IPA packaging and artifact upload.
- **not physically validated** on iPhone/Watch yet.

Documentation commits may be ahead of this code SHA. Treat `cf6b9550...` as the latest exact code+CI checkpoint until a later code SHA is explicitly validated.

### Earlier important v0.4 checkpoints

- first v0.4 code/CI SHA: `b8702027f2546189326e747e8c842177120c303c`, run `34464673739` — SUCCESS.
- summary/segments/Health-context SHA: `89e04aa508e978a21627a98cccc4a21e99f64278`, run `34467626579` — SUCCESS.
- Watch recent-history SHA: `af38d7c7fc90f44873bdd4bf00e79960bd2c821c`, run `34468156004` — SUCCESS.
- first physically launched v0.4 candidate: `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`, run `34468523258` — SUCCESS.

## Immutable physical baseline

Real outdoor baseline build:

- branch at test time: `feat/watch-sensor-tracker-recorder-20260909`
- SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- main field session: `1789026745407`
- short pre-walk session: `1789026601777`
- extracted corpus root: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806`
- ZIP: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`

Do not delete/rewrite this corpus or silently purge the matching historical activity during upgrade tests.

Baseline measured findings from the long walk:

- wall span ~1h09m29s;
- active duration ~58m33s;
- ~10m56s excluded/paused;
- Watch-authoritative distance ~5.798 km;
- iPhone integrated GPS distance ~5.931 km; delta ~2.29%;
- Auto remained Walking with no false Run/Cycle switch;
- Watch->iPhone motion ~4.89 samples/s with one notable ~14 s gap;
- iPhone GPS median horizontal accuracy ~5.1 m;
- HR functional;
- defects: ~30.2 km/h false walking max speed, noisy D+/D-, logged gyro all zero, dynamic Auto HealthKit semantics incorrect.

## Physical validation state

First v0.4 hardware candidate `3efcc2cd...`:

- iPhone launch: **PHYSICALLY_VALIDATED**;
- Apple Watch launch: **PHYSICALLY_VALIDATED**;
- normal upgrade preserved the baseline activity on iPhone: **PHYSICALLY_VALIDATED**;
- baseline activity visible in iPhone history: **PHYSICALLY_VALIDATED**.

Still not physically validated on the current code line:

- new-session calories and calorie progression;
- weather snapshots / wind / gust / humidity / pressure and environmental summary;
- gyro non-zero data/source;
- barometric D+/D-;
- cadence/steps;
- speed-spike filtering/max speed;
- startup smoothing;
- Watch horizontal data pages;
- Watch recent-history sync/offline persistence;
- per-sport auto-pause thresholds and manual-vs-auto precedence;
- STOP review/confirmation flow;
- pause breakdown and HR zones;
- Auto confidence/provenance UI/history;
- Hiking inference;
- richer per-segment analytics;
- delayed Watch-event recovery after disconnect;
- HealthKit route/type/exact deletion;
- deliberate Walk -> Run -> Walk and Cycle Auto transitions;
- manual/automatic triathlon transitions.

Do not call any of these physically validated from CI alone.

## Current implementation state at `cf6b9550...`

### Core authority / telemetry

- Watch remains the live workout authority.
- iPhone sends requests; Watch applies revisioned state and broadcasts authoritative state.
- HealthKit mirroring remains the live Watch/iPhone workout coordination path.
- WatchConnectivity provides bootstrap, fallback, samples and durable queued data.
- sport-aware GPS plausibility filtering exists on Watch/iPhone;
- Watch uses `CMAltimeter` for relative elevation when available, GPS altitude fallback otherwise;
- Watch motion prefers `CMDeviceMotion.rotationRate`, raw gyro fallback, and records source;
- Watch sends bounded `authority_metrics` snapshots containing distance, speed, altitude, D+/D-, HR, calories, cadence, steps and Auto provenance.

### Durable disconnect recovery

- reliable Watch packets queued through `transferUserInfo` carry `session_id`;
- iPhone stores delayed packets in per-session `watch_reliable.jsonl` instead of racing the live `samples.jsonl` handle;
- completed summaries can rebuild segment boundaries when delayed transition events arrive;
- pause/Auto/HR/segment analyzers read both the primary journal and reliable journal.

This is CI-validated but still needs a deliberate physical disconnect/reconnect test.

### Weather / live/history progression

- Open-Meteo remains the provider to avoid introducing an unvalidated WeatherKit entitlement into the sideload signing path;
- stored fields include temperature, apparent temperature, humidity, pressure, wind speed/direction/gusts, weather code, provider, timestamp and coordinates;
- iPhone live UI exposes richer weather context;
- history/post-summary contains timeline charts for speed, HR, altitude, cadence, calories and weather context where data exists;
- environmental analysis includes descriptive headwind/tailwind component from route heading + meteorological wind direction.

### STOP activity review / correction

- just-finished summary is automatically presented after STOP;
- user must confirm or correct the activity before dismissing it;
- correction is stored separately from the original detected activity, preserving provenance;
- activity can be edited later from iPhone history;
- corrected activity is used when recent-history digests are republished to Watch;
- if correction differs from the already-saved HealthKit workout type, the UI explicitly records that mismatch instead of pretending HealthKit was changed.

### Pause analytics / heart-rate zones

- finished summary/history shows pause total, count, manual-vs-auto time and detailed pause intervals when event evidence exists;
- legacy single-session fallback may reconstruct only total pause as wall time minus active time and labels that limitation;
- five HR zones are computed from recorded HR samples with evidence coverage;
- configured personal max HR is used when available;
- without configured max HR, the observed session peak is used only as a relative reference and explicitly not presented as a physiological max estimate.

### Auto-pause

- global Pause auto remains the master enable;
- Watch exposes per-sport profile controls for Walk/Hike/Run/Cycle;
- profiles include per-sport enable and configurable pause dwell;
- policy also has sport-specific resume dwell;
- pause/resume decisions combine stationary state with sport-specific speed/cadence evidence;
- manual and automatic pause events remain distinct.

### Auto classification / hiking provenance

- Walk/Run/Cycle uses Core Motion classification with conservative hysteresis/dwell;
- Hiking is an app inference, not claimed as a native Core Motion hiking category;
- Hiking inference requires sustained walking plus meaningful terrain/elevation evidence;
- Watch live UI shows effective Auto activity, confidence and provenance;
- iPhone post-summary/history reconstructs Auto evidence/candidates/changes and distinguishes `Core Motion` from `Inférence Watch Tracker`;
- every detected activity remains user-correctable after STOP.

### Segments / triathlon

- durable segment summaries track activity/start/end/distance;
- delayed reliable transition events can rebuild completed segment summaries;
- post-summary/history derives per-segment active time, pause overlap, distance, calories, D+/D-, average/max HR, max speed and cadence from Watch-authoritative snapshots;
- manual HealthKit `swimBikeRun` flow supports swim -> transition -> bike -> transition -> run;
- automatic triathlon candidate logic exists: conservative motion candidate + dwell automatically opens transition or starts the expected next segment, with manual controls retained.

Automatic triathlon remains **CI_VALIDATED/PARTIAL**, not field validated.

## Important known correctness issue: dynamic Auto HealthKit semantics

This is the next major architecture task and must not be hand-waved.

Current Auto starts its HealthKit workout with the initial effective activity (Walking by default), not `.mixedCardio`. If Auto later changes Walk -> Run -> Cycle, Watch Tracker correctly changes its internal segment/activity state, but the containing saved HealthKit workout can remain typed as the initial sport.

The code logs:

- the detected transition;
- current HealthKit container activity type;
- `healthkit_semantic_mismatch` when the container no longer matches the detected sport;
- automatic transition count when HealthKit save completes.

Apple documentation verified on 2026-09-10:

- `HKWorkout` requires an activity type and represents one physical activity;
- `HKWorkoutSession.beginNewActivity(...)` allows different child types specifically for `swimBikeRun` (swimming/cycling/running); interval children must match the containing workout;
- therefore arbitrary Walk/Run/Cycle mixing must not be represented by abusing a normal Walking workout or a fake triathlon.

Next implementation must preserve one Watch Tracker master session while mapping mixed Auto segments to semantically correct HealthKit object(s), or otherwise explicitly avoid saving a knowingly false workout until a correct mapping is available.

## Current major remaining work

Authoritative list remains `V040_SCOPE.md`. Main unfinished groups:

1. `V040-001`, `V040-033`, `V040-034`: correct HealthKit/general mixed-master semantics for arbitrary mixed Auto outings.
2. Physical validation `V040-007`/`V040-008` and all current v0.4 sensor/UI behavior.
3. Persist/cache richer per-segment derived metrics into the summary schema only if justified; current raw evidence remains authoritative.
4. Pace/speed zones in addition to implemented HR zones.
5. Automatic km/mile splits.
6. Configurable haptics.
7. Rolling pace/speed.
8. export strategy (GPX/TCX/FIT).
9. cross-session comparison/baseline tools.
10. unified data-quality/missingness indicators.
11. optional legacy-history HealthKit enrichment only from confident app-owned workout matching; never invent old values.

## Exact next development step

1. verify current remote branch HEAD and local worktree status before any local edit;
2. design/implement the dynamic Auto HealthKit mapping around an app-internal master session + correct sport segments; do not use arbitrary child activities inside a Walking workout;
3. keep Watch as the authority and preserve existing telemetry/segment/reconnect journals;
4. keep exact-SHA CI green after the coherent HealthKit slice;
5. update `V040_SCOPE.md` and this HANDOFF from evidence;
6. only after a coherent exact-SHA candidate is green, use the existing exact-SHA PowerShell/`gh`/iLoader flow for the next physical test;
7. record the installed candidate SHA before testing and then run focused speed/D+/gyro/cadence/weather/auto-pause/history/HealthKit/Auto tests;
8. extract the new corpus and compare to baseline session `1789026745407`.

## Exact-SHA build/install workflow

Preserve `.github/workflows/watch-sensor-lab-bootstrap.yml`.

Use the existing app script from the dedicated v0.4 worktree rather than inventing another downloader/install path. Keep:

`-ExpectedBranch 'feat/watch-sensor-v040-20260910'`

Verify `HEAD AFTER`, CI run and artifact identity before every physical install. Do not modify iLoader/isideload unless a concrete signing/install failure proves it necessary.

Never conflate:

- compile;
- CI success;
- IPA packaged;
- exact artifact downloaded;
- signed/installed by iLoader;
- iPhone launch;
- Watch launch;
- observed physical behavior.

## Architecture constraints

- Watch remains the single active-workout authority.
- No independent competing workout state on iPhone.
- Preserve revision/session stale rejection.
- Preserve distinction between raw sensor value, accepted/filtered metric and displayed metric.
- Preserve provenance for Watch GPS, iPhone GPS, HealthKit, Core Motion, Watch Tracker inference and external weather.
- Do not treat Apple Watch wrist temperature as ambient temperature.
- Do not add WeatherKit entitlement until the sideload signing/provisioning path is explicitly validated for it.
- General mixed Auto must not be mislabeled as triathlon merely to satisfy HealthKit child-activity restrictions.

## Separate iLoader/watchOS-publication chantier

Generic iLoader/isideload Watch companion publication is a separate chantier. Do not mix Watch Tracker product code/data into that public project. Keep public patches sanitized from local paths, tracker bundle IDs, device identifiers, personal activity data and diagnostic clutter. Do not merge/release it without explicit approval.

## Do not modify

- `main`;
- `iphone-lab-v2`;
- baseline corpus files;
- validated iLoader/isideload transport/provisioning without a concrete failure;
- Watch bundle identity/companion relationship without a proven packaging reason;
- historical activities during normal upgrade testing.