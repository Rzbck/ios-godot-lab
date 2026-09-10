# HANDOFF — Watch Tracker product UX

Date: 2026-09-10

## Objective

Turn `watch-sensor-lab` into one coherent iPhone + Apple Watch product without changing the core tracking contract: Apple Watch remains the single live-workout authority; iPhone becomes the richer home, configuration, supervision, history and analysis surface.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-product-ux-20260910`
- base v0.4 SHA: `ab77fe270838fca2793b77dcff6f84c4e46cad4f`
- device-test checkpoint SHA: `fa28758bda549deaddbbc12c24eb869d0965af4b`
- local Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-product-ux`
- verify current branch HEAD before any continuation.

## Current CI-validated checkpoint

SHA `fa28758bda549deaddbbc12c24eb869d0965af4b`

- GitHub Actions run `34507870711` — SUCCESS.
- iPhone unsigned native build: SUCCESS.
- watchOS unsigned companion build: SUCCESS.
- HealthKit declarations: SUCCESS.
- companion assembly: SUCCESS.
- exact-SHA companion IPA packaging/upload: SUCCESS.
- artifact: `watch-sensor-lab-companion-fa28758bda549deaddbbc12c24eb869d0965af4b`.
- artifact ID: `10164656063`.
- downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\fa28758bda54\WatchSensorLab-companion-unsigned-fa28758bda54.ipa`.
- IPA SHA-256: `3f782f0a6c6845d6a28af65610116e0826c99c1408a7a1eca81d0da41e987e62`.
- this is CI + exact artifact validation only; the redesigned UX/settings/history slice is NOT yet physically validated on iPhone/Watch.

## UX included in this checkpoint

- iPhone opens on `Aujourd’hui`, not a full-screen map.
- primary navigation: Aujourd’hui / Activité / Progression / Historique.
- live iPhone activity hierarchy: Résumé / Carte / Détails.
- deterministic map recenter/follow implementation awaiting physical verification.
- HealthKit Progression dashboard: resting HR, HRV SDNN, recent sleep, VO2 max, steps, active energy, exercise minutes, personal baselines and HR/HRV trends.
- missing HealthKit data is shown as unavailable, never converted to zero.
- Today contextual Health snapshot appears only after the user has explicitly visited Progression.
- History is a first-class destination with period overview, search, sport filters and improved detail hierarchy.
- activity detail can compare against up to 8 recent same-sport sessions of comparable distance for pace, average HR and cadence.
- profile/settings button opens a real iPhone settings screen.
- iPhone is the configuration surface for master auto-pause and per-sport Walk/Hike/Run/Cycle profiles.
- safe migration: a phone profile is not sent until the user edits it, preserving existing Watch-local custom values.
- preferences are re-sent before START and when Watch reachability returns.
- Watch persists received phone profiles into its existing local auto-pause keys so later WatchConnectivity application-context replacements do not lose them.
- Watch UI is simplified for glanceability and advanced auto-pause configuration was removed from the Ready screen.
- obsolete duplicate iPhone Activity/Progression prototype views were removed.

## Physical validation still required

Upgrade in place; do not purge or manually uninstall first.

1. confirm existing history remains after upgrade;
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

1. install the exact IPA `WatchSensorLab-companion-unsigned-fa28758bda54.ipa` through the already validated auth-fixed iLoader path, as an upgrade over the existing app;
2. confirm iPhone + Watch installation succeeds;
3. verify preserved history before starting a new workout;
4. perform visual/interaction checks first, then a short real workout for sync, map recenter and auto-pause-profile validation;
5. record hardware observations before any additional UX code changes.
