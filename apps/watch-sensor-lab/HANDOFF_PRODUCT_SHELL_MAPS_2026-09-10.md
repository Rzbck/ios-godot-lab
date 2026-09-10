# HANDOFF — Product shell, depth, maps, workload and automated CI

Date: 2026-09-10

## Objective

Build Watch Sensor Lab into a compact depth-first sports app while preserving existing tracking authority/recorder semantics, and keep the GitHub Actions → exact build → Windows updater → iLoader pipeline automatic and auditable.

User priorities:
- Today first;
- tap cards/zones for deeper information;
- Watch: horizontal major sections + vertical/crown/tap depth, no long free-form scrolling;
- current-vs-previous graphs;
- sport-aware live pages;
- maps + elevation/terrain context;
- estimated effort + perceived effort + workload context;
- polished, compact sports-app UI on iPhone and Watch.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-product-shell-maps-20260910`
- branch base: `e46e3d09687b677023512a8fe685161725c73a51`
- latest build-producing code SHA before this docs commit: `886497a0d3169b8b21b72d46dbe7a8bcc4687c15`
- CI run for that SHA: `34525959462` SUCCESS
- CI job: `103035098751` SUCCESS
- artifact ID: `10171670509`
- artifact: `watch-sensor-lab-companion-886497a0d3169b8b21b72d46dbe7a8bcc4687c15`
- artifact digest: `sha256:b31ca903cc9d86b92ca6a2fad2faa8ffbe6993f4c27fa1511cd6159e0112698c`
- artifact expires: 2026-09-24
- latest physically observed visual-analytics base remains `9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- current combined product-shell candidate is NOT physically validated yet.

Always verify branch HEAD and compatible BUILD SHA before local sync.

## Master plan

`apps/watch-sensor-lab/PRODUCT_UX_MASTERPLAN_2026-09-10.md`

Covers screen hierarchy, Watch depth, maps/terrain, effort/workload, Apple Health/Fitness, sync/reliability, visual system and hardware validation gates.

## Implemented product UI

### iPhone Today

`TodayExperienceView.swift`:
- all Apple Health workouts accessible to the app;
- Today hero with sessions, active time, distance and energy;
- tappable sessions/time/distance/steps cards;
- Today workout drill-down with source;
- 7-day mini chart;
- tappable resting HR / HRV / sleep / VO2 cards.

### iPhone Progression

`PerformanceProgressionTodayView.swift`:
- Today / 7d / 1 month / 6 months / 1 year / all;
- sport filter;
- current and previous period overlaid/cumulative comparison;
- Today activity drill-down;
- sport distribution;
- Health/recovery drill-down.

`TrainingVolumeInsightView.swift`, added at build SHA `886497a0...`:
- accessible from Progression through a gauge/depth action;
- recent 7-day active workout duration;
- independent reference = weekly average of the 28 days immediately preceding the recent 7-day window;
- chart with four reference weeks + current 7 days;
- sport filter;
- recent sport breakdown and contributing sessions;
- explicitly labelled as workout **volume context**, not physiological/medical training load.

### iPhone active shell

`ActivityProductContainerView.swift`:
- inactive launcher retained;
- active Summary / Cardio / Map when relevant / Terrain when relevant / Conditions;
- persistent controls;
- Stop confirmation;
- focused metric detail.

No intentional change to iPhone `TrackerModel` authority/tracking logic in this product-shell work.

### Watch idle/depth

Top-level horizontal pages:
1. Start;
2. Progression;
3. Recent;
4. Status.

`WatchProgressionDepthView.swift`:
- Today / 7d / 28d vertical depth;
- compact current-vs-previous graph;
- tappable focused details.

`WatchStatusDepthView.swift`:
- device/sync;
- Health/GPS;
- 7d-vs-28d volume/workload context.

### Watch active presentation

`WatchActiveWorkoutView.swift` horizontal pages:
1. Primary metrics;
2. Effort/Cardio;
3. Route/Terrain;
4. Controls.

Distance/heart/energy/terrain cards have focused depth. Pause/Resume/Stop/Triathlon still call existing `SensorModel` methods. No intentional SensorModel tracking/classifier changes.

### Maps / terrain

`TrackerMapPresentation.swift`:
- Plan / Hybrid / Satellite;
- persistent `tracker.map.style`.

`SessionTerrainAnalysis.swift` + post-activity:
- retained GPS/altitude analysis;
- elevation profile and amplitude;
- max uphill/downhill grade;
- descriptive relief;
- route start/end markers.

Road/trail/gravel is intentionally NOT inferred without a trustworthy cartographic source.

### Effort

`TrackerEffortInsight.swift`:
- Watch Tracker estimated effort 1–10 from available HR-zone/duration/continuity/elevation/environment context;
- separate user perceived effort 1–10;
- perceived effort is never overwritten.

Apple currently exposes `workoutEffortScore` and `estimatedWorkoutEffortScore`; do not mix these silently with Tracker estimates. Future integration must use availability guards and explicit provenance because deployment minimums remain iOS 17/watchOS 10.

## Automated CI pipeline

Workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`

### Automatic trigger

- fallback manual `workflow_dispatch` retained;
- automatic push on `feat/watch-sensor-*`;
- builds only when actual app/build inputs change:
  - `apps/watch-sensor-lab/iphone/**`
  - `apps/watch-sensor-lab/watch/**`
  - `apps/watch-sensor-lab/Shared/**`
  - `apps/watch-sensor-lab/godot/**`
  - `apps/watch-sensor-lab/GENERATE_APP_ICON.py`
  - `.github/workflows/watch-sensor-lab-bootstrap.yml`
- docs/HANDOFF/tooling-only commits do not launch app builds;
- branch-scoped concurrency with `cancel-in-progress: true`.

Verified behavior:
- automatic trigger SHA `a98e28267f1e95d3f49d6d987916aed6f5865700` → run `34524691563` SUCCESS;
- hardened workflow SHA `d8e4f2a36ec49bc2185b163f68fc0380f963a17c` → run `34525075345` SUCCESS;
- docs-only SHA `0014e319502bc8555b5c1ecbe2dc00f20f6dfe63` → zero workflow runs;
- intermediate feature SHA `1b07f2957f7c4da3e74412d72d08653f673404d2` was cancelled during iPhone build when `886497a0...` superseded it;
- final feature SHA `886497a0...` → run `34525959462` SUCCESS and artifact uploaded.

### Security / reproducibility

- `permissions: contents: read`;
- checkout pinned to immutable `3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1);
- `persist-credentials: false`;
- upload-artifact pinned to immutable `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1);
- Godot 4.7.2 macOS SHA-256 verified before execution: `c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e`;
- XcodeGen 2.46.0 SHA-256 verified before execution: `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`;
- artifact upload uses compression level 0 for already-compressed IPA/ZIP payloads;
- run summary records full build SHA, event/ref, IPA SHA-256, artifact ID/digest/URL and says hardware validation was NOT performed.

No automatic PR/fork runner was added: this is a public repository and the macOS workflow executes checked-out code. Keep untrusted fork code out of this trusted build path unless a separate restricted PR workflow is designed.

Do not globally enable Dependabot `github-actions` from this chantier because this repository has multiple applications/workflows; avoid cross-project automation changes. Pins for this workflow are maintained explicitly.

Artifact attestations are reserved for deliberate distributed/release candidates rather than every iterative push.

## Windows exact-compatible build resolver

`UPDATE_WATCH_SENSOR_LAB.ps1` updated at `71691f4fff024699748edd62963c96aab3cf63c2`.

It distinguishes:
- branch HEAD;
- BUILD SHA that produced the IPA.

A previous successful BUILD SHA may be reused only when:
1. it is an ancestor of current HEAD; and
2. `git diff` proves no build-relevant path changed between BUILD SHA and HEAD.

Otherwise it refuses stale output or dispatches a current build when allowed. Artifact metadata must equal BUILD SHA and downloaded IPA SHA-256 is verified. `LATEST.json` records both SHAs.

This is required because docs/tooling-only commits intentionally do not consume a macOS runner.

## Validation state

CI validated:
- product shell/maps `c041402c...`: run `34524343565` SUCCESS;
- auto trigger `a98e2826...`: run `34524691563` SUCCESS;
- hardened CI `d8e4f2a3...`: run `34525075345` SUCCESS;
- recent-volume product depth `886497a0...`: run `34525959462` SUCCESS.

NOT physically validated yet:
- new Today/depth shell;
- Progression ranges/comparison/recent volume;
- Watch 4-page idle shell and progression/status depth;
- redesigned active Watch pages;
- iPhone active sport-aware pages;
- map style + elevation profile presentation;
- estimated/perceived effort in combined candidate;
- new workout type/source icon in Apple Fitness/Forme.

## Next work

Before changing recorder semantics:
1. refine effort provenance: Tracker estimate vs Apple-provided effort when available;
2. refine sport-specific metric/detail cards without overcrowding;
3. evaluate trustworthy cartographic trail/surface source before road/trail/gravel labels;
4. then exact compatible-build sync and hardware test;
5. after hardware feedback, tackle Auto Health/Fitness semantic reconciliation and reliability cases (background/restart/disconnect/reconnect/weak GPS/long session/battery/duplicate prevention).

## Hardware test order

1. iPhone Today + drill-down.
2. Progression: ranges, current-vs-previous, Volume récent.
3. Watch idle: Start / Progression / Recent / Status.
4. Watch Progression depth.
5. short WALK.
6. iPhone active pages.
7. Watch active pages + depth + controls.
8. finish: effort/perceived effort/map/elevation.
9. Apple Fitness/Forme: verify NEW workout type, source app name and source icon.
10. later reliability matrix.

## Do not modify

- no merge to main/release/promotion without explicit approval;
- no purge/history rewrite for UX work;
- no HealthKit workout replacement/deletion without dedicated design + validation;
- no iLoader/backend change unless Code 48 becomes reproducible.
