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
- personal discoveries only after enough observations, with sample size and non-causal wording;
- maps/terrain and sport-aware live UI;
- no opaque or fabricated health values.

## Repository / branch

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- active branch: `feat/watch-sensor-product-shell-maps-20260910`
- exact latest build-producing code SHA: `61689574162c063f845c7c75c14ac1ce95236406`
- latest docs-only branch HEAD before this HANDOFF update: `ab0f66635b552c7510b8c4ddc3d96d81411aa94f`
- parent tooling/storage-policy commits:
  - `244d53c713efd32658673167eef8021710c35488` — candidate-only GitHub artifacts
  - `b76e0651dce7baad2a5d68ffdc3862be7d3a6bc7` — updater resolves only retained device artifacts

This HANDOFF update is docs-only. On resume, verify actual branch HEAD and use Git diff/build-input equivalence before reusing the build checkpoint.

## Latest CI checkpoint

- workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`
- build SHA: `61689574162c063f845c7c75c14ac1ce95236406`
- run: `34566090256`
- job: `103158434696`
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

Verified behavior:
- run `34564308303` on `244d53c7...`: SUCCESS, upload skipped, 0 artifacts;
- run `34565274225` on `a741407f...`: SUCCESS, upload skipped, 0 artifacts;
- run `34566090256` on `61689574...`: SUCCESS, upload skipped, 0 artifacts.

`UPDATE_WATCH_SENSOR_LAB.ps1` distinguishes branch HEAD from BUILD SHA and searches for an actual retained artifact. If no compatible artifact exists and auto-build is permitted, it can dispatch a deliberate device build. Never silently treat a green no-artifact CI run as an installable IPA.

## Product intelligence implemented

### Today Command Center + Daily Brief

`TodayCommandCenterView.swift` remains the Today entry surface and now places `TrackerDailyBriefCard()` directly under the Today hero.

`TrackerDailyBrief.swift`:
- short Today headline based on readable personal signals;
- factor-level cards for recovery, sleep, workload context, HRV and resting HR when available;
- comparison to personal recent baseline where available;
- explicit confidence and provenance;
- missing values remain missing;
- detail view explains why the brief reached its wording;
- no causal or medical language.

Today hierarchy is now:
1. Today/activity hero;
2. Daily Brief;
3. Tracker Recovery;
4. Today movement;
5. current-vs-previous 7-day trajectory;
6. Cardio Lab;
7. recent workouts;
8. Health signals;
9. progression/history actions.

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

`TrackerSleepLabView.swift`:
- latest night duration versus personal sleep baseline;
- sleep-window continuity;
- interruptions;
- bedtime regularity;
- accumulated 7-day sleep shortfall versus personal baseline;
- Core / Deep / REM breakdown when available;
- 14-night duration trend with personal baseline;
- embeds Vitals Nuit;
- explicitly explains why Tracker does not create a second Apple Sleep Score.

Apple 2026 research note:
- Apple provides an official Sleep Score in current OS/product behavior;
- Apple DTS states there is currently no public HealthKit API to read Apple Sleep Score;
- Tracker therefore must not market its own Recovery/Sleep analysis as Apple Sleep Score or silently recreate it;
- Tracker Recovery stays multi-signal: sleep + personal baselines + HRV/RHR + night vitals + training context + confidence.

### Physiology / cardio

`TrackerPhysiologyProfile.swift`:
- age from Health date of birth;
- body mass;
- height;
- VO2 max;
- one-minute heart-rate recovery;
- adult age-based HRmax estimate only as fallback (`208 - 0.7 * age`), never as guaranteed personal max;
- provenance and freshness retained.

`TrackerCardioFitnessLab.swift`:
- VO2 max / HR recovery / resting HR / weight trends;
- long-range chart periods and source/date context.

Heart-rate reference hierarchy:
1. configured/personal HRmax;
2. adult age estimate when appropriate;
3. workout peak only as last-resort context.

Age/weight are contextual inputs only. They do not directly penalize Recovery. Apple VO2 max is already relative to body mass (`mL/kg/min`) and must not be reweighted by body mass again.

### Effort provenance

`AppleWorkoutEffortReader.swift` + `TrackerEffortInsight.swift` separate:
- Apple perceived workout effort;
- Apple estimated workout effort;
- Tracker local estimated effort;
- user-entered perceived effort 1–10.

These values never overwrite one another silently.

### Multi-source training load

`TrainingLoadIntelligenceView.swift` presents four independent axes rather than one opaque combined number:
1. all-accessible Apple Health workout volume: recent 7 days vs weekly average of previous 28 days;
2. session-RPE internal load for Tracker sessions where user explicitly entered perceived effort, calculated as active minutes × RPE;
3. Tracker estimated effort trend for local Tracker sessions;
4. current Tracker Recovery context.

Behavior:
- sport filter;
- recent daily-volume chart;
- sRPE daily chart when coverage exists;
- Tracker effort trend;
- per-session provenance;
- explicit RPE coverage;
- missing RPE is never substituted by Tracker estimation;
- volume ratio is descriptive context only;
- no ACWR-based injury prediction.

### Correlation Lab

`TrackerCorrelationLab.swift` implements guarded personal associations:
- sleep duration vs next-day HRV;
- sleep duration vs next-day resting HR;
- previous-day workout minutes vs following sleep duration.

Rules:
- raw pair count `n` is visible;
- minimum 10 paired observations before relationship wording;
- Pearson `r` shown as an association coefficient;
- no cause/effect language;
- no diagnostic interpretation;
- first version uses the recent Recovery sleep history and should later expand to 30/60/90-day histories after UX validation.

### Local behavior / experiment journal

`TrackerBehaviorJournal.swift` collects local explicit tags such as:
- late caffeine;
- alcohol;
- late meal;
- late screen;
- meditation/breathing;
- sauna/heat;
- mobility/stretching;
- good hydration;
- nap;
- perceived high stress;
- travel;
- feeling sick.

Rules:
- local storage only in current implementation;
- optional short note;
- tags do not write to Apple Health;
- tags do not modify Recovery or training-load scores;
- collect first, analyze later;
- future behavior-impact analysis must require sufficient observations in both yes/no groups and display sample sizes.

Benchmark guardrails:
- WHOOP requires repeated yes/no entries before behavior impacts;
- Oura requires meaningful recent baseline coverage for Discoveries;
- Tracker follows the same conservative philosophy rather than showing instant pseudo-insights.

### iPhone Recovery Lab

`ProgressionEntryView.swift` now exposes:
- Volume récent;
- Charge multi-source;
- Récupération lab.

Recovery lab contains:
- Tracker Recovery Intelligence;
- Daily Brief;
- Sleep Lab;
- Correlation Lab;
- Behavior Journal;
- Vitals Nuit;
- Cardio Fitness;
- Physiological Profile.

### Watch wellness sync

`PhoneRecentHistoryBridge.swift` attaches a compact wellness digest to the existing recent-history v6 transfer rather than creating a competing WatchConnectivity channel.

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

`WatchStatusDepthView.swift` Status depth vertical pages:
1. Devices;
2. Health/GPS sensors;
3. Recovery;
4. Cardio / Night;
5. Load.

Global Watch major-function navigation remains horizontal; Status uses vertical/Crown depth.

## External benchmark / current research

Research file:
`apps/watch-sensor-lab/RESEARCH_PRODUCT_BENCHMARK_2026-09-11.md`

It records current Apple / Garmin / Strava / WHOOP / Oura product patterns, scientific/product guardrails, and future modules.

Important retained conclusions:
- do not create a fake cardiovascular-age feature from VO2 max alone; Oura CVA uses estimated pulse-wave velocity from PPG waveform;
- do not claim a workload ratio predicts injury;
- do not infer road/trail/gravel without trustworthy map/source data;
- personal discoveries require sufficient data and visible sample sizes;
- current Apple WorkoutKit is a possible future Plans module for structured workouts/pacers/triathlon, but must not silently replace current Watch workout authority;
- Apple documents HealthKit access to hypertension notification events on supported new OS versions; if ever integrated, keep this medically sensitive context separate from sport-readiness scoring.

## Apple Fitness/Forme source icon

Current iPhone project explicitly uses `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and a normal universal 1024×1024 iOS AppIcon PNG.

The old user-observed white/missing source icon in Fitness/Forme is NOT declared fixed. Current iOS 26 developer-forum reports show similar Fitness source-icon rendering issues in other apps. Do not modify the icon asset blindly. Verify a newly recorded workout from a future device candidate for:
- activity type;
- source app name;
- source icon.

## Existing UI/product work preserved

Still present:
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

- current Today Command Center and Daily Brief;
- Recovery Lab;
- Sleep Lab;
- Correlation Lab;
- Behavior Journal;
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
- current combined code on physical iPhone/Watch.

## Next work that does not require hardware first

1. Matched-activity comparison:
   - same sport;
   - similar distance/duration;
   - later route fingerprint;
   - compare pace/speed, HR, effort, elevation and environment context.
2. Extend analytical history to 30/60/90 days for Correlation Lab.
3. Behavior-impact engine only after enough journal history exists; preserve yes/no sample-count gates.
4. Research/implement transparent Fitness / Fatigue / Form only when enough load history is available.
5. Continue sport-specific metric/detail cards and trustworthy map/terrain-source research.
6. Evaluate WorkoutKit as a separate structured Plans module after existing active-workout UX is physically validated.

Do not alter active workout authority/recorder semantics during these analytical UI tasks.

## Next deliberate device candidate

Normal CI must remain artifact-free.

When the analytical tranche is mature enough for real-device inspection:
- create one deliberate `[device-artifact]` build or manual workflow dispatch;
- verify exact BUILD SHA and artifact metadata;
- use `UPDATE_WATCH_SENSOR_LAB.ps1` from the correct dedicated worktree;
- install with the already-validated iLoader workflow;
- test iPhone Today/Recovery/Load/Journal first;
- then Watch idle/depth/wellness sync;
- then one short real WALK;
- then active screens and Apple Fitness/Forme source type/name/icon.

No merge to main, release, or promotion without explicit user approval.
