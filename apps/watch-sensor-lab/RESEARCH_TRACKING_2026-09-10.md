# Tracking research — 2026-09-10

Purpose: turn the first field-test feedback into an implementation plan grounded in current Apple APIs and proven tracker product patterns. This file complements `FIELD_TEST_2026-09-10.md`.

## Apple capability conclusions

### Real-time or near-real-time candidates

These are suitable for live workout UI when hardware/API availability is confirmed at runtime:

- `HKQuantityTypeIdentifier.activeEnergyBurned`: active calories. Watch Tracker already receives active energy through `HKLiveWorkoutBuilder`; next step is primarily UI/history exposure.
- `CMPedometerData.currentCadence`: current step cadence where supported.
- `CMPedometerData.currentPace`: current pedestrian pace where supported.
- `CMAltimeter`: relative and, where available, absolute altitude updates. Apple explicitly describes hiking/elevation-change use cases. This should become the primary source for ascent/descent deltas, with GPS altitude as a secondary/fallback source.
- Outdoor running metrics available through HealthKit on supported Apple Watch hardware include running speed, stride length, running power, ground contact time and vertical oscillation. `HKLiveWorkoutDataSource.typesToCollect` should be inspected per active workout type rather than assuming all metrics exist on every device.
- Heart rate and active energy continue through the Watch HealthKit workout session.

### Available in HealthKit but NOT appropriate as continuous live metrics

- Apple Walking Steadiness is read-only and typically generated roughly every 7 days when enough qualifying walking data exists. It is contextual/history data, not a workout live metric.
- Walking speed, walking step length, walking asymmetry and walking double-support are system-generated mobility samples under constrained conditions (for example the iPhone carried near the waist and steady walking). Apple documents only a limited number of such samples on a typical day. Treat these as post-session/context data when timestamps overlap, not as a 1 Hz live feed.
- Heart-rate recovery at one minute is a post-exercise metric and belongs in summary/history, not live workout display.

### Respiration

Apple Watch exposes respiratory-rate information primarily as an overnight/sleep vital. Current public Apple documentation does not provide a general continuous workout respiratory-rate sensor stream for arbitrary third-party workout apps.

Decision:

- do NOT label any derived workout value as Apple-measured respiratory rate;
- optionally show relevant HealthKit respiratory-rate context outside a workout when available;
- an experimental breathing-rate estimator may be researched later using motion/HR patterns, but it must be clearly labeled estimated/experimental and separately validated.

### Temperature and environment

Do not use Apple Watch wrist temperature as ambient temperature. Apple documents wrist-temperature sensing as an overnight baseline/variation feature and explicitly says it is not an on-demand thermometer.

For outdoor workout context, use a real weather source. Apple WeatherKit can request weather for a `CLLocation`.

Recommended session environmental snapshots:

- start weather;
- periodic coarse snapshots for long sessions (not every GPS point);
- end weather;
- temperature;
- apparent temperature if available;
- humidity;
- wind speed/direction where useful;
- pressure;
- condition/source/timestamp/coordinate.

HealthKit provides workout metadata keys for weather temperature, humidity, pressure and condition, so overall workout context can also be attached to saved workouts where appropriate.

### Auto activity classification

Public `CMMotionActivity` categories remain broad: stationary, walking, running, automotive, cycling and unknown, with confidence levels. They are not mutually exclusive and updates are best-effort.

Therefore:

- Walk/Run/Cycle can use Apple motion classification as a strong input;
- Hiking is not a native Core Motion classification. Hiking must be an app inference, e.g. sustained walking + outdoor route + meaningful grade/elevation + duration/context. It should start as a conservative suggestion/confirmation rather than an aggressive silent switch;
- swimming and many other sports cannot be reliably inferred from `CMMotionActivity` alone;
- store classifier evidence/confidence and transition reason in the event log.

### Multisport / triathlon

HealthKit directly supports triathlon-style multisport:

- containing workout type: `HKWorkoutActivityType.swimBikeRun`;
- child activities can be Swimming, Cycling and Running;
- transition activities are supported;
- `HKWorkoutSession.beginNewActivity(configuration:date:metadata:)` changes the current activity;
- HealthKit automatically changes relevant collection types as the current activity changes.

This is the correct future architecture for one real triathlon session.

Important limitation: Apple documents mixed sport activities within one HealthKit workout specifically for `swimBikeRun`. Arbitrary free combinations such as Bike -> Walk -> Run are not equivalent to a native `swimBikeRun` workout because Walking is not one of its supported child activities.

Recommended architecture:

- Watch Tracker owns a first-class internal `MasterSession` containing ordered `ActivitySegment` and `TransitionSegment` records;
- triathlon can map directly to one HealthKit `swimBikeRun` workout;
- arbitrary mixed outings remain one activity in Watch Tracker history but may need multiple correctly typed HealthKit workouts/segments rather than one falsely labeled HealthKit workout;
- manual transition is the reliable baseline;
- automatic transitions come later and must use confidence + dwell time + hysteresis.

## Proven product patterns from specialist trackers

### WorkOutDoors

Useful patterns:

- left/right swipe between multiple live data screens on Apple Watch;
- highly configurable screen contents and layouts;
- map as one of several screens rather than permanent chrome;
- post-workout summary with mini route map;
- tap metric for deeper lap/interval breakdown;
- detailed iPhone analysis by Pace / Heart / Elevation and other dimensions;
- auto-pause, zones, alerts, rolling metrics, splits and export.

Product implication for Watch Tracker:

Do not copy the 800-field complexity. Adopt the strong structure:

1. a small set of curated horizontal live pages per sport;
2. one Map page;
3. one Controls page that remains easy to reach;
4. optional user configuration later.

Map gesture conflict must be handled: horizontal page switching should not accidentally pan a map. Use a clear interaction boundary or a dedicated map page behavior.

### Strava

Useful patterns:

- Watch recording exposes sport-specific key metrics;
- controls are reached by swiping rather than permanently occupying the main data screen;
- Auto-Pause is sport-specific:
  - cycling uses GPS movement;
  - running uses motion/accelerometer;
- manual pause still has explicit behavior and is not replaced by auto-pause.

Product implication:

Watch Tracker auto-pause should use a per-sport strategy, never a single universal threshold.

Suggested first implementation:

- Walking: motion stationary + very low validated speed for a dwell period;
- Running: motion + cadence + validated speed;
- Cycling: validated GPS speed + Core Motion cycling/stationary evidence;
- manual Pause has precedence and disables automatic Resume until the user manually resumes;
- automatic pause/resume events are logged distinctly from manual events.

### Polar multisport

Useful pattern:

- fixed multisport such as Triathlon;
- free multisport as a product-level concept;
- explicit transition mode;
- transition duration tracked separately;
- per-sport settings maintained within one session.

Product implication:

Even if automatic sport switching is a long-term goal, Watch Tracker should first expose a reliable manual `Next sport / Transition` control and record transitions as first-class data.

### TrainingPeaks

Useful analysis pattern:

- layer physiological signals against pace/power/HR/terrain;
- analyze selected time ranges/segments rather than only one summary number;
- environmental context (temperature, humidity, wind) helps explain effort drift;
- richer heat/breathing metrics often require dedicated external sensors rather than pretending a basic Watch measures them directly.

Product implication:

History detail should have synchronized time-series layers and selectable segments. Weather belongs in the same timeline/context as HR, pace and elevation.

## Recommended next-version product/data architecture

### 1. Stable live presentation layer

Introduce a display-quality layer separate from raw sensor state:

- raw values remain logged;
- validated/smoothed values drive the UI;
- each metric has state: unavailable / acquiring / valid / degraded;
- do not display zeros as real measurements while a sensor is acquiring;
- apply sport-aware plausibility gates;
- use hysteresis so values do not jump on first few samples.

This directly addresses the field-test startup UI jumping bug.

### 2. Sensor-quality model

For each live stream record:

- source device;
- timestamp;
- availability;
- accuracy where provided;
- sample age;
- acquisition status;
- last error;
- selected source/fallback reason.

This allows UI confidence indicators and post-session diagnostics without printing sensor spam.

### 3. Distance/speed fusion

Keep Watch and iPhone GPS independently measurable. Do not silently mix them point-by-point.

Proposed pipeline:

- reject stale/impossible GPS points;
- sport-aware acceleration/speed plausibility checks;
- accuracy-aware position filtering;
- calculate separate Watch and iPhone route/distance estimates;
- select an authoritative route/distance policy with explicit source and confidence;
- preserve raw streams for regression.

Never derive max speed from one transient point. Require a short validated window or percentile/rolling confirmation.

### 4. Elevation

Use `CMAltimeter` relative altitude as primary D+/D- evidence where available.

- fuse/anchor with GPS altitude for absolute elevation;
- reject vertical jumps inconsistent with time/horizontal movement;
- store raw GPS altitude and barometric altitude separately;
- summary reports the selected elevation source and quality.

### 5. Motion

Fix current gyroscope zero issue and log runtime capability state:

- `isGyroAvailable`;
- `isGyroActive` after start;
- error/timeout if no non-zero/changing sample arrives;
- consider `CMDeviceMotion` for fused attitude/rotation data when useful for classifier work.

### 6. History schema

History must be migration-safe and independent from current UI implementation.

Each session should include:

- stable session id;
- schema version;
- app semantic version/build;
- exact git SHA;
- algorithm/filter version;
- start/end/active/paused time;
- activity segments + transitions;
- route(s) + source;
- summary metrics;
- environmental snapshots;
- event log;
- raw-data references;
- HealthKit workout UUID(s) when available;
- deletion state / HealthKit deletion result.

Never delete sessions during a normal app upgrade. Before the next physical upgrade, keep the already extracted PC corpus as an external safety copy.

### 7. History UI

iPhone first:

- list by date/sport;
- map thumbnail;
- distance/duration/pace/calories/HR/D+;
- detail timeline with synchronized graphs;
- segment/lap/transition breakdown;
- environment section;
- compare with previous / personal baseline later.

Watch:

- recent activities list;
- compact summary/detail;
- avoid trying to reproduce full iPhone analysis on the small screen.

### 8. Live Watch pages

Recommended curated horizontal pages during activity:

- Page A — Primary: time, distance, pace/speed, HR;
- Page B — Effort: active calories, average HR, HR zone, cadence when available;
- Page C — Terrain: altitude, D+, D-, grade;
- Page D — Dynamics: sport-specific metrics (running power/stride/GCT/vertical oscillation, cycling data when available);
- Page E — Map;
- Controls must remain immediately reachable and not become hidden behind many pages.

### 9. Summary screen

At STOP, do not instantly drop to idle. Show a durable summary state with:

- sport/segments;
- active vs elapsed time;
- distance;
- pace/speed;
- calories;
- HR average/max/zones;
- elevation;
- map;
- pauses/transitions;
- weather;
- sensor/data-quality warnings;
- saved-to-Health status.

### 10. Additional high-value features inspired by specialist trackers

Candidates after correctness/history foundation:

- automatic km/mile laps and splits;
- rolling pace/speed (e.g. last 30 s / last km);
- HR / pace / speed / cadence zones;
- haptic alerts for zone/pace deviations;
- configurable spoken summaries through iPhone/Watch audio where appropriate;
- GPX/TCX/FIT export for interoperability;
- compare current outing against a previous route/session;
- battery impact and sensor connection status;
- offline route/map support as a later navigation project, not mixed into the immediate correctness release.

## Implementation priority after research

### P0 — next build

1. preserve/migrate history storage and baseline session;
2. correct HealthKit Auto semantics;
3. sport-aware GPS speed filtering + max-speed fix;
4. `CMAltimeter` elevation path + robust fallback;
5. gyro diagnostics/fix;
6. event log + Watch GPS evidence;
7. stable acquisition/display layer;
8. compact iPhone status/map fix;
9. calories live on both devices;
10. post-activity summary + iPhone history foundation.

### P1

11. horizontal curated Watch data pages;
12. cadence/current pace where available;
13. running dynamics where available;
14. weather/environment snapshots + HealthKit weather metadata;
15. activity-specific auto-pause;
16. gait/mobility HealthKit context in history, clearly non-live when applicable;
17. recent history on Watch;
18. export/splits/zones.

### P2

19. multisport internal segment model + manual transitions;
20. native HealthKit triathlon (`swimBikeRun`) implementation;
21. automatic multisport transitions after enough field data;
22. conservative Hiking inference/confirmation;
23. experimental respiration estimation only if separately validated and explicitly labeled.

## Sources reviewed

Official Apple Developer / Support documentation reviewed on 2026-09-10:

- HealthKit — Dividing a HealthKit workout into activities
- `HKWorkoutActivityType.swimBikeRun`
- `HKWorkoutSession.beginNewActivity(...)`
- HealthKit data types / Mobility / Running metrics
- `CMPedometerData.currentCadence` / `currentPace`
- `CMAltimeter`
- `CMMotionActivity` / `CMMotionActivityManager`
- WeatherKit `WeatherService.weather(for:)`
- HealthKit workout weather metadata keys
- Apple Support — respiratory rate during sleep
- Apple Support — wrist temperature during sleep

Specialist products/docs reviewed:

- WorkOutDoors user guide / workout screens and analysis
- Strava Auto-Pause and Apple Watch app documentation
- Polar multisport documentation
- TrainingPeaks advanced analysis/environmental context material

Re-check current platform docs when implementing because APIs/platform behavior may evolve.