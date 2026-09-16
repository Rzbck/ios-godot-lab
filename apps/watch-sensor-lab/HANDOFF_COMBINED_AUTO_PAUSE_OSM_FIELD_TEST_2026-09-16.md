# HANDOFF — Combined Auto-pause + OSM field test — 2026-09-16

## Tested runtime

- Repository: `Rzbck/ios-godot-lab`
- Branch: `feat/watch-sensor-integration-auto-pause-osm-20260916`
- Physically tested runtime SHA: `26862ac4c6334b4a98cb2ca6d208f2e1343f1a71`
- Combined runtime merge: `9e329e6e140daea9c84a971c8bf9bb86f46a47e2`
- Auto-pause parent physically tested here: `37fe5226d3eea6f5c8a4efa9b9878bb3a4b8cdbb`
- OSM parent: `3f453f32ff5cbb41274e9f32a33390b477989a59`
- Field session: `1789561072024`

This outing does not validate later Auto-pause reactivity/haptics work such as `9ef0d15c514caa72a28e96824c0336bf0a0e8c1a`.

## Auto-pause forensic result

- Started from Watch in `automatic`; iPhone joined the same session.
- 18 pause candidates, 13 correctly cancelled by evidence vetoes, 5 confirmed automatic pauses.
- 4 confirmed automatic resumes; the fifth pause was followed directly by session end.
- Confirmed pause dwell: about 6.0–6.3 s on every pause.
- Pause/resume mirrored HealthKit states converged between Watch and iPhone within roughly 0–0.22 s in captured events.
- No confirmed pause/resume oscillation loop was observed.
- After finish, iPhone returned to `ready`, no active session and no pending command.
- Saved HealthKit workout exists for this session.

### Defect: stop while auto-paused double-counts final pause in local duration

- Tracker summary duration: `3583.0287 s`.
- Saved HealthKit workout duration: `3619.1244 s`.
- Difference: about `36.10 s`.
- Final `pause_until_end`: `36.09 s`.
- Strong evidence that the final paused interval is subtracted twice from the local Tracker summary when the workout is ended while paused.

### Defect confirmed: fast walking misclassified as running

User physically confirms the whole outing was walking only; there was no jogging/running. Therefore both short `walking -> running -> walking` transitions are false positives.

The tested Auto policy classifies running from sensors when `speed >= 1.7 m/s` and `cadence >= 95 steps/min` for a 2 s dwell. The forensic run crossed that threshold while fast-walking:

- first false run: Watch about `1.79 m/s` with about `104.5 steps/min`;
- second false run: Watch about `1.70–1.72 m/s` with about `106 steps/min`.

This threshold is too permissive for fast walkers. Do not fix by speed alone. Rework walk/run classification with stronger gait evidence and hysteresis; cadence near 95–106 steps/min must remain compatible with brisk walking. Published gait-transition literature places spontaneous walk/run transition roughly around 1.9–2.1 m/s for healthy adults and reports cadence around 135–140 steps/min as a substantially stronger transition discriminator than the current 95 steps/min threshold.

## OSM forensic result

- Persisted `osm_context.json`: present.
- 140 persisted route segments.
- OSM segment total: about `5752.23 m`.
- Tracker/Watch summary distance: about `5505.70 m`.
- iPhone filtered route geometry: about `5744.17 m`.
- OSM is internally consistent with iPhone route geometry (~0.14 % difference) but about 4.5 % above the canonical Tracker/Watch distance. Final product summary should normalize or otherwise reconcile these distances.

Surface distance breakdown:

- asphalt: ~2641.18 m (45.9 %)
- unknown: ~2124.25 m (36.9 %)
- gravel: ~315.25 m (5.5 %)
- pebblestone: ~233.71 m (4.1 %)
- dirt: ~156.24 m (2.7 %)
- other known surfaces: concrete, paving stones, sett, fine gravel, ground, paved

Unknown handling:

- ~1837.16 m matched an OSM way/highway with no `surface=*`; must display `Inconnu` and add zero invented surface roughness.
- ~287.09 m had no matched OSM way and are also unknown.

Map matching:

- weighted matched confidence about 86 %.
- 32 segments shorter than 10 m; 62 shorter than 20 m. Visually inspect junction/parallel-way churn before tuning.

Effort contribution for this walking session:

- known surface coverage about 63.1 %.
- OSM surface contribution about `+0.025` to Tracker effort, displayed approximately as `+0.03`.
- unknown surface contributes zero.

No app-level error records were returned in the captured error diagnostics. Cache/offline behavior is not proven by this archive because the OSM cache directory was not collected and dedicated Overpass/cache telemetry is insufficient in this candidate.

## Physical OSM/UI observations from user

The OSM data pipeline worked in the archive, but the feature is not acceptably integrated in the product UI yet.

1. **Apple Watch:** no OSM live context was visible during the workout. Keep OSM network access on iPhone, but mirror the resulting current surface/highway context to Watch and integrate it into the existing Watch route/terrain experience.
2. **iPhone live activity:** the candidate added a separate OSM bar at the top of the activity screen. This is the wrong location. `ActivityProductContainerView` already contains the intended `Terrain` page and an explicit `SURFACE` slot currently saying `Non déterminée en direct`; wire OSM into that existing slot instead of adding a competing top safe-area bar.
3. **iPhone map:** the normal activity UI already has a `Carte` page. OSM colored route segments should be rendered in that existing map rather than hidden behind a separate OSM sheet/map that the user could not find.
4. **History:** after the workout, opening this activity from `Historique` showed no visible OSM information. `ActivityDetailView` must load persisted `osm_context.json`, render the route with surface colors, show surface/highway breakdown and percentages, and expose the OSM contribution to effort there.
5. **Finish from Watch:** because the workout was ended from Watch, the user saw no final OSM summary. OSM cannot depend on an iPhone-only transient finish sheet; the persisted summary must be discoverable later from History on iPhone, and useful compact context should also reach Watch where practical.

The user did not find or see the separate OSM detail map at any point. Treat this as a product discoverability/integration failure, not as proof that map rendering itself is broken.

## Next implementation targets

1. Fix fast-walk -> running false positives with gait-aware thresholds/hysteresis, not a single low speed/cadence gate.
2. Fix local duration when ending while auto-paused.
3. Remove the separate top `OSMLiveSurfaceBar` integration path.
4. Feed OSM into the existing iPhone `Terrain > SURFACE` slot.
5. Feed colored OSM segments into the existing iPhone `Carte` page.
6. Load persisted OSM context in `ActivityDetailView` / History and show map + breakdown + effort contribution.
7. Mirror compact OSM current context from iPhone to the Watch and integrate it into `WatchRouteTerrainPage`; Watch must never perform Overpass requests itself.
8. Reconcile OSM segment distances against canonical Tracker/Watch distance before presenting final percentages/distances.
9. Add regression tests for brisk walking around 1.7–1.9 m/s with ~100–120 steps/min so it cannot become running solely from these signals.

## Still not physically proven

- correct visible OSM surface/road context on Watch;
- OSM colored segments integrated into the normal iPhone map;
- OSM summary and percentages visible in History;
- offline/cache behavior;
- a corrected walk/run classifier on a new physical build;
- a corrected stop-while-paused duration on a new physical build.

Do not merge to `main`, release, or call either feature fully validated from this outing alone.
