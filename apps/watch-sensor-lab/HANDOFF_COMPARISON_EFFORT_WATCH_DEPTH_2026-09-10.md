# HANDOFF — Today-first comparison, effort, Watch depth

Date: 2026-09-10

## Objective

Continue the Watch Tracker product/UX refinement from the physically observed visual-analytics build without modifying the active tracking engine.

User feedback driving this tranche:

- Progression must open with **Today** first; 7 days/month/year are secondary time ranges.
- period comparison should be visual on the same chart (current vs previous) so ahead/behind is immediately readable, rather than only textual percentages;
- important metric cards/icons should be tappable and open a clean detailed view;
- Watch horizontal pages are useful, but some pages should also have vertical depth for more information without returning to one long ScrollView;
- Watch Progression should not be limited to one 7-day summary; it should include Today, 7-day comparison and a 28-day mini graph;
- add perceived effort and an automatic estimated effort using recorded physiological/session/environmental context where available;
- an older activity shown in Apple Fitness/Forme did not display as walking and appeared with a white/blank source icon; verify this on a newly recorded workout before changing icon assets.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-comparison-effort-watch-depth-20260910`
- exact branch base: `9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- base CI run: `34515836355` SUCCESS
- base artifact: `watch-sensor-lab-companion-9f85583ce9c0fcfccbf1879f5b93c62a16b61b2e`
- implementation HEAD before this handoff commit: `1264b38535b6c01990e3077bc92c1420f9d01859`
- verify exact branch HEAD before continuation or CI.

## Changes

### iPhone Progression — Today first

Added `iphone/Sources/PerformanceProgressionTodayView.swift` and routed `ProgressionEntryView` to it.

Primary order:

1. Today hero
2. tappable Today metric cards
3. periods: Today / 7 j / 1 month / 6 months / 1 year / All
4. current-vs-previous cumulative comparison chart
5. today's workout drill-down
6. sport distribution
7. tappable Health/recovery cards

The activity dataset still comes from all readable Apple Health workouts, not only local Tracker sessions.

For bounded periods, the comparison chart overlays cumulative current and previous-period lines at equivalent progress through the period. Metric selector supports active time, distance and sessions.

Today cards and Health cards are NavigationLinks to dedicated details. Today workouts can also open a detailed view; when the Health workout maps back to a retained Tracker session, the detailed Tracker effort card is available.

### Effort

Added `iphone/Sources/TrackerEffortInsight.swift`.

It provides:

- an explicit Watch Tracker **estimated effort** on a 1–10 scale;
- uses recorded heart-rate zones when available, duration, continuity/pauses, elevation and available weather/headwind context;
- the score is labeled as an estimate/reference and not a medical measurement;
- separate **user perceived effort 1–10** stored per Tracker session in UserDefaults;
- perceived effort is deliberately not overwritten by the automatic estimate.

`PostActivitySummaryView` now displays this effort block immediately after the main metrics.

### iPhone -> Watch progression payload

`PhoneRecentHistoryBridge` now sends `tracker_recent_history_v6` containing:

- recent activities (up to 16 as before);
- Today aggregate;
- 7-day aggregate;
- 28-day aggregate;
- 28 fixed daily buckets for compact Watch trend rendering.

Delivery still uses the bounded WatchConnectivity activation retry added previously.

### Watch progression depth

`WatchRecentHistoryStore` now ingests/persists v6 while retaining v5/v4 fallback loading.

Added `watch/Sources/WatchProgressionDepthView.swift`.

The horizontal top-level Watch structure remains Start / Progression / Recent. The Progression horizontal page now contains a **vertical page stack**:

1. Today — active time, sessions, distance;
2. 7 days — paired daily bars, current vs previous 7 days, plus totals;
3. 28 days — four weekly bars plus totals.

This is intentional two-axis navigation: left/right for app sections, up/down (or crown/page gesture where watchOS applies it) for depth inside Progression. No long free-form ScrollView was introduced.

### Active workout preservation

No intentional change to SensorModel tracking, HealthKit workout session control, auto classifier, pause/resume, authority/revision rules, route collection or active-workout metric pages.

The active-workout UX still needs its separate physical test before redesign.

## Apple Fitness / activity type / app icon open point

Current Watch HealthKit code starts Auto using the current `effectiveActivity` configuration. During an Auto workout the classifier may change `effectiveActivity`, while the initially created HealthKit workout semantics are preserved and the final detected activity is recorded as metadata. A workout already saved to HealthKit is not retroactively relabeled merely by the local post-activity review.

The repository already contains a non-white generated app icon source and both iPhone/watch targets declare `AppIcon.png`. Do not change icon assets based only on the older Fitness entry. Physically record one new workout with the current candidate and verify:

- workout type shown by Apple Fitness/Forme;
- source app name;
- source icon rendering.

If the new workout still shows a blank/white icon, investigate the packaged/signing/source-revision icon path separately.

## Validation state

- NOT CI validated yet for this branch.
- NOT physically validated yet for this tranche.
- base `9f85583...` is the latest known successful CI visual-analytics checkpoint referenced by this work.
- do not claim the new Today/comparison/effort/Watch-depth UX works on hardware until exact-SHA install and observation.

## Required next validation

1. trigger existing `watch-sensor-lab-bootstrap.yml` on the exact final HEAD;
2. fix only concrete CI errors if any;
3. use existing `UPDATE_WATCH_SENSOR_LAB.ps1` in a dedicated worktree to retrieve the exact-SHA IPA;
4. install in place with auth-fixed iLoader, no purge;
5. iPhone: Progression opens Today first; tappable cards drill down; period comparison shows two curves;
6. Watch: horizontal Start/Progression/Recent still works; inside Progression vertical Today/7d/28d pages work and fit;
7. finish a short Tracker session and verify estimated effort + perceived effort selector;
8. verify new workout type and source icon in Apple Fitness/Forme;
9. only after this, perform the still-pending active-workout UX test.

## Do not modify

- no merge to main without explicit user approval;
- no iLoader/isideload changes in this tranche;
- no data purge or history rewrite;
- no HealthKit workout replacement/deletion flow without separate design and validation;
- no active-workout redesign until physically observed.
