# Watch Tracker — UI/UX redesign plan

Date: 2026-09-10

## Goal

Turn the current feature-rich tracker into one coherent iPhone + Apple Watch product. Preserve the existing technical architecture: Apple Watch remains the single live-workout authority; iPhone is the richer configuration, supervision, history and analysis surface.

This redesign must not remove diagnostics or provenance. It moves them deeper in the information hierarchy so normal users see useful activity/health information first.

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
3. **Progression** — 7/28-day trends, later enriched from HealthKit.
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
6. later: HealthKit-informed sleep/recovery/cardio insights when data and permission are actually available.

Never fabricate missing HealthKit values. Missing/unauthorized data is shown as unavailable/insufficient, never zero.

## Activity

### Idle

- chosen activity or Auto;
- recent/preferred sports before the full Apple activity catalog;
- Watch/GPS/Health readiness;
- large Start control;
- auto-pause summary, with advanced configuration on iPhone settings.

### Live

Information hierarchy:

- activity + state + elapsed time;
- 3–4 primary metrics;
- segmented content: Summary / Map / Details;
- Pause/Resume + Finish always easy to reach;
- technical acquisition/status text secondary.

Map rules:

- not the app home screen;
- location control always has deterministic behavior;
- first location action recenters/follows the current user position;
- user map interaction exits follow mode;
- current route framing and history route framing are separate concepts.

## History

History is a first-class destination, not a modal shortcut.

### List

- weekly/monthly summary header;
- chronological activity list;
- activity type + date + distance + duration + energy where available;
- later: search, period filter, sport filter, Auto/manual filter.

### Activity detail

Order:

1. activity/date header;
2. hero metrics;
3. route;
4. effort / HR / pace-speed;
5. elevation;
6. segments and pauses;
7. environment/weather;
8. comparisons with similar personal sessions;
9. data quality/provenance;
10. technical trace/build metadata at the bottom.

## Progression / health dashboard

The dashboard should combine Watch Tracker history with user-authorized HealthKit history, while keeping provenance explicit.

Target groups:

- activity volume: workouts, active time, distance, elevation, sport mix;
- cardio: resting HR, workout HR, HRV where readable, recovery metrics where available;
- sleep/recovery context where HealthKit provides data;
- mobility: walking pace, step length, asymmetry, double support and related available metrics;
- personal performance: comparable pace/speed/HR/cadence/elevation trends;
- environment-vs-effort insights from Watch Tracker weather context.

Potential product concepts:

- **Charge** — recent training/activity volume and intensity relative to personal baseline;
- **Récupération** — transparent contextual indicator using available personal baseline data, never medical diagnosis;
- **Équilibre** — recent load vs personal normal range.

No opaque score should ship until its inputs, missing-data behavior and explanation are defined and validated.

## Apple Watch redesign

### Ready screen

Keep only:

- selected activity / Auto;
- compact readiness;
- large Start;
- optional quick activity selector;
- recent history shortcut only if space remains useful.

Move advanced auto-pause settings and explanatory paragraphs to iPhone.

### Active pages

Target maximum four top-level pages:

1. **Principal** — elapsed, distance, HR, current pace/speed + state.
2. **Effort** — HR/zone, calories, cadence/steps.
3. **Terrain / route** — route, altitude, ascent/descent, GPS quality where relevant.
4. **Controls** — pause/resume, transition when relevant, finish.

Auto classification confidence/provenance remains available but should not compete with the primary workout metrics. Prefer a compact Auto state and expose deeper provenance on iPhone/post-session.

## Shared interaction contract

- Watch remains authoritative for workout state.
- iPhone and Watch use the same activity names, state vocabulary and symbols.
- configuration values edited on iPhone must converge to Watch before/start of workout.
- deletion/history synchronization must converge across devices when implemented.
- no phone-only and Watch-only versions of the same setting unless platform constraints require it.

## Implementation slices

### UX-1 — navigation foundation

- Today becomes iPhone entry point;
- Activity, Progression and History become first-class destinations;
- map no longer owns the root screen;
- deterministic map recenter/follow behavior.

### UX-2 — Activity live hierarchy

- Summary / Map / Details presentation;
- reduce horizontal metric-card overload;
- promote sport-relevant metrics;
- preserve controls and acquisition state.

### UX-3 — Watch simplification

- remove advanced auto-pause settings from Ready screen;
- remove long instructional copy from Watch;
- increase primary metric sizing;
- compact Auto confidence/provenance;
- simplify page hierarchy.

### UX-4 — History redesign

- summary header + richer list;
- detail information hierarchy;
- technical trace collapsed/de-emphasized;
- filters/search and comparison entry points.

### UX-5 — HealthKit trends

- explicit read types and permission UX;
- historical queries with provenance/missing-data states;
- Today health cards;
- Progression cardio/sleep/mobility sections;
- baseline calculations and explainable insights.

## Validation

UI builds and CI are not physical UX validation. After each substantial slice, validate on real iPhone/Watch for tap targets, text sizing, safe areas, Digital Crown/page behavior, map recenter, state synchronization and legibility during motion.
