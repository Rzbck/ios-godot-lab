# HANDOFF — Watch Tracker product UX

Date: 2026-09-10

## Objective

Turn `watch-sensor-lab` into one coherent iPhone + Apple Watch product without changing the core tracking contract: Apple Watch remains the single live-workout authority; iPhone becomes the richer home, configuration, supervision, history and analysis surface.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-product-ux-20260910`
- base v0.4 SHA: `ab77fe270838fca2793b77dcff6f84c4e46cad4f`
- verify current branch HEAD before any continuation.

## Last CI-validated checkpoint

SHA `dd667266fcda113e3210f8966670c36e9f542217`

- GitHub Actions run `34505299622` — SUCCESS.
- iPhone unsigned native build: SUCCESS.
- watchOS unsigned companion build: SUCCESS.
- HealthKit declarations: SUCCESS.
- companion assembly: SUCCESS.
- exact-SHA companion IPA packaging/upload: SUCCESS.
- artifact: `watch-sensor-lab-companion-dd667266fcda113e3210f8966670c36e9f542217`.
- this is CI validation only; the redesigned UX has not yet been physically validated on iPhone/Watch.

## UX already present at the green checkpoint

- iPhone opens on `Aujourd’hui`, not a full-screen map.
- primary navigation: Aujourd’hui / Activité / Progression / Historique.
- live iPhone activity hierarchy: Résumé / Carte / Détails.
- deterministic map recenter/follow implementation awaiting physical verification.
- HealthKit Progression dashboard: resting HR, HRV SDNN, recent sleep, VO2 max, steps, active energy, exercise minutes, personal baselines and HR/HRV trends.
- missing HealthKit data is shown as unavailable, never converted to zero.
- History is a first-class destination with period overview and improved detail hierarchy.
- Watch UI is simplified for glanceability and advanced auto-pause configuration was removed from the Ready screen.

## Current post-checkpoint work

Work after `dd667266...` adds:

- Today contextual Health snapshot after the user has explicitly visited Progression;
- profile/settings button opening a real iPhone settings screen;
- iPhone master auto-pause setting plus per-sport Walk/Hike/Run/Cycle profiles;
- pause and resume dwell settings per sport;
- safe migration: a phone profile is not sent until the user edits it, preserving existing Watch-local custom values;
- preferences are re-sent before START and when Watch reachability returns;
- Watch persists received phone profiles into its existing local auto-pause keys so later WatchConnectivity application-context replacements do not lose them;
- History search;
- History sport filters: all / walk / run / cycle / hike / other;
- filters use user-confirmed/corrected activity when available;
- activity detail personal comparison against up to 8 recent same-sport sessions of comparable distance, for pace, average HR and cadence;
- removed obsolete duplicate iPhone Activity/Progression prototype views.

## Validation state of current post-checkpoint work

- NOT YET CI VALIDATED at the time this handoff is written.
- NOT physically validated.
- Must run the existing `watch-sensor-lab-bootstrap.yml` manually on the exact final branch HEAD and record the result before device testing.

## Physical validation still required

When the user has the iPhone and Watch available:

1. upgrade without purge and confirm existing history remains;
2. inspect Today / Activity / Progression / History layouts on real iPhone;
3. verify HealthKit permission UX and missing-data states;
4. verify map location button actually recenters/zooms to the current user position;
5. verify Watch text sizes, controls and vertical pages during a real workout;
6. edit one auto-pause profile on iPhone and verify the Watch applies the same profile;
7. verify START/PAUSE/RESUME/STOP convergence still respects Watch authority;
8. continue the v0.4 physical sensor/HealthKit validation ledger separately.

## Do not modify

- do not merge to `main` without explicit user approval;
- do not modify iLoader/isideload for UX work;
- do not purge or rewrite preserved field-test history/baseline corpus;
- do not weaken Watch workout authority, revision/session stale rejection, HealthKit semantics or diagnostic provenance merely for UI simplification.

## Next exact step

1. verify branch HEAD after this documentation commit;
2. trigger `watch-sensor-lab-bootstrap.yml` with `workflow_dispatch` against that exact SHA;
3. if CI fails, fix the actual compile/test error only;
4. if CI succeeds, mark this UX/settings/history slice CI_VALIDATED and continue polish or physical UX testing depending on device availability.
