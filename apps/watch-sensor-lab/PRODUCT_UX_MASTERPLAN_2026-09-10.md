# Watch Sensor Lab — Product / UX masterplan

Date: 2026-09-10

## Source of truth

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch for this tranche: `feat/watch-sensor-product-shell-maps-20260910`
- branch base: `e46e3d09687b677023512a8fe685161725c73a51`
- previous physically observed base: `9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- previous exact CI run: `34515836355` SUCCESS for `9f85583...`
- current Today/comparison/effort/depth tranche inherited from `e46e3d...` is NOT yet CI/hardware validated.

Do not claim hardware validation until an exact-SHA IPA is installed and observed on iPhone + Watch.

## Product principles

1. **Today first.** The first meaningful view is what happened today; 7d/1m/6m/1y/all are secondary analysis ranges.
2. **Progressive disclosure.** Compact summary first; tap a card/zone to enter a focused detail view.
3. **Two-axis Watch navigation.** Left/right changes major section. Vertical page/crown depth reveals more information inside that section. Avoid one long free-form ScrollView.
4. **One clear action per Watch screen.** Start/stop/pause remain visually dominant when relevant.
5. **Data provenance is explicit.** Apple Health data, Tracker-local data, estimated metrics and user-entered values are visually distinguishable.
6. **No opaque medical score.** Effort/load/recovery are explained and use personal baselines; unavailable data is shown as unavailable, never fake zero.
7. **iPhone = analysis; Watch = glance + action.** Dense charts and historical drill-down live primarily on iPhone; Watch shows concise summaries and immediate control.
8. **Activity-specific UI.** Map, pace, elevation, cadence, strokes, lengths, etc. are shown only where they make sense for the selected/detected sport.
9. **Preserve tracking semantics.** UX work must not silently alter Watch authority, HealthKit session lifecycle, auto-classifier, pause/resume or recorder semantics.

## iPhone information architecture

### Tab 1 — Aujourd’hui

Order:

1. Today hero: sessions, active time, distance, calories.
2. Quick cards: steps, exercise minutes, active energy, resting HR, HRV, sleep, VO2 max where readable.
3. Every important card is tappable and opens a focused detail screen.
4. Today workout list with source, sport, time, duration, distance and detail entry.
5. Today-vs-reference comparison: same point in previous day / personal baseline when meaningful.
6. Compact latest route/map preview when a route exists.
7. Recovery / load summary when enough data exists.

Files:
- `iphone/Sources/TrackerDashboardViews.swift`
- `iphone/Sources/HealthProgressionDashboard.swift`
- `iphone/Sources/HealthWorkoutHistory.swift`
- new focused detail components may live in dedicated `*DetailView.swift` files.

### Tab 2 — Activité

Idle:
- primary Start action;
- selected sport / Auto;
- compact Watch / HR / GPS / Health / weather state;
- sport picker and session options behind secondary actions.

Running:
- horizontal/page hierarchy: Summary / Cardio / Pace-Speed / Map / Terrain-Elevation / Effort / Controls;
- no giant vertical dashboard;
- sport-specific page visibility and metric order;
- map controls must not obscure the route.

Files:
- `iphone/Sources/ActivityExperienceView.swift`
- `iphone/Sources/LiveTrackerView.swift`
- `iphone/Sources/TrackerModel.swift` only if presentation data plumbing is missing; avoid changing tracking behavior in a pure UX tranche.

### Tab 3 — Progression

Ranges:
- Today / 7d / 1m / 6m / 1y / All.

Core analytics:
- sessions, active time, distance, energy;
- sport filter;
- current-vs-previous cumulative overlay on same chart;
- sport distribution;
- records and consistency;
- 7d vs 28d training load;
- HRV/resting HR/sleep/VO2 trends where readable;
- workout drill-down and similar-session comparison.

Files:
- `iphone/Sources/PerformanceProgressionTodayView.swift`
- `iphone/Sources/HealthProgressionDashboard.swift`
- `iphone/Sources/TrackerEffortInsight.swift`

### Tab 4 — Historique

- Apple Health and Tracker views remain distinguishable;
- search, period and sport filters;
- workout detail, route, effort, perceived effort, weather, pauses, segments;
- avoid duplicating one Tracker workout when it is also present in Apple Health.

Files:
- `iphone/Sources/HealthWorkoutHistory.swift`
- `iphone/Sources/ActivityHistoryView.swift`
- `iphone/Sources/PostActivitySummaryView.swift`

### Settings

- Health permissions/state;
- Watch sync state;
- auto-pause profiles;
- units/display preferences;
- map style preference;
- developer/build identity kept secondary.

File:
- `iphone/Sources/TrackerSettingsView.swift`

## Apple Watch information architecture

### Top-level horizontal pages while idle

1. **Démarrer** — dominant Start button; current sport; tiny status indicators.
2. **Progression** — Today summary as first page.
3. **Récentes** — latest workout preview and entry to history.
4. **État** — concise body/device status when data is available.

### Depth interaction

Inside a top-level page, tap a meaningful card/zone to open focused depth, or use vertical page/crown navigation where the information is sequential.

Examples:
- Progression -> Today -> 7d comparison -> 28d -> Load -> Recovery.
- Recent -> selected workout -> Summary -> HR -> Effort -> route/elevation summary where transferable.
- Status -> Watch/iPhone sync -> Health permissions -> GPS quality.

Avoid nested arbitrary ScrollViews. Prefer `TabView(.verticalPage)`, NavigationStack destinations and compact fixed-height cards.

Files:
- `watch/Sources/WatchSensorLabApp.swift`
- `watch/Sources/WatchProgressionDepthView.swift`
- `watch/Sources/WatchRecentHistory.swift`
- new `WatchStatusDepthView.swift` / detail views as needed.

## Active Watch workout target layout

Do not change session authority or control semantics.

Top-level workout pages should remain small and sport-specific:

1. Primary: elapsed time + primary metric + HR.
2. Effort: HR zone + estimated effort / perceived effort prompt only after workout.
3. Route/Terrain: GPS quality, distance, elevation; no map if it would be unreadable.
4. Controls: Pause/Resume/Stop, explicit and hard to trigger accidentally.

Additional depth should open by tapping a metric card, not by adding more permanent clutter.

## Map / route / terrain strategy

### Phase 1 — native map presentation

- Map styles: Standard, Hybrid, Satellite.
- Activity-specific defaults:
  - walk/run/hike/cycle: route-first standard or hybrid;
  - water/outdoor exploration: satellite/hybrid option prominent;
  - indoor/no-route sports: hide map page.
- recenter control;
- route bounds with start/end markers;
- pace/speed/elevation-derived route styling only when stable enough.

Files:
- `iphone/Sources/ActivityExperienceView.swift`
- `iphone/Sources/PostActivitySummaryView.swift`
- optional new `TrackerMapStyle.swift` shared presentation helper.

### Phase 2 — terrain inference

First useful local version:
- elevation gain/loss and grade profile;
- route roughness/turn density/speed variability as descriptive context only;
- classify **road / trail-like / mixed / unknown** only when evidence is sufficient;
- label as estimated when no external trail/road dataset is used.

Do not claim Komoot-grade surface/road intelligence without a real map/OSM/trail data source and explicit data pipeline.

## Effort / perceived effort / load

### Per-session effort

- estimated effort 1–10 from recorded evidence where available;
- heart-rate zone exposure is the strongest signal;
- duration, continuity/pauses, elevation and environmental context can adjust the estimate;
- show why the estimate exists;
- user perceived effort 1–10 is stored separately and never overwritten.

Files:
- `iphone/Sources/TrackerEffortInsight.swift`
- `iphone/Sources/SessionHeartRateZones.swift`
- `iphone/Sources/SessionPauseAnalysis.swift`
- `iphone/Sources/SessionEffortAnalysis.swift`
- `iphone/Sources/PostActivitySummaryView.swift`

### Training load

Target model:
- compare recent 7-day workload to a 28-day personal baseline;
- allow sport filtering;
- expose raw components and confidence/data coverage;
- no medical recovery claim.

## HealthKit / Apple Fitness correctness

Open validation items:
- Auto workout can change Tracker `effectiveActivity` after HealthKit workout configuration has already started;
- post-activity local correction does not retroactively relabel an already-saved HealthKit workout;
- verify a NEW workout on hardware for Fitness activity type, source name and source icon;
- if source icon remains blank, inspect packaged app icon/signing/source revision rather than changing UI assets blindly.

Files primarily involved:
- `watch/Sources/SensorModel.swift`
- `Shared/TrackerShared.swift`
- `iphone/Assets.xcassets/AppIcon.appiconset`
- `watch/Assets.xcassets/AppIcon.appiconset`

Any HealthKit workout replacement/reconciliation design must be a separate, explicitly tested change.

## Sync / offline / concurrency validation matrix

Architecture principle remains: Watch is active-workout authority; iPhone requests and mirrors.

Must validate:
- start on Watch / start on iPhone;
- pause/resume/stop convergence;
- iPhone locked/backgrounded;
- iPhone app killed and reopened;
- Watch app temporarily unreachable;
- Bluetooth/network interruption and recovery;
- history delivery after WCSession late activation;
- duplicate prevention;
- deletion convergence if/when deletion is made user-facing on both devices;
- no data loss after upgrade install.

Files:
- `iphone/Sources/TrackerModel.swift`
- `iphone/Sources/WatchReliableRecovery.swift`
- `iphone/Sources/PhoneRecentHistoryBridge.swift`
- `watch/Sources/SensorModel.swift`
- `watch/Sources/WatchRecentHistory.swift`

## Visual system

- dark-first but not black-only; use restrained gradients and activity accents;
- cyan/mint for live/positive movement, orange for effort, pink/red for heart, purple/indigo for long-term trend/recovery;
- one focal accent per card;
- 24–28 pt iPhone card radius, 12–20 pt Watch cards depending on size;
- monospaced digits for changing metrics;
- charts use direct legends and current-vs-reference contrast;
- cards that navigate must look tappable and include disclosure affordance where useful;
- support small Watch sizes with line limits/minimumScaleFactor.

## Implementation phases

### A — Today + drill-down + comparison
Status: in progress/inherited from `e46e3d...`.
- Today-first progression.
- tappable metric cards.
- overlay comparison chart.

### B — Watch depth shell
Status: in progress/inherited from `e46e3d...`; extend now.
- Today/7d/28d vertical progression.
- add tappable focused details.
- add fourth top-level Status page.

### C — Effort and load
Status: estimated effort + perceived effort scaffold inherited; expand UI/load next.
- session effort explanation.
- 7d vs 28d load.
- sport filter and data-coverage explanation.

### D — Maps and terrain
Status: start in this branch.
- persistent map style preference.
- shared map style selector.
- route detail presentation.
- first local terrain/elevation profile.

### E — Active workout presentation redesign
Status: start only at presentation layer; preserve tracking semantics.
- sport-specific page order.
- compact primary/cardio/route-controls hierarchy.
- drill-down from metrics where practical.

### F — HealthKit/Fitness semantics
Status: separate after physical evidence.
- validate new Auto workout type and app icon first.
- design reconciliation only if needed.

### G — Reliability validation
Status: hardware required.
- long workout, weak GPS, background, reconnect, app restart, Watch-only operation, battery impact.

## Exact validation gates

For each code checkpoint:
1. verify branch HEAD and diff;
2. run existing `watch-sensor-lab-bootstrap.yml` on exact SHA;
3. CI SUCCESS is compile/package validation only;
4. retrieve exact-SHA IPA with existing `UPDATE_WATCH_SENSOR_LAB.ps1`;
5. install as upgrade with corrected iLoader; no purge unless explicitly requested;
6. record hardware observations in HANDOFF;
7. do not merge/release without explicit approval.
