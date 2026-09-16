# Device candidate — Auto-pause + OSM surface integration — 2026-09-16

This note intentionally carries no runtime code. Its commit is the exact-SHA CI/device-candidate trigger for the combined test branch.

## Integration parents

- Auto-pause parent: `37fe5226d3eea6f5c8a4efa9b9878bb3a4b8cdbb`
- OSM parent: `3f453f32ff5cbb41274e9f32a33390b477989a59`
- Combined runtime merge commit: `9e329e6e140daea9c84a971c8bf9bb86f46a47e2`
- Test branch: `feat/watch-sensor-integration-auto-pause-osm-20260916`

## Conflict resolution

The OSM feature branch still contained the older per-sport Auto-pause settings UI. The integration keeps the current adaptive Auto-pause UI/runtime from the Auto-pause parent (master toggle + no user timing sliders) and adds only the independent `Type de revêtement (OSM)` map toggle. No Auto-pause runtime source was replaced by the OSM branch.

## Validation intent

This branch exists so one physical outing can observe both features together:

- current neutral-start/adaptive Auto-pause behavior remains under validation;
- OSM surface/type map matching, live display, persistence, summary and effort contribution are also observed;
- a successful combined outing can contribute evidence for both features, but each observation must still be recorded explicitly; one feature working does not automatically validate the other.

Do not merge this branch to `main`, publish a release, or call either feature physically validated until exact-SHA CI is green and the corresponding behavior has actually been observed on iPhone/Apple Watch.
