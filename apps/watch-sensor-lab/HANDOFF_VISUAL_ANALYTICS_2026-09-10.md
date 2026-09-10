# HANDOFF — Visual analytics + compact Watch launcher

Date: 2026-09-10

## Objective

Raise Watch Tracker from prototype-like UI toward a coherent sport/health product while preserving the existing tracking engine and Watch live-workout authority.

This tranche directly addresses physical feedback from the installed `e8854651...` checkpoint:

1. iPhone Progression visually showed only the two local Tracker sessions instead of the broader readable Apple Health workout history.
2. iPhone Progression lacked real sport-app period analysis, comparisons, richer graphs and sport filtering.
3. Watch idle Start page did not fit cleanly: the selected `Auto` activity dominated the top and the Start button was clipped at the bottom.
4. iPhone/Watch visual language still felt too monochrome and prototype-like.

The active-workout Watch pages have still not been physically UX-tested and must not be redesigned based on guesses.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-visual-analytics-20260910`
- branch base: `9a41838d1e7847258e02e3b88517b8f8788d2a83`
- base code checkpoint physically installed: `e8854651b564c40a8611a32228f1de6fd96b5d1b`
- base CI run: `34513228617` SUCCESS
- base IPA SHA-256: `27fcfdc7fcdefdfd955c208b3a05cdc6d49d531bdfb9b5a9b700600100c2e210`
- verify exact branch HEAD before any continuation.

## Latest physical observations

- installation of `e8854651...` initially hit `IXErrorDomain Code=48` / process-scoped `streaming_zip_conduit` coordinator.
- a plain retry immediately succeeded; no new iLoader/isideload fix was required for that occurrence.
- Watch idle main screen physically did not fit: large current activity/Auto area plus controls pushed `Démarrer` partly off-screen.
- user wants the Watch home compact, intentional and page-driven, not a long downward scroll.
- user prefers a large `Démarrer` action first, followed by a visual sport/Auto chooser.
- phone/heart/GPS readiness indicators should remain but be much more discreet.
- iPhone Progression currently appears to use only Tracker-local sessions and needs Health-wide period analytics.
- active workout mode remains NOT physically UX-tested.

## Research direction

Applied current product/design patterns rather than cloning any one app:

- detailed multi-period charts belong primarily on iPhone; Watch should surface glanceable summaries and simple actions;
- progression should expose current values, personal reference/comparison and time-range switching;
- long-term trends should support daily/weekly/monthly/yearly-scale views;
- Watch pages should each have one clear purpose and fit within a single screen when practical.

## Changes on this branch

### iPhone — Performance Progression

Added `iphone/Sources/PerformanceProgressionView.swift` and routed `ProgressionEntryView` to it.

The activity side now reads `HealthWorkoutHistoryReader`, not `NativeSessionStore`, so activity analytics use every workout Apple Health makes readable to Watch Tracker, regardless of recording app.

Current controls:

- periods: `7 j`, `1 mois`, `6 mois`, `1 an`, `Tout`;
- global sport filter populated from the actually readable Health workout activities;
- metric selector for trend chart: active time, distance or session count;
- current-period KPI cards: active time, distance, sessions, active energy;
- comparison against the preceding equivalent period where applicable;
- automatic chart bucketing: day for short windows, week for 6/12-month windows, month for all-time;
- sport-distribution donut based on activity duration;
- compact Health signal cards for resting HR, HRV SDNN, recent sleep and VO2 max using the existing Health reader and personal 28-day baselines where available;
- richer visual hierarchy with distinct accents, gradients and materials while staying in dark mode;
- missing Health data remains unavailable rather than being converted to zero.

The existing Health history screen remains separate and intact.

### Watch — compact launch flow

`WatchSensorLabApp.swift` was rebuilt around a compact idle experience.

Horizontal top-level pages remain:

1. Start
2. Progression
3. Recent

The new Start page:

- removes the large activity title/picker stack;
- uses one dominant full-width `Démarrer` control that fits on screen;
- shows the currently selected activity only as a small secondary label;
- reduces phone/Health/GPS readiness to tiny status icons;
- keeps auto-pause as a compact secondary icon action;
- tapping `Démarrer` opens a dedicated sport launcher rather than starting immediately.

The sport launcher:

- is vertical page-based rather than a long list;
- presents four large sport buttons per page;
- prioritizes Auto, Walk, Run, Cycle, Hike, Swim, Row, Triathlon, strength, HIIT, elliptical, yoga and common sports first;
- still exposes the complete existing `ActivityKind` catalogue across subsequent pages;
- selecting a sport applies it and starts through the existing `SensorModel` authority path.

Watch Progression and Recent idle pages were also given stronger color/visual hierarchy while remaining fixed-screen and glanceable.

### Active Watch workout preservation

The existing active-workout UI was moved without intentional behavior changes to `watch/Sources/WatchActiveWorkoutView.swift`.

This is structural isolation only so the idle redesign does not accidentally mix with the still-pending physical active-workout UX verdict.

No tracking algorithm, SensorModel authority logic, HealthKit workout recording, auto classifier, pause/resume algorithm or WatchConnectivity revision contract was intentionally changed in this tranche.

## Validation state

- NOT CI validated yet.
- NOT physically validated yet.
- base `e8854651...` is the last CI + installed code checkpoint.
- active workout UI remains physically unvalidated as a UX surface.

## Required next validation

1. run existing `watch-sensor-lab-bootstrap.yml` manually against the exact final HEAD of this branch;
2. if CI fails, fix only the actual compile/build cause;
3. if CI succeeds, retrieve exact-SHA IPA with existing `UPDATE_WATCH_SENSOR_LAB.ps1` from a dedicated worktree;
4. upgrade in place with the already validated iLoader path; do not purge history;
5. physically verify iPhone Progression across 7 j / 1 month / 6 months / 1 year / All and confirm historical Health workouts contribute;
6. physically verify Watch Start fits fully, readiness icons are discreet, and `Démarrer` -> sport pages -> start interaction is usable;
7. verify horizontal Start/Progression/Recent navigation remains smooth;
8. only then perform the separate active-workout UX test and collect observations before changing active pages.

## Do not modify

- do not merge to main without explicit user approval;
- do not modify iLoader/isideload as part of this visual tranche;
- do not purge or rewrite Health/Tracker history;
- do not weaken Watch live-workout authority or revision/session stale rejection;
- do not redesign active-workout pages until the pending physical test is observed.
