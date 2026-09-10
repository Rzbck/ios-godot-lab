# HANDOFF — Product shell, Watch depth, maps, terrain and automated CI

Date: 2026-09-10

## Objective

Turn Watch Sensor Lab from a functional tracker prototype into a compact, depth-first sports product UI while preserving the existing tracking authority/recorder semantics, and make the exact-SHA build pipeline automatic, secure and low-noise.

User priorities:
- Today first;
- tap cards/zones to enter deeper information;
- Apple Watch: left/right for major areas, vertical/crown/tap depth inside an area, no giant free-form ScrollView;
- current-vs-previous graphs;
- sport-specific live pages;
- better maps and terrain/elevation context;
- effort + perceived effort + workload context;
- professional automatic GitHub Actions workflow with exact provenance.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-product-shell-maps-20260910`
- branch base: `e46e3d09687b677023512a8fe685161725c73a51`
- product-shell code was already CI validated at `c041402cd276c8e435a2197ffa317cdc58bb9714`
- manual CI run for that SHA: `34524343565` SUCCESS, job `103029433528`
- current branch HEAD immediately before this docs commit: `71691f4fff024699748edd62963c96aab3cf63c2`
- latest CI-validated build-input SHA before this docs commit: `d8e4f2a36ec49bc2185b163f68fc0380f963a17c`
- latest physically observed visual-analytics base in this lineage remains `9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- product-shell/maps candidate is NOT physically validated yet.

Always verify current branch HEAD and the compatible BUILD SHA before local artifact sync.

## Master plan

Full screen-by-screen product plan:
- `apps/watch-sensor-lab/PRODUCT_UX_MASTERPLAN_2026-09-10.md`

It records information architecture, map/terrain strategy, effort/load strategy, Apple Health/Fitness open points, sync validation matrix, visual system and validation gates.

## Implemented product UI

### iPhone Today

`iphone/Sources/TodayExperienceView.swift` and Today route in `TrackerApp.swift`:
- all Apple Health workouts accessible to the app;
- Today hero: sessions, active time, distance, energy;
- tappable sessions/time/distance/steps cards;
- Today workout list with source + drill-down;
- 7-day mini chart;
- tappable resting-HR / HRV / sleep / VO2 cards;
- direct Activity / Progression / History entry.

### iPhone active product shell

`iphone/Sources/ActivityProductContainerView.swift`:
- inactive state keeps the existing launcher;
- active presentation: Summary / Cardio / Map when relevant / Terrain when relevant / Conditions;
- persistent bottom controls;
- Stop confirmation;
- focused metric detail views.

No iPhone `TrackerModel` tracking/authority logic was intentionally changed by this product-shell work.

### Watch idle + depth

`watch/Sources/WatchSensorLabApp.swift` top-level horizontal pages:
1. Start;
2. Progression;
3. Recent;
4. Status.

`WatchProgressionDepthView.swift`:
- Today / 7d / 28d vertical pages;
- current-vs-previous compact graph;
- tappable focused drill-down.

`WatchStatusDepthView.swift`:
- device/sync;
- Health/GPS;
- 7d vs 28d volume/workload context.

### Watch active workout presentation

`WatchActiveWorkoutView.swift` now presents four horizontal pages:
1. Primary metrics;
2. Effort/Cardio;
3. Route/Terrain;
4. Controls.

Distance, Heart, Energy and Terrain/GPS can open focused detail views. Pause/Resume/Stop/Triathlon still call the existing `SensorModel` actions. No Watch `SensorModel` tracking/HealthKit/classifier logic was intentionally changed in this product-shell work.

### Maps and terrain

`TrackerMapPresentation.swift`:
- Plan / Hybrid / Satellite;
- persistent `tracker.map.style` preference.

`SessionTerrainAnalysis.swift` + post-activity UI:
- retained GPS/altitude analysis;
- elevation profile;
- elevation amplitude;
- max uphill/downhill grade;
- descriptive relief;
- start/end route markers.

Road/trail/gravel surface is intentionally NOT inferred without a real cartographic source.

### Effort inherited from previous tranche

`TrackerEffortInsight.swift`:
- Watch Tracker estimated effort 1–10 using available HR-zone/duration/continuity/elevation/environment context;
- separate user perceived effort 1–10;
- perceived effort is never overwritten by the estimate.

## Automated GitHub Actions pipeline

Workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`

### Trigger policy

- manual `workflow_dispatch` remains as fallback;
- automatic `push` on `feat/watch-sensor-*` branches;
- automatic builds only when build inputs change:
  - `apps/watch-sensor-lab/iphone/**`
  - `apps/watch-sensor-lab/watch/**`
  - `apps/watch-sensor-lab/Shared/**`
  - `apps/watch-sensor-lab/godot/**`
  - `apps/watch-sensor-lab/GENERATE_APP_ICON.py`
  - `.github/workflows/watch-sensor-lab-bootstrap.yml`
- docs/HANDOFF/tooling-only commits do not intentionally trigger an app build;
- `concurrency` is branch-scoped and `cancel-in-progress: true` cancels obsolete runs when a newer build-relevant push supersedes them.

No automatic `pull_request`/`pull_request_target` build was added: repository is public and the macOS job executes checked-out code. Keep untrusted fork code out of this trusted build path unless a separate restricted PR workflow is deliberately designed.

### Security / reproducibility

The hardened workflow build SHA is:
`d8e4f2a36ec49bc2185b163f68fc0380f963a17c`

Hardened auto-trigger CI:
- run `34525075345` SUCCESS;
- job `103031872497` SUCCESS;
- artifact ID `10171318873`;
- artifact name `watch-sensor-lab-companion-d8e4f2a36ec49bc2185b163f68fc0380f963a17c`;
- artifact digest `sha256:825e391bc481d7c7ea4e610f6995914c5bbd71ac1adef7a7494fc748b52b2723`;
- artifact expiration: 2026-09-24.

Workflow hardening:
- `permissions: contents: read`;
- `actions/checkout` pinned to full immutable commit `3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1);
- checkout uses `persist-credentials: false`;
- `actions/upload-artifact` pinned to full immutable commit `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1);
- Godot 4.7.2 macOS archive verified before execution against SHA-256 `c58a24e31d720be9d62f60cb5627c4e695fb72f21b0cfe1bc9ccaa9a3b3ba63e`;
- XcodeGen 2.46.0 archive verified before execution against SHA-256 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`;
- artifact upload uses `compression-level: 0` because IPA/diagnostic ZIP are already compressed;
- final Actions step summary records full build SHA, event/ref, IPA SHA-256, artifact ID/digest/URL and explicitly states that CI did not perform hardware validation.

Preliminary automatic trigger validation also succeeded:
- SHA `a98e28267f1e95d3f49d6d987916aed6f5865700`;
- run `34524691563` SUCCESS;
- event `push`.

Do not enable repository-wide Dependabot `github-actions` casually from this chantier: this repository contains multiple applications/workflows. Action pins for this workflow are currently maintained explicitly to avoid cross-project changes.

Artifact attestations are deliberately not emitted for every iterative push build. Exact-SHA metadata + local IPA SHA verification remain the development pipeline. Consider attestations only for deliberately distributed/release candidates.

## Windows exact-build resolver

`apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1` was updated in commit:
`71691f4fff024699748edd62963c96aab3cf63c2`

Reason: docs-only commits are intentionally excluded from automatic builds, so branch HEAD can be newer than the most recent binary-producing commit.

The updater now keeps separate provenance:
- `branch_head_sha` = current branch HEAD;
- `build_sha` = commit that produced the IPA.

An earlier successful build may be reused ONLY when:
1. its SHA is an ancestor of current HEAD; and
2. `git diff` proves there are zero changes between BUILD SHA and HEAD across the exact build-relevant paths used by the workflow.

Otherwise the updater refuses the stale artifact or triggers the current branch build when allowed.

Artifact metadata must still exactly match BUILD SHA, and IPA SHA-256 is still verified locally after download. `LATEST.json` records both branch HEAD and BUILD SHA plus `build_inputs_match_branch_head=true`.

This preserves binary provenance while allowing documentation/tooling-only branch commits without wasting a macOS build.

For an already-existing local worktree that predates this updater change, fast-forward the worktree once before invoking the updater so the running script itself is the new version.

## Validation state

Validated in CI:
- product-shell/maps code at `c041402c...`: manual run `34524343565` SUCCESS;
- automatic trigger at `a98e2826...`: run `34524691563` SUCCESS;
- hardened automatic workflow at `d8e4f2a3...`: run `34525075345` SUCCESS and artifact uploaded.

NOT yet physically validated:
- new iPhone Today/depth product shell;
- new iPhone active Summary/Cardio/Map/Terrain/Conditions shell;
- Watch 4-page idle shell + deeper Progression/Status;
- Watch redesigned active pages + drill-down;
- new map styles/elevation profile presentation;
- effort/perceived-effort presentation in this combined candidate;
- Apple Fitness/Forme new-workout type/source icon.

Do not equate CI SUCCESS with iPhone/Watch hardware validation.

## Next product work

Continue the master plan without changing recorder authority unless necessary:
1. iPhone Progression: add clearly labelled recent workload/volume section using 7-day active volume vs 28-day weekly baseline, with drill-down; do NOT call duration-only volume a physiological training-load score;
2. later integrate richer effort provenance where platform APIs allow it, keeping Tracker estimate vs Apple-provided effort clearly separated;
3. refine metric drill-down and sport-specific live cards;
4. evaluate a real cartographic surface/trail source before showing road/trail/gravel claims;
5. then exact compatible-build sync + physical test.

## Hardware test order

1. iPhone Today: Apple Health workouts + drill-down.
2. iPhone Progression: ranges/current-vs-previous/workload context.
3. Watch idle: Start / Progression / Recent / Status.
4. Watch Progression: Today / 7d / 28d depth.
5. Short WALK test.
6. iPhone active: Summary/Cardio/Map/Terrain/Conditions + Stop confirmation.
7. Watch active: four horizontal pages + drill-down + controls.
8. Finish: effort + perceived effort + route + elevation profile.
9. Apple Fitness/Forme: verify NEW workout type, source app name and source icon.
10. Later reliability: iPhone lock/background/restart, Watch unreachable/reconnect, weak GPS, longer session, duplicates and battery.

## Known open items

- trustworthy road/trail/gravel surface requires a real cartographic source;
- Apple Health/Fitness Auto workout semantic reconciliation remains a separate physical-validation-led chantier;
- Apple workout-effort APIs require availability/provenance design against iOS 17/watchOS 10 minimum targets;
- deletion convergence across iPhone/Watch remains to be designed/tested before broader destructive controls;
- full reliability/battery validation requires hardware.

## Do not modify

- no merge to main, release or promotion without explicit user approval;
- no purge/history rewrite for UX work;
- no HealthKit workout replacement/deletion without dedicated design and validation;
- no iLoader/backend changes unless transient Code 48 becomes reproducibly problematic.
