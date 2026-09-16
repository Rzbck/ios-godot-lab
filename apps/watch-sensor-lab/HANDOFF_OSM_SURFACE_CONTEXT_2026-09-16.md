# HANDOFF — OSM surface / road context

Date: 2026-09-16

## Objective

Add OpenStreetMap-derived road/surface context to Watch Tracker without touching the parallel Auto-pause chantier. The feature must remain provenance-first: missing OSM tags stay unknown, never inferred from GPS alone.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-osm-surface-context-20260916`
- base SHA: `886497a0d3169b8b21b72d46dbe7a8bcc4687c15`
- base CI run: `34525959462` — SUCCESS
- base status: **CI VALIDATED**, **NOT physically validated**. This base was chosen because it already contains the MapKit product shell and local effort estimator required by this feature. Do not relabel it as physically validated.
- parallel Auto-pause branch is separate and must not be modified by this chantier.

## Exact OSM implementation candidate

- code SHA: `42d8685655eb5e024e2e154d16323dd3b1106140`
- commit: `feat(tracker): add OSM road surface context`
- GitHub Actions run: `35089788558` — **SUCCESS**
- CI job: `104773123198` — **SUCCESS**
- artifact id: `10443886292`
- artifact name: `watch-sensor-lab-companion-42d8685655eb5e024e2e154d16323dd3b1106140`
- artifact digest: `sha256:c792a21ae3cf6f4a65651b0509aff66cb4d9d58c0b7df9c125be15af48ebf72b`
- iPhone unsigned build: SUCCESS
- watchOS unsigned build: SUCCESS
- HealthKit declarations: SUCCESS
- embedded Watch companion assembly: SUCCESS
- exact-SHA companion IPA package/upload: SUCCESS
- status: **BUILD CI VALIDÉ**, **NOT physically validated on iPhone/Watch**.

This documentation commit may move branch HEAD ahead of the code SHA without launching another build. For installation/testing, resolve the compatible BUILD SHA using the existing updater rather than treating the docs-only HEAD as a new binary.

## Implementation

New `iphone/Sources/OSMSurfaceContext.swift` provides:

- public Overpass client using `https://overpass-api.de/api/interpreter`;
- requests only `highway` ways around the route and keeps `surface`, `highway`, `tracktype`, `smoothness`, `name` tags;
- ~1 km zone cache with 24 h disk TTL;
- no request per GPS point: one zone query, minimum request spacing, in-memory zone pruning;
- lightweight local map matching against nearby OSM way geometry;
- confidence based on distance-to-way and GPS horizontal accuracy;
- explicit unknown surface when `surface=*` is absent;
- persistent per-session sidecar `Sessions/<sessionID>/osm_context.json` so history does not change when OSM changes later;
- distance and percentage breakdown by surface and highway type;
- segmented coordinates suitable for colored route rendering;
- mandatory `© OpenStreetMap contributors · ODbL` attribution in OSM detail views.

`TrackerApp.swift` now feeds accepted iPhone coordinates into the OSM service without modifying TrackerModel recorder/authority semantics. During an activity a compact OSM bar shows the current surface/type/confidence and opens a live color-segmented route map. After STOP, the normal post-activity summary is wrapped with a compact OSM summary bar opening the persisted surface/type breakdown.

`TrackerEffortInsight.swift` now adds a bounded `surfaceContribution` to the local Watch Tracker effort estimate. It is sport-aware (cycling > running > hiking/walking), weighted by known OSM distance coverage, uses surface/smoothness/tracktype and gives **zero penalty for unknown surface**. Contribution is capped so OSM tagging cannot dominate the score.

## Privacy / network behavior

- This feature sends the current query-zone coordinates to the configured public Overpass endpoint while enabled.
- It does not use OSM tile servers; MapKit remains the basemap.
- Public Overpass is suitable only for modest/prototype usage. Cache/rate limits are mandatory. Scale-up requires a suitable provider, own Overpass instance or regional extracts.

## Validation state

- **BUILD CI VALIDÉ** for exact code SHA `42d8685655eb5e024e2e154d16323dd3b1106140` / run `35089788558`;
- **NO physical iPhone/Watch validation yet**;
- OSM network/map-matching correctness, UI behavior, persistence, battery impact and effort calibration all remain hardware/field-test items;
- **no merge into Auto-pause, main or release**.

## Required tests

1. Install exact compatible artifact for code SHA `42d8685655eb5e024e2e154d16323dd3b1106140` using the existing Watch Sensor Lab updater/iLoader workflow.
2. Device route with asphalt → gravel/track → asphalt where OSM tags are known.
3. Route with `highway=*` but no `surface=*`: UI must show `Inconnu`, effort adds no surface penalty for that part.
4. Parallel roads / intersection and degraded GPS to inspect confidence and false map-matches.
5. Loss of network after an OSM zone was cached: live context must continue from cache.
6. Verify `osm_context.json` persists and old summary remains stable after relaunch.
7. Verify OSM summary percentages against raw route and OSM tags.
8. Compare effort before/after on representative walking/running/cycling sessions; tune only from real data.
9. Check network/battery behavior on a longer outing.
10. Verify visible OSM attribution in live and summary detail.

## Integration discipline

Keep this branch independent while Auto-pause is still under physical test. When both are individually accepted, merge them into a dedicated integration branch, resolve conflicts there, run exact-SHA CI, then perform a combined device regression test before promoting anything further.