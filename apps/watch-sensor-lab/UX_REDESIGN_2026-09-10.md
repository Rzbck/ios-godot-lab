# Watch Tracker — UI/UX redesign plan

Date: 2026-09-10

## Goal

Turn the current feature-rich tracker into one coherent iPhone + Apple Watch product. Preserve the existing technical architecture: Apple Watch remains the single live-workout authority; iPhone is the richer configuration, supervision, history and analysis surface.

This redesign must not remove diagnostics or provenance. It moves them deeper in the information hierarchy so normal users see useful activity/health information first.

## Branch / checkpoints

- repository: `Rzbck/ios-godot-lab`
- branch: `feat/watch-sensor-product-ux-20260910`
- branch base: `ab77fe270838fca2793b77dcff6f84c4e46cad4f`
- first UX implementation checkpoint: `41cfe677c695ce697903b5d81cb905b91f3dd4d1`
- exact CI run for that checkpoint: `34503568827` — **SUCCESS**
- validated by that run: retained Godot prototype, unsigned iPhone build, unsigned watchOS build, HealthKit declarations, embedded companion assembly and exact-SHA IPA artifact.
- second UX code checkpoint: `9d754c39535e675e82bdf7398cc2f7d1bac6b9e2`
- second checkpoint adds the HealthKit progression dashboard plus the redesigned iPhone live Activity experience; **CI validation pending** at the time of this documentation update.
- this documentation commit is expected to be ahead of the code checkpoint; always validate/install the final current branch HEAD with its own exact-SHA workflow run.
- no physical UX validation yet for this redesign.

## Product roles

### Apple Watch

Capture + immediate control + glanceable live feedback.

- start/select activity;
- pause/resume/stop;
- multisport transition controls when relevant;
- 2–4 high-value metrics per page;
- route/terrain where useful;
- recent activity shortcut only;
- no advanced configuration matrix.

### iPhone

Plan + supervise + understand + configure.

- Today dashboard;
- activity launcher/live session;
- Progression / health trends;
- full History;
- detailed post-session analysis;
- advanced activity, Auto and auto-pause settings;
- data provenance/quality/technical trace as drill-down.

## iPhone information architecture

Primary navigation:

1. **Aujourd’hui** — default entry point.
2. **Activité** — start/supervise current workout; map belongs here.
3. **Progression** — 7/28-day trends enriched from user-authorized HealthKit data.
4. **Historique** — durable session timeline, filters and detailed sessions.

Profile/settings belong in the top-right profile affordance, not History.

## Today

Purpose: answer “where am I today?” before exposing detail.

Priority order:

1. current workout / ready-to-start hero;
2. Watch, GPS and Health readiness;
3. strong CTA to Activity;
4. recent weekly activity summary;
5. last activity;
6. later: compact HealthKit-informed sleep/recovery/cardio insights when data and permission are actually available.

Never fabricate missing HealthKit values. Missing/unauthorized data is shown as unavailable/insufficient, never zero.

## Activity

### Idle

- chosen activity or Auto;
- recent/preferred sports before the full Apple activity catalog;
- Watch/GPS/Health readiness;
- large Start control;
- auto-pause summary, with advanced configuration on iPhone settings.

### Live

Implemented direction:

- activity + state + elapsed time;
- 3–4 primary metrics;
- segmented content: Summary / Map / Details;
- Pause/Resume + Finish always easy to reach;
- technical acquisition/status text secondary.

Map rules:

- not the app home screen;
- location control always has deterministic behavior;
- first location action recenters/follows the current user position;
- current implementation explicitly frames `TrackerModel.currentCoordinate` at about 600 m and falls back to MapKit user-location mode until a coordinate is available;
- user map interaction exits follow mode;
- current route framing and history route framing are separate concepts.

## History

History is a first-class destination, not a modal shortcut.

### List

Implemented first pass:

- period summary for 7 days / 30 days / all history;
- chronological activity list;
- activity type + date + distance + duration + energy where available.

Remaining:

- search;
- sport filter;
- Auto/manual filter;
- richer calendar presentation if it improves real-device usability.

### Activity detail

Current hierarchy:

1. activity/date header;
2. hero metrics;
3. route;
4. effort / HR / pace-speed;
5. elevation;
6. segments and pauses;
7. environment/weather;
8. later: comparisons with similar personal sessions;
9. data quality/provenance;
10. technical trace/build metadata collapsed/de-emphasized at the bottom.

## Progression / health dashboard

The dashboard combines Watch Tracker history with user-authorized HealthKit history while keeping provenance explicit.

Second checkpoint implements:

- Watch Tracker activity load: recent duration, distance and count, compared with the previous three-week personal reference when available;
- today HealthKit totals for steps, Apple Exercise Time and active energy;
- latest resting heart rate with 28-day personal mean;
- latest HRV SDNN with 28-day personal mean;
- recent sleep duration from asleep-stage samples, merging overlaps rather than double-counting them;
- latest VO2 max when available;
- 14-day resting-HR and HRV trend charts;
- source name for latest quantity samples when HealthKit exposes it;
- explicit missing-data behavior: absent/non-shared values render unavailable, never zero;
- no opaque health/readiness score and no diagnostic claim.

Later target groups:

- workout HR / recovery metrics;
- mobility: walking pace, step length, asymmetry, double support and related available metrics;
- personal performance: comparable pace/speed/HR/cadence/elevation trends;
- environment-vs-effort insights from Watch Tracker weather context;
- optional explainable Charge / Recovery / Balance concepts only after inputs and missing-data behavior are validated.

## Apple Watch redesign

### Ready screen

Implemented first pass:

- selected activity / Auto;
- compact readiness;
- large Start;
- quick activity selector;
- recent-history shortcut only where space remains useful;
- advanced auto-pause settings and long explanatory copy removed from Watch ready UI.

### Active pages

Target/implemented hierarchy is kept to four top-level concepts:

1. **Principal** — elapsed, distance, HR, current pace/speed + state.
2. **Effort** — HR/zone, calories, cadence/steps.
3. **Terrain / route** — route, altitude, ascent/descent, GPS quality where relevant.
4. **Controls** — pause/resume, transition when relevant, finish.

Auto classification confidence/provenance remains available but must not compete with primary workout metrics. Deeper provenance belongs on iPhone/post-session.

## Shared interaction contract

- Watch remains authoritative for workout state.
- iPhone and Watch use the same activity names, state vocabulary and symbols.
- configuration values edited on iPhone must converge to Watch before/start of workout.
- deletion/history synchronization must converge across devices when implemented.
- no phone-only and Watch-only versions of the same setting unless platform constraints require it.

## Implementation slices

### UX-1 — navigation foundation

Implemented and CI-validated at `41cfe677...`:

- Today becomes iPhone entry point;
- Activity, Progression and History become first-class destinations;
- map no longer owns the root screen.

### UX-2 — Activity live hierarchy

Implemented in second checkpoint, CI pending:

- Summary / Map / Details presentation;
- horizontal metric-card overload removed from the new live surface;
- sport-relevant pace/speed selection;
- controls always available;
- deterministic explicit map recenter behavior.

### UX-3 — Watch simplification

Implemented and CI-validated at `41cfe677...`:

- remove advanced auto-pause settings from Ready screen;
- remove long instructional copy from Watch;
- increase primary metric sizing;
- compact Auto presentation;
- simplify page hierarchy.

### UX-4 — History redesign

First pass implemented and CI-validated at `41cfe677...`:

- summary header + richer list;
- detail information hierarchy;
- technical trace collapsed/de-emphasized.

Search/filters and comparison entry points remain.

### UX-5 — HealthKit trends

First functional pass implemented in second checkpoint, CI pending:

- additional read types requested only when Progression becomes relevant;
- historical queries with source/missing-data states;
- activity-load context;
- resting HR, HRV, sleep, VO2 max, steps, active energy, exercise time;
- 14-day trend charts and 28-day personal baselines.

Today health cards and deeper mobility/performance insights remain.

## Validation

UI builds and CI are not physical UX validation. After each substantial slice, validate on real iPhone/Watch for tap targets, text sizing, safe areas, Digital Crown/page behavior, HealthKit permission behavior, map recenter, state synchronization and legibility during motion.
