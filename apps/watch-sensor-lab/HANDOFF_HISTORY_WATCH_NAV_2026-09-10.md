# HANDOFF — Health history + Watch paged navigation

Date: 2026-09-10

## Objective

Fix three physical UX observations after installing the product UX checkpoint:

1. Watch showed `Aucune activité synchronisée` while iPhone still had Tracker history.
2. Watch home relied on a long vertical ScrollView; user wants compact purposeful pages, with horizontal swipes for main functions and Crown/page navigation for deeper history.
3. iPhone History showed only Watch Tracker local sessions instead of all user-authorized workouts already present in Apple Health.

Do not change the active-workout UI/behavior yet: the user has not physically tested the active workout screens in this checkpoint.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- branch: `feat/watch-sensor-history-watch-nav-20260910`
- branch base: `d2e9da6958d7754d310a5f2b1d366ca551d318ba`
- physically installed code checkpoint before this chantier: `fa28758bda549deaddbbc12c24eb869d0965af4b`
- previous CI run: `34507870711` SUCCESS for `fa28758...`
- previous exact IPA SHA-256: `3f782f0a6c6845d6a28af65610116e0826c99c1408a7a1eca81d0da41e987e62`
- verify current branch HEAD before continuation.

## Physical observations that triggered this branch

- iPhone upgraded and opened successfully.
- iPhone retained local Watch Tracker history.
- Watch recent activities page displayed no synchronized activities even though iPhone had history.
- user wants no long downward-scrolling Watch home; prefers compact page-based navigation and left/right swipes for functions.
- iPhone startup Health permissions did not cover all later-used HealthKit metrics.
- iPhone History exposed only app-local sessions, not the broader Apple Health workout history.
- active workout UI has NOT yet been physically tested; preserve it until that test.

## Changes on this branch

### iPhone Health workout history

Added `iphone/Sources/HealthWorkoutHistory.swift`.

- Queries `HKObjectType.workoutType()` using `HKSampleQuery` with no workout-source restriction.
- Shows all workouts HealthKit makes readable to the app, regardless of which app recorded them.
- Maps `HKWorkoutActivityType` back to the existing `ActivityKind` catalogue.
- Shows source app, date, duration, distance and active energy where HealthKit provides them.
- History tab now defaults to `Santé`; a `Tracker` source keeps the existing rich local Tracker history/details intact.
- No Health workout is imported into or rewritten inside `NativeSessionStore`.
- Missing Health history is not interpreted as zero or proof of denial; HealthKit read privacy semantics are respected.

### Complete startup permission pass

Added `iphone/Sources/StartupPermissionCoordinator.swift`.

- Full current app-used HealthKit read set is requested before `TrackerModel` is initialized, avoiding the old partial-first Health sheet.
- Current read set includes workouts, heart rate, active energy, walking/running/cycling/swimming distance, resting HR, HRV SDNN, VO2 max, steps, exercise time, sleep, walking mobility metrics, running dynamics, heart-rate recovery and respiratory context.
- After Health completes, location permission is requested if needed.
- Motion/Fitness permission is then probed through `CMPedometer` if still not determined.
- `NSHealthShareUsageDescription` was updated to accurately describe workout/history/cardio/sleep/mobility use.

### Unified recent-history bridge

Updated `PhoneRecentHistoryBridge.swift`.

- Builds a unified feed from local Tracker summaries plus readable Health workouts.
- Deduplicates a Health workout when its Tracker session metadata matches an existing local session.
- Sends up to 16 recent activities plus 7-day and 28-day aggregate stats to Watch using `tracker_recent_history_v5`.
- Delivery now retries for a bounded period if `WCSession` is not yet activated instead of silently dropping the publication.
- History is re-published when Watch reachability returns and after a completed Tracker session.

### Watch home/navigation

Updated `WatchSensorLabApp.swift`.

Idle Watch home no longer uses the previous long `ScrollView`.

Top-level idle navigation is horizontal page-based:

1. Start — activity selector, readiness, auto-pause, Start.
2. Progression — compact 7-day activity count/time/distance and comparison against 28-day weekly reference.
3. Recent — latest synchronized activity plus entry to history.

Active workout remains the existing four vertical pages and was intentionally not changed.

### Watch recent history

Updated `WatchRecentHistory.swift`.

- Supports new v5 history envelope plus legacy v4 fallback.
- Persists activities and 7/28-day stats on Watch.
- Replaces continuous ScrollView history with one fixed activity card per vertical page.
- Digital Crown/vertical-page behavior remains available for navigating activity pages.

## Validation state

- NOT CI validated yet.
- NOT physically validated yet.
- Active workout behavior was not modified on this branch.

## Required next validation

1. Run `watch-sensor-lab-bootstrap.yml` manually on the exact final branch HEAD.
2. If CI succeeds, download exact-SHA IPA with existing `UPDATE_WATCH_SENSOR_LAB.ps1` from a dedicated local worktree for this branch.
3. Upgrade in place through the already validated auth-fixed iLoader; do not uninstall/purge.
4. On iPhone, accept the consolidated startup permissions and verify History -> Santé contains workouts recorded outside Watch Tracker.
5. On Watch, verify horizontal idle pages fit without downward content scrolling.
6. Verify recent history arrives from the iPhone and Progression is populated.
7. Only after that, separately test the existing active-workout pages and report physical UX issues before modifying them.

## Do not modify

- do not merge to main without explicit user approval;
- do not modify iLoader/isideload in this UX/history branch;
- do not purge local Tracker history or Apple Health history;
- do not import external Health workouts into NativeSessionStore;
- do not change Watch workout authority/sync revisions or active tracking until the pending physical active-workout test is observed.
