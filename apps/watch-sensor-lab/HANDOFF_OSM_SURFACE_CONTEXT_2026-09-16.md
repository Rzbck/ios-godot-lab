# HANDOFF — OSM surface / road context

Date: 2026-09-16

## Objective

Add OpenStreetMap-derived road/surface context to Watch Tracker without touching the parallel Auto-pause chantier. Missing OSM tags stay unknown and are never inferred from GPS alone.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-osm-surface-context-20260916`
- original OSM prototype base: `886497a0d3169b8b21b72d46dbe7a8bcc4687c15`
- original OSM prototype code SHA: `42d8685655eb5e024e2e154d16323dd3b1106140`, run `35089788558` SUCCESS; this is superseded as the device-test base because it predates the latest user-validated product baseline.
- **user-indicated physically validated product base:** `f97aaf09181763d9e816fced23da040d6da6819a`, as recorded by `HANDOFF_AUTO_BEHAVIOR_2026-09-14.md`.
- this branch is now merged forward onto that physically validated product base without taking the later Auto-pause WIP changes.
- parallel Auto-pause branches remain separate and must not be modified by this chantier.

## Implementation

`iphone/Sources/OSMSurfaceContext.swift` provides:

- public Overpass client at `https://overpass-api.de/api/interpreter`;
- `highway` ways plus `surface`, `highway`, `tracktype`, `smoothness`, `name` tags;
- ~1 km query zones, 24 h disk cache, request spacing and bounded in-memory zone retention;
- lightweight local map matching against OSM way geometry;
- confidence from distance-to-way and GPS horizontal accuracy;
- explicit `Inconnu` when `surface=*` is absent;
- per-session persistent sidecar `Sessions/<sessionID>/osm_context.json`;
- distance/percentage breakdown by surface and highway type;
- segmented coordinates for colored route rendering;
- visible `© OpenStreetMap contributors · ODbL` attribution in OSM detail views.

`TrackerApp.swift` feeds accepted iPhone coordinates into OSM without changing Watch workout authority or `TrackerModel` recorder semantics. A compact live surface bar opens a color-segmented OSM route view. Post-STOP, the normal summary is wrapped with a persisted OSM breakdown/detail view.

`TrackerSettingsView.swift` now contains the requested `Type de revêtement (OSM)` toggle. It defaults on and can disable OSM network/matching/display independently of workout tracking.

`TrackerEffortInsight.swift` adds a bounded `surfaceContribution` to the local Tracker estimate while preserving Apple estimated/perceived effort and user perceived effort as separate provenance. Surface weight is sport-aware, coverage-weighted, uses `surface/smoothness/tracktype`, and unknown surface contributes zero.

## Privacy / network behavior

- while enabled, the current query-zone coordinates are sent to the public Overpass endpoint;
- MapKit remains the basemap; no OSM tile server is used;
- no query per GPS point; cached zones and request spacing are mandatory;
- public Overpass is for modest/prototype usage only. Scale-up requires a suitable provider, own instance or regional extracts.

## Validation state

- validated source baseline: `f97aaf09181763d9e816fced23da040d6da6819a` — **physically validated product base according to the project handoff**;
- OSM feature itself: **IMPLEMENTED, NOT physically validated**;
- CI must pass on the merge-forward candidate before any install;
- no merge into Auto-pause, `main` or release.

## Required tests

1. Exact-SHA CI: iPhone + watchOS + HealthKit declarations + companion IPA.
2. Install through existing `UPDATE_WATCH_SENSOR_LAB.ps1` / iLoader pipeline only after CI success.
3. Route asphalt → gravel/track → asphalt with known OSM tags.
4. `highway=*` without `surface=*`: UI must say `Inconnu` and effort must add zero surface penalty for that part.
5. Parallel roads/intersections/degraded GPS: inspect map-match confidence and false matches.
6. Network loss after zone cache: context should continue from cache.
7. Relaunch: `osm_context.json` and old summary must stay stable.
8. Compare summary percentages to raw route/OSM tags.
9. Compare effort before/after for walking/running/cycling before tuning coefficients.
10. Check battery/network usage and visible OSM attribution.

## Integration discipline

Keep OSM and Auto-pause independent while Auto-pause is under physical test. Once each is accepted separately, create a dedicated integration branch from the accepted newer line, merge/cherry-pick OSM there, resolve only real conflicts, run exact-SHA CI/tests, then perform a combined iPhone/Watch regression before any promotion.