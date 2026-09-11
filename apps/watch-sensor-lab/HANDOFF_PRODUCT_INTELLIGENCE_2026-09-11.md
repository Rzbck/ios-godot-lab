# HANDOFF — Product intelligence / wellness / multi-source load

Date: 2026-09-11

## Objective

Continue Watch Sensor Lab as a premium, compact, depth-first sports/wellness app while preserving the already-established Watch workout authority and recorder semantics.

Current product priorities:
- Today first;
- tap-to-depth on iPhone and Watch;
- compact Watch hierarchy rather than free-form long scrolling;
- all accessible Apple Health workout history for progression/volume;
- transparent recovery/sleep/cardio intelligence with personal baselines and confidence;
- explicit provenance for Apple / Tracker / user-entered effort;
- multi-source training-load context without presenting ratios as medical or injury predictions;
- maps/terrain and sport-aware live UI;
- no opaque or fabricated health values.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- active branch: `feat/watch-sensor-product-shell-maps-20260910`
- exact latest build-producing code SHA: `a741407f7255ec345049eef95e1a8fab626a9f33`
- parent tooling/storage-policy commits:
  - `244d53c713efd32658673167eef8021710c35488` — candidate-only GitHub artifacts
  - `b76e0651dce7baad2a5d68ffdc3862be7d3a6bc7` — updater resolves only retained device artifacts
- this HANDOFF is a docs-only commit after `a741407f...`; on resume, verify actual branch HEAD and prove build inputs are unchanged before reusing the CI checkpoint.

## Latest CI checkpoint

- workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`
- build SHA: `a741407f7255ec345049eef95e1a8fab626a9f33`
- run: `34565274225`
- job: `103156024000`
- conclusion: **SUCCESS**
- iPhone build: SUCCESS
- watchOS build: SUCCESS
- HealthKit declaration checks: SUCCESS
- combined iPhone + embedded Watch assembly: SUCCESS
- exact-SHA packaging: SUCCESS
- device artifact upload: **SKIPPED by design**
- workflow artifacts for this run: **0**
- hardware validation: **NOT performed**

Do not describe this checkpoint as installed or physically validated.

## GitHub Actions storage policy

Problem observed 2026-09-11:
- 50 Watch Sensor Lab artifacts consumed about 255.42 MB;
- user cleaned 44 redundant artifacts;
- 6 important checkpoints remain, about 12.25 MB total.

Current policy:
- normal build-relevant push still runs full iPhone + Watch CI;
- normal push does **not** upload an artifact;
- an artifact is uploaded only for a deliberate device candidate (`[device-artifact]`) or manual `workflow_dispatch`;
- candidate artifact retention: 2 days;
- Watch diagnostic ZIP is not retained as a separate artifact;
- docs/HANDOFF/tooling-only changes do not trigger app CI;
- branch-scoped `cancel-in-progress` keeps only the newest relevant build running.

The policy was physically verified at the GitHub Actions level:
- run `34564308303` on `244d53c7...` succeeded with upload skipped and 0 artifacts;
- run `34565274225` on `a741407f...` also succeeded with upload skipped and 0 artifacts.

`UPDATE_WATCH_SENSOR_LAB.ps1` distinguishes branch HEAD from BUILD SHA and searches for an actual retained artifact. If no compatible artifact exists and auto-build is permitted, it can dispatch a deliberate device build. Never silently treat a green no-artifact CI run as an installable IPA.

## Product intelligence implemented

### Recovery / sleep

`TrackerRecoveryIntelligence.swift`:
- personal-baseline recovery intelligence;
- sleep duration, bedtime consistency and continuity;
- HRV, resting HR, respiratory rate and sleeping wrist temperature context;
- recent 7-day workout-volume pressure versus previous reference window;
- confidence/coverage is explicit;
- missing factors reduce confidence instead of becoming zero;
- no injury prediction or medical diagnosis.

`TrackerNightVitals.swift`:
- finds latest sufficiently documented sleep window;
- reads median overnight HR, HRV, respiratory rate, wrist temperature and oxygen saturation when accessible;
- stores source and sample count for each signal;
- labels values as context, not diagnosis.

Current Apple 2026 research note:
- Apple now has an official Sleep Score 0–100 using duration (50 points), bedtime consistency (30) and interruptions (20), with 13-night consistency history;
- Tracker must not market its recovery intelligence as a clone of Apple Sleep Score;
- future refinement should keep recovery multi-signal (sleep + vitals + training context + personal baselines) with visible factors and confidence.

### Physiology / cardio

`TrackerPhysiologyProfile.swift`:
- age from Health date of birth;
- body mass;
- height;
- VO2 max;
- one-minute heart-rate recovery;
- adult age-based HRmax estimate only as a fallback (`208 - 0.7 * age`), never as a guaranteed personal max;
- provenance and freshness retained.

`TrackerCardioFitnessLab.swift`:
- VO2 max / HR recovery / resting HR / weight trends;
- long-range chart periods and source/date context.

Heart-rate reference hierarchy remains:
1. configured/personal HRmax;
2. adult age estimate when appropriate;
3. workout peak only as last-resort context.

### Effort provenance

`AppleWorkoutEffortReader.swift` + `TrackerEffortInsight.swift` separate:
- Apple perceived workout effort;
- Apple estimated workout effort;
- Tracker local estimated effort;
- user-entered perceived effort 1–10.

These values must never overwrite each other silently.

### iPhone Recovery Lab

`ProgressionEntryView.swift` now exposes:
- Volume récent;
- Charge multi-source;
- Récupération lab.

Recovery lab contains:
- Tracker Recovery Intelligence;
- Vitals Nuit;
- Cardio Fitness;
- Physiological Profile.

### Watch wellness sync

`PhoneRecentHistoryBridge.swift` now attaches a compact wellness digest to the existing recent-history v6 transfer instead of creating a competing WatchConnectivity channel.

Digest includes when available:
- recovery score + confidence + label;
- sleep duration + efficiency + 7-day deficit;
- workload ratio context;
- night HR;
- night HRV;
- night respiratory rate;
- wrist temperature;
- oxygen saturation;
- VO2 max;
- 1-minute HR recovery.

`WatchRecentHistory.swift` persists the optional wellness payload while remaining backward-compatible with older v6/v5/v4 history caches.

`WatchStatusDepthView.swift` top-level Status depth now has vertical pages:
1. Devices;
2. Health/GPS sensors;
3. Recovery;
4. Cardio / Night;
5. Load.

This keeps the global Watch UI horizontal by major function while using vertical/Crown depth inside Status.

### Multi-source training load

`TrainingLoadIntelligenceView.swift` added at build SHA `a741407f...`.

It intentionally avoids one opaque combined score and presents four independent axes:
1. all-accessible Apple Health workout volume: recent 7 days vs weekly average of previous 28 days;
2. session-RPE internal load for Tracker sessions where the user explicitly entered perceived effort, calculated as active minutes × RPE;
3. Tracker estimated effort trend for local Tracker sessions;
4. current Tracker Recovery context.

Additional behavior:
- sport filter;
- daily recent-volume chart;
- sRPE daily chart when coverage exists;
- Tracker effort trend;
- per-session provenance;
- explicit RPE coverage;
- missing RPE is never substituted by Tracker estimation;
- volume ratio is descriptive context only;
- no ACWR-based injury prediction.

Research basis:
- Apple training load compares workout intensity + duration over the recent 7 days with the previous 28 days;
- session-RPE has broad validation as an internal training-load monitoring method;
- literature identifies major conceptual/methodological problems with using acute:chronic workload ratios as causal injury predictors, so Watch Tracker must not make that claim.

## Existing UI/product work preserved

Still present from earlier product-shell work:
- Today Command Center;
- Today-first progression;
- current-vs-previous graphs;
- Health + Tracker history;
- compact Watch Start / Progression / Recent / Status navigation;
- Watch active horizontal pages with metric depth;
- iPhone active Summary / Cardio / Map / Terrain / Conditions;
- MapKit Plan / Hybrid / Satellite;
- elevation profile and slope analysis;
- estimated effort + perceived effort;
- exact Watch workout authority path.

## What is NOT yet physically validated

- new Today Command Center;
- Recovery Lab;
- night vitals display;
- physiology/cardio lab;
- multi-source training load;
- wellness digest arriving/persisting/rendering on a real Watch;
- Watch Recovery/Cardio status pages fitting all real Watch sizes;
- active Watch four-page redesign;
- active iPhone sport-aware shell;
- map/terrain presentation;
- current effort UI;
- new workout type/source icon in Apple Fitness/Forme;
- current combined build on physical iPhone/Watch.

## Next work that does not require hardware first

1. Refine Tracker Recovery so it is clearly differentiated from Apple Sleep Score 2026 and uses multi-signal personal-baseline logic rather than looking like a sleep-score clone.
2. Build a Daily Brief / Today insight layer with factor-level explanations and minimum-data confidence gates.
3. Add correlation lab only with sufficient sample count (sleep / recovery / load / performance), showing sample size and avoiding causal claims.
4. Extend multi-source load with Apple effort coverage across accessible Health workouts where this can be queried efficiently and transparently.
5. Continue sport-specific cards and map/terrain source research.

Do not alter active workout authority/recorder semantics during these analytical UI tasks.

## Next deliberate device candidate

Do not create an artifact for every commit.

When the analytical tranche is mature enough for real-device inspection:
- mark one exact code commit with `[device-artifact]` or dispatch a manual device build;
- verify build SHA and artifact metadata;
- use `UPDATE_WATCH_SENSOR_LAB.ps1` from the correct dedicated worktree;
- install with the already-validated iLoader workflow;
- test iPhone first, then Watch idle/depth, then a short real WALK, then active screens and Fitness/Forme source/type/icon.

No merge to main, release, or promotion without explicit user approval.
