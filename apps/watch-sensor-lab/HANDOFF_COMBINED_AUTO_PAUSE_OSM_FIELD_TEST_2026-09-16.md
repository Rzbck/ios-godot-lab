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

### Auto-sport clarification still needed

Final activity is `walking` in Tracker and HealthKit. Auto classification briefly switched `walking -> running -> walking` twice (about 6 s near the start and about 3 s near 12:59 UTC). This is a defect only if the user did not actually jog at those moments.

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

## Physical UI observations from user

1. OSM live context is not shown on the Apple Watch. Future UI should expose useful surface/road context on Watch while keeping OSM network requests on iPhone.
2. On iPhone the OSM bar is inserted at the top of the activity screen even though an existing designated UI slot already exists for this kind of information. Reuse the existing slot instead of adding a competing top safe-area bar.

## Still not physically proven

- detailed OSM map colored segments were visually checked;
- final OSM summary/percentages were visibly correct;
- offline/cache behavior;
- whether the two short automatic running classifications were real jogging or false positives.

Do not merge to `main`, release, or call either feature fully validated from this outing alone.
