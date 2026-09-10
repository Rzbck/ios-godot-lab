# HANDOFF — Product shell, Watch depth, maps and terrain

Date: 2026-09-10

## Objective

Turn Watch Sensor Lab from a functional tracker prototype into a compact, depth-first sports product UI while preserving the existing active-workout authority and recorder semantics.

User priorities:
- Today is the first meaningful view;
- tap cards/zones to enter deeper information;
- Apple Watch uses left/right for major areas and vertical/crown/navigation depth inside an area, without long free-form scrolling;
- richer current-vs-previous graphs;
- sport-specific live pages;
- better maps and terrain/elevation context;
- effort + perceived effort + training-load style context;
- keep every feature strategically placed and visually coherent.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-product-shell-maps-20260910`
- branch base: `e46e3d09687b677023512a8fe685161725c73a51`
- implementation HEAD before this handoff commit: `5fdcdc9e769f63a10f89f78f01ff564919aac78d`
- previous physically observed visual-analytics checkpoint: `9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- previous successful CI: run `34515836355` for `9f85583...`
- local worktree for this branch: NOT created/verified yet.

Always verify current remote HEAD before CI or local worktree creation.

## Master plan

Full durable screen-by-screen product plan:
- `apps/watch-sensor-lab/PRODUCT_UX_MASTERPLAN_2026-09-10.md`

It records information architecture, map/terrain strategy, effort/load strategy, HealthKit/Fitness open points, sync validation matrix, visual system and validation gates.

## Implemented in this branch

### iPhone Today

New `iphone/Sources/TodayExperienceView.swift` and Today route in `TrackerApp.swift`.

- reads all Apple Health workouts accessible to the app;
- Today hero: sessions, active time, distance, energy;
- tappable cards for sessions/time/distance/steps;
- Today workout list with source name and drill-down;
- 7-day mini chart;
- tappable resting-HR / HRV / sleep / VO2 cards;
- direct entry to Activity / Progression / History.

### iPhone active product shell

New `iphone/Sources/ActivityProductContainerView.swift` and Activity tab route in `TrackerApp.swift`.

When inactive, the existing idle launcher remains.
When active, presentation becomes sport-aware pages:
- Summary;
- Cardio;
- Map when relevant;
- Terrain when relevant;
- Conditions.

Persistent bottom controls remain. Pause/Resume semantics are unchanged. Stop now uses a confirmation dialog on iPhone presentation.

Metric cards can open focused detail views. No TrackerModel or SensorModel tracking logic changed in this branch.

### Watch idle product shell

`watch/Sources/WatchSensorLabApp.swift` now has four horizontal top-level pages:
1. Start;
2. Progression;
3. Recent;
4. Status.

Recent card is tappable. Start remains dominant and sport selection stays behind the Start action.

### Watch Progression depth

`watch/Sources/WatchProgressionDepthView.swift`:
- Today / 7d / 28d as vertical pages;
- Today cards are tappable;
- 7d current-vs-previous paired bars are tappable;
- 28d weekly bars are tappable;
- focused detail views add additional vertical depth rather than a giant ScrollView.

### Watch Status depth

New `watch/Sources/WatchStatusDepthView.swift`:
- device/sync page;
- Health/GPS page;
- 7d-vs-28d volume/load page;
- explicitly labels this as workload context, not medical diagnosis.

### Watch active workout presentation

`watch/Sources/WatchActiveWorkoutView.swift` presentation redesigned to four horizontal pages:
1. Primary metrics;
2. Effort/Cardio;
3. Route/Terrain;
4. Controls.

Distance, Heart, Energy and Terrain/GPS can open focused depth views.
Pause/Resume/Stop/Triathlon actions still call the same SensorModel methods. No SensorModel changes in this branch.

### Map styles

New `iphone/Sources/TrackerMapPresentation.swift`:
- Plan / Hybrid / Satellite;
- persistent preference key `tracker.map.style`;
- shared menu used by live and post-activity maps.

### Post-activity terrain

New `iphone/Sources/SessionTerrainAnalysis.swift` and updated `PostActivitySummaryView.swift`:
- uses retained local GPS/altitude samples;
- elevation profile;
- elevation amplitude;
- max uphill/downhill grade;
- descriptive relief label;
- route map has start/end markers and map-style chooser.

Surface type is intentionally NOT invented. It remains unknown without a dedicated external cartographic road/trail/surface source.

### Effort inherited from previous tranche

`TrackerEffortInsight.swift` already provides:
- Tracker estimated effort 1–10 based on recorded HR zones plus duration/continuity/elevation/environment where available;
- separate user perceived effort 1–10;
- user perceived effort is never overwritten.

## Deliberately not changed here

- `iphone/Sources/TrackerModel.swift` tracking/authority logic;
- `watch/Sources/SensorModel.swift` tracking/HealthKit/classifier logic;
- Watch authoritative workout state/revision protocol;
- Auto classifier;
- HealthKit workout reconciliation semantics;
- purge/deletion behavior;
- iLoader/isideload.

## Apple / API verification

Current code targets iOS 17 and watchOS 10.
Apple documentation confirms the MapKit map styles used here and the watchOS 10 `containerBackground(..., for: .tabView)` pattern.

Apple also exposes workout effort / estimated workout effort in newer HealthKit, but this branch does NOT yet adopt those APIs because availability against iOS 17/watchOS 10 must be handled explicitly. Keep Tracker effort separate until that integration is designed and tested.

## Validation state

- new product-shell/maps code: NOT CI validated yet;
- new product-shell/maps code: NOT physically validated yet;
- inherited `e46e3d...` Today/comparison/effort depth tranche was also not yet CI/hardware validated at branch creation;
- `9f85583...` remains the latest known physically observed visual-analytics base in this lineage.

Do not claim the new UI works on device before exact-SHA CI + install + hardware observation.

## Required next step

1. verify final remote HEAD after this documentation commit;
2. run existing `.github/workflows/watch-sensor-lab-bootstrap.yml` by `workflow_dispatch` on that exact branch/SHA;
3. fix concrete compiler errors only if CI reports them;
4. after SUCCESS, create a dedicated local worktree for `feat/watch-sensor-product-shell-maps-20260910`;
5. use existing `apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1 -ExpectedBranch ... -NoAutoBuild -OpenFolder` to retrieve exact-SHA IPA;
6. install as upgrade with corrected iLoader, no purge.

## Hardware test order

1. iPhone Today: Today is first, Apple Health workouts appear, cards drill down.
2. iPhone Progression: current-vs-previous graph and ranges.
3. Watch idle: Start / Progression / Recent / Status horizontal navigation.
4. Watch Progression: Today / 7d / 28d vertical depth + tappable cards.
5. Start a short WALK test.
6. iPhone active: Summary/Cardio/Map/Terrain/Conditions pages and Stop confirmation.
7. Watch active: four horizontal pages + metric drill-down + controls.
8. Finish workout: effort + perceived effort + route + elevation profile.
9. Apple Fitness/Forme: verify NEW workout type, source app name and source icon.
10. Reliability later: iPhone lock/background/app restart, Watch unreachable/reconnect, weak GPS, longer session, duplicate prevention and battery.

## Known open product items

- surface/road/trail/gravel requires a real cartographic source before it can be trustworthy;
- Apple Health/Fitness Auto workout semantic reconciliation remains a separate physical-validation-led chantier;
- Apple workout-effort APIs can be integrated later with availability guards and clear provenance;
- deletion convergence across iPhone/Watch remains to be designed/tested before exposing broader destructive controls;
- full reliability/battery validation requires hardware.

## Do not modify

- no merge to main, release, or promotion without explicit user approval;
- no purge/history rewrite for UX work;
- no HealthKit workout replacement/deletion without dedicated design and validation;
- no iLoader backend changes unless the transient Code 48 becomes reproducible and needs its own fix.
