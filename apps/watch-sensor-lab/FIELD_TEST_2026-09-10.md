# Field test + product backlog — 2026-09-10

This document is the durable record for the first long real-world Watch Tracker walk and the product feedback that followed it. Keep it updated as items move from TODO -> implemented -> CI validated -> physically validated.

## Exact tested build

- repository: `Rzbck/ios-godot-lab`
- application: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-tracker-recorder-20260909`
- physically tested code SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- CI artifact: `watch-sensor-lab-companion-1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- artifact id: `10141689980`
- artifact digest: `sha256:2c8187f5e684302ce4ed0ce8d385128386490f913e68219e30980ec42755a5a0`
- exact downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\1bbd803f4916\WatchSensorLab-companion-unsigned-1bbd803f4916.ipa`
- IPA SHA-256: `8a8478b7b9ead0afdec7ad17dc3105f41d8e220ca39266ceb75ba9fa9fd6d4b6`
- installed iPhone bundle observed through pymobiledevice3: `com.rzbck.watchsensorlab.59858TV9N2`
- user physical result: long real walk completed successfully; user also manually used Pause during the activity.

## Preserved field-test data

Do not delete the first real walk until explicitly decided after regression comparison.

PC extraction:

- root: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806`
- archive: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- short pre-walk session: `1789026601777`
- main field session: `1789026745407`
- main `samples.jsonl`: 7,512,119 bytes
- main `summary.json`: 333 bytes

The data above is the baseline regression corpus for future versions. App upgrades should preserve local historical sessions unless the user explicitly requests deletion.

## Measured results from main session `1789026745407`

- wall-clock span: about 1 h 09 min 29 s
- active duration: about 58 min 33 s
- excluded/paused time: about 10 min 56 s
- Watch-authoritative final distance: about 5.798 km
- iPhone locally integrated GPS distance: about 5.931 km
- distance delta: about 132.8 m / 2.29%
- summary average speed: about 5.94 km/h
- average pace: about 10:06 min/km
- HealthKit average HR: about 88.44 bpm
- logged HR observed range: about 63–100 bpm
- summary elevation gain/loss: about +226.6 m / -215.9 m — NOT yet considered reliable
- local records: 24,405 total
  - Watch motion: 20,397
  - iPhone location: 2,998
  - Watch heart-rate change events: 1,008
- JSONL integrity: readable/monotonic/no missing session id found in analysis
- Watch motion transport: about 4.89 samples/s against 5 Hz target, one significant gap around 14 s
- iPhone GPS horizontal accuracy median: about 5.1 m
- about 91.3% of retained iPhone GPS points <= 10 m accuracy
- about 95.9% <= 20 m accuracy
- Auto remained `selected=automatic`, `effective=walking` for the full walk; no false Run/Cycle transition observed

## Objective defects found from data/code analysis

### P0 — data correctness / workout semantics

- [ ] **Auto HealthKit workout type is wrong.** `ActivityKind.automatic` currently maps to `HKWorkoutActivityType.mixedCardio`. The field session was detected locally as Walking, but the HealthKit workout may therefore be stored as Mixed Cardio. Fix final HealthKit semantics so a walk is stored as Walking, a run as Running, a ride as Cycling, and true multisport uses an appropriate multisport strategy.
- [ ] **Watch max-speed outlier.** `summary.json` reported about 8.3975 m/s / 30.23 km/h for a walk; iPhone GPS maximum was about 3.52 m/s / 12.68 km/h. Tighten Watch GPS/outlier filtering and make sport-aware max-speed validation.
- [ ] **Elevation gain/loss too noise-sensitive.** Current ~1.5 m delta accumulation is not robust relative to GPS vertical error. Introduce better filtering and use barometric/relative-altitude data where supported.
- [ ] **Gyroscope logged as zero.** Accelerometer is useful, but all recorded gyro axes were zero in the field corpus. Diagnose Core Motion sampling/order/packet construction and validate on hardware.

### P0 — observability and regression analysis

- [ ] Add a bounded lightweight event log for `START`, `PAUSE`, `RESUME`, `STOP`, session id, authority revision, selection revision, Auto candidate/transition, transport used, reconnects and errors. Do not spam high-frequency sensor callbacks.
- [ ] Record enough Watch GPS data locally/on iPhone to compare Watch GPS and iPhone GPS point-by-point and quantify route/distance divergence.
- [ ] Add explicit sensor availability/acquisition state so startup is not represented by unstable/placeholder numerical values.

### P0 — physical validation still required

- [ ] Confirm the saved HealthKit workout appears in Health/Fitness with correct activity type.
- [ ] Confirm the HealthKit workout route appears and is coherent.
- [ ] Physically test deletion of the workout + route created by Watch Tracker only; verify unrelated Health data is untouched.
- [ ] Run deliberate Auto transition tests: Walk -> Run -> Walk; separately Cycle; later mixed/multisport scenarios.

## User product feedback from the same field test

### iPhone UI

- [ ] The map is partly hidden by the top-right Watch connection badge. Fix layout so map content is never obscured by status chrome.
- [ ] The dedicated Watch-connected badge is redundant because connection/readiness is already represented alongside GPS / Watch / Health. Remove it or merge status into a compact readiness row.
- [ ] Make GPS / Watch / Health indicators more compact on iPhone.
- [ ] Show real-time active calories during an activity on iPhone.
- [ ] Fix startup visual instability: at activity start, values visibly jump around while acquisition/calculation settles. Use explicit acquiring states, sensible placeholders and display smoothing/gating so numbers do not look broken to the user.

### Apple Watch UI

- [ ] Show real-time active calories during an activity on Apple Watch.
- [ ] Current Watch UI is generally considered good by the user.
- [ ] Add an additional horizontal swipe/page dimension for more real-time metrics, while preserving simple workout controls and glanceability. Exact watchOS interaction model must be validated against current Apple HIG before implementation.

### Richer live metrics / sensor research

The user wants the tracker to exploit as much useful Apple data as reasonably possible, but only claim real-time metrics when the platform actually exposes them at appropriate cadence.

Research/implement where feasible:

- [ ] respiratory/breathing-related metric(s)
- [ ] walking balance/asymmetry and gait quality
- [ ] walking speed / step length / double-support time / cadence where available
- [ ] additional heart-rate metrics and quality indicators
- [ ] barometric altitude / relative altitude / terrain metrics
- [ ] environmental/outdoor temperature associated with the activity
- [ ] any additional high-value metrics available from Apple Watch/iPhone that improve activity classification or post-activity analysis

Important: distinguish live sensor data from HealthKit metrics that Apple only computes later, during sleep, in supported contexts, or on specific hardware. Do not fake unsupported real-time values.

### Session summary and history

- [ ] Add a proper post-activity summary screen.
- [ ] Add an activity history/list on iPhone.
- [ ] Add useful recent activity/history access on Apple Watch, adapted to Watch screen size.
- [ ] Allow reopening previous activities with route, duration, distance, pace/speed, calories, heart rate, elevation, pauses and all available derived metrics.
- [ ] Preserve historical activities across app upgrades. Do not treat upgrade/install as a data purge.
- [ ] Keep this first real field session as a baseline so future versions can compare algorithm improvements against the same corpus where possible.
- [ ] Store schema/app/build version per activity so historical interpretation remains reproducible after algorithm changes.

### Environmental context

- [ ] Associate ambient/outdoor temperature with sessions when a reliable source is available.
- [ ] Prefer also storing humidity/weather context if feasible and privacy/network cost is acceptable.
- [ ] Treat environmental context as part of effort interpretation: the same pace/HR at extreme cold or heat is not equivalent.
- [ ] Preserve provenance and timestamps for environmental data; do not pretend Watch wrist temperature is ambient temperature.

### Auto-pause

- [ ] Add optional automatic pause in settings.
- [ ] Auto-pause must be configurable on/off, and ideally activity-specific.
- [ ] Detect inactivity only after a stability interval; avoid rapid pause/resume oscillation.
- [ ] Use different thresholds/logic by sport rather than a single universal speed threshold.
- [ ] Manual Pause/Resume remains authoritative and must coexist cleanly with auto-pause.

### Auto activity classification

- [ ] Improve Auto beyond only Walk/Run/Cycle where evidence permits.
- [ ] Add hiking/randonnée detection if feasible using combined motion, speed, terrain/elevation and context rather than unsupported Core Motion labels.
- [ ] Keep conservative confidence/hysteresis; false sport switches are worse than delayed switches.
- [ ] Expose what Auto currently knows vs what is inferred by our own classifier.

### Multisport / triathlon / mixed outings

User requirement: one continuous session may naturally contain bicycle -> walk -> run, and a future triathlon should ideally remain one coherent session.

- [ ] Design a first-class multisport session model with segments/transitions instead of forcing one `effective_activity` string over the whole session.
- [ ] Support manual sport transition as a reliable baseline.
- [ ] Research/implement automatic transition detection for supported combinations with strong hysteresis/confidence.
- [ ] Triathlon target: swim -> bike -> run in one session, including transition durations where practical.
- [ ] More general mixed outing target: e.g. bike -> walk -> run without splitting user history into unrelated sessions unless user chooses that behavior.
- [ ] HealthKit representation must be correct for multisport, not a fake relabel of one single-sport workout.

## Product principles established by this field test

1. Watch remains the single live workout authority while an Apple Watch workout is active.
2. Data correctness beats visual novelty. Implausible speed/elevation values must be filtered before display and summary.
3. Auto must be conservative and explicit about confidence/capability.
4. Historical activities are user data, not disposable test state. Purge is explicit only.
5. Every stored session should be traceable to app version/build SHA/schema and algorithm version.
6. Sensor/environment provenance matters: Watch GPS, iPhone GPS, HealthKit, Core Motion and external weather must remain distinguishable.
7. Build/CI validation and physical validation remain separate statuses.

## Status model to use for this backlog

Each feature/bug should move through these states explicitly:

- `TODO`
- `IMPLEMENTED`
- `CI_VALIDATED`
- `PHYSICALLY_VALIDATED`

Do not mark physical validation without a real iPhone/Apple Watch observation from the user.

## Next version scope recommendation

The next version should prioritize, in order:

1. correctness: HealthKit Auto semantics, speed outlier, elevation, gyro;
2. observability: event log + Watch GPS evidence;
3. startup display stabilization;
4. real-time calories + compact iPhone status layout + unobscured map;
5. post-activity summary + persistent history foundation;
6. auto-pause foundation;
7. richer metrics with explicit capability/availability labeling;
8. multisport session model before aggressive automatic multisport classification.

Do not delete or overwrite the baseline field-test data while implementing this version.