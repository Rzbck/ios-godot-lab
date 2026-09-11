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

## Repository / branch / resume point

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- active branch: `feat/watch-sensor-product-shell-maps-20260910`
- exact latest CI-validated build-producing code SHA: `0a012414e6ba5e25a13f0f2fb80d816546b3155a`
- parent comparison implementation SHA: `1ab087fe0718a3c5e6d278ded0c85d3fb6ecacf4`
- parent tooling/storage-policy commits:
  - `244d53c713efd32658673167eef8021710c35488` — candidate-only GitHub artifacts
  - `b76e0651dce7baad2a5d68ffdc3862be7d3a6bc7` — updater resolves only retained device artifacts
- local Windows worktree path was **not re-verified in this chat**; before any local command, resolve it from `git worktree list`, then verify branch, `git status`, and exact HEAD.

This HANDOFF update is docs-only. On resume, verify actual branch HEAD. Do not confuse a later docs-only HEAD with the latest CI-validated build SHA above; compare build inputs before reusing the checkpoint.

## Latest CI checkpoint

- workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`
- build SHA: `0a012414e6ba5e25a13f0f2fb80d816546b3155a`
- commit: `feat(tracker): expose similar sessions in progression`
- run: `34566730079`
- job: `103160274613`
- conclusion: **SUCCESS**
- iPhone build: **SUCCESS**
- watchOS build: **SUCCESS**
- HealthKit declaration checks: **SUCCESS**
- combined iPhone + embedded Watch assembly: **SUCCESS**
- exact-SHA packaging: **SUCCESS**
- device artifact upload: **SKIPPED by design**
- workflow artifacts for this run: **0**
- hardware validation: **NOT performed**

The parent implementation SHA `1ab087fe0718a3c5e6d278ded0c85d3fb6ecacf4` is also CI-valid:
- run `34566476368`
- job `103159529999`
- iPhone + Watch + HealthKit + packaging: SUCCESS
- artifact upload: SKIPPED

Do not describe either checkpoint as installed or physically validated.

## GitHub Actions storage policy

Problem observed 2026-09-11:
- 50 Watch Sensor Lab artifacts consumed about 255.42 MB;
- user cleaned 44 redundant artifacts;
- 6 important checkpoints remained, about 12.25 MB total after cleanup.

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
- run `34566090256` on `61689574...`: SUCCESS, upload skipped, 0 artifacts;
- run `34566476368` on `1ab087fe...`: SUCCESS, upload skipped;
- run `34566730079` on `0a012414...`: SUCCESS, upload skipped, 0 artifacts.

`UPDATE_WATCH_SENSOR_LAB.ps1` distinguishes branch HEAD from BUILD SHA and searches for an actual retained artifact. If no compatible artifact exists and auto-build is permitted, it can dispatch a deliberate device build. Never silently treat a green no-artifact CI run as an installable IPA.

## Product intelligence implemented

### Today Command Center + Daily Brief

`TodayCommandCenterView.swift` places `TrackerDailyBriefCard()` directly under the Today hero.

`TrackerDailyBrief.swift` provides:
- a short Today headline based on readable personal signals;
- factor-level cards for recovery, sleep, workload context, HRV and resting HR when available;
- comparison to personal recent baseline where available;
- explicit confidence and provenance;
- missing values remain missing;
- detail explaining why the brief reached its wording;
- no causal or medical language.

Today hierarchy:
1. Today/activity hero;
2. Daily Brief;
3. Tracker Recovery;
4. Today movement;
5. current-vs-previous 7-day trajectory;
6. Cardio Lab;
7. recent workouts;
8. Health signals;
9. progression/history actions.

### Recovery / sleep / night vitals

`TrackerRecoveryIntelligence.swift`:
- personal-baseline recovery intelligence;
- sleep duration, bedtime consistency and continuity;
- HRV, resting HR, respiratory rate and sleeping wrist temperature context;
- recent 7-day workout-volume pressure versus previous reference window;
- explicit confidence/coverage;
- missing factors reduce confidence instead of becoming zero;
- no injury prediction or medical diagnosis.

`TrackerNightVitals.swift`:
- latest sufficiently documented sleep window;
- median overnight HR, HRV, respiratory rate, wrist temperature and oxygen saturation when accessible;
- source and sample count retained;
- values labelled as context, not diagnosis.

`TrackerSleepLabView.swift`:
- latest night duration versus personal sleep baseline;
- continuity and interruptions;
- bedtime regularity;
- accumulated 7-day sleep shortfall versus personal baseline;
- Core / Deep / REM breakdown when available;
- 14-night duration trend with personal baseline;
- embedded Vitals Nuit;
- explicitly does not create a second Apple Sleep Score.

Apple 2026 guardrail retained:
- Apple provides an official Sleep Score in current product behavior;
- there is currently no public HealthKit API for Tracker to read that Apple Sleep Score;
- Tracker Recovery remains its own transparent multi-signal analysis and must not be marketed as Apple Sleep Score.

### Physiology / cardio

`TrackerPhysiologyProfile.swift` reads/contextualizes age, body mass, height, VO2 max and one-minute heart-rate recovery. Adult age-based HRmax estimate (`208 - 0.7 * age`) is fallback context only, never a guaranteed personal maximum.

`TrackerCardioFitnessLab.swift` exposes VO2 max / HR recovery / resting HR / weight trends with long-range charts and source/date context.

Heart-rate reference hierarchy:
1. configured/personal HRmax;
2. adult age estimate when appropriate;
3. workout peak only as last-resort context.

Age/weight are contextual inputs only and do not directly penalize Recovery. Apple VO2 max is already relative to body mass (`mL/kg/min`) and must not be reweighted by body mass again.

### Effort provenance

`AppleWorkoutEffortReader.swift` + `TrackerEffortInsight.swift` keep separate:
- Apple perceived workout effort;
- Apple estimated workout effort;
- Tracker local estimated effort;
- user-entered perceived effort 1–10.

These values never overwrite one another silently.

### Multi-source training load

`TrainingLoadIntelligenceView.swift` presents four independent axes rather than one opaque combined number:
1. all-accessible Apple Health workout volume: recent 7 days vs weekly average of previous 28 days;
2. session-RPE internal load for Tracker sessions with explicit user RPE, calculated as active minutes × RPE;
3. Tracker estimated effort trend for local Tracker sessions;
4. current Tracker Recovery context.

It includes sport filtering, recent daily volume, sRPE when coverage exists, Tracker effort trend, per-session provenance and explicit RPE coverage. Missing RPE is never replaced by a Tracker estimate. Volume ratios are descriptive context only; no ACWR injury prediction.

### Correlation Lab

`TrackerCorrelationLab.swift` currently supports guarded personal associations:
- sleep duration vs next-day HRV;
- sleep duration vs next-day resting HR;
- previous-day workout minutes vs following sleep duration.

Rules:
- raw paired count `n` is visible;
- minimum 10 pairs before relationship wording;
- Pearson `r` is shown as an association coefficient;
- no cause/effect or diagnostic language;
- current first version uses recent Recovery sleep history; 30/60/90-day analytical histories remain future work.

### Local behavior / experiment journal

`TrackerBehaviorJournal.swift` collects local explicit tags such as late caffeine, alcohol, late meal/screen, meditation, sauna/heat, mobility/stretching, hydration, nap, high perceived stress, travel and feeling sick.

Rules:
- local storage only in current implementation;
- optional short note;
- no write to Apple Health;
- tags do not alter Recovery or training-load scores;
- future behavior-impact analysis must require enough observations in both yes/no groups and show sample sizes.

### Matched activity comparison — CI validated

`MatchedActivityComparisonView.swift` was added at `1ab087fe0718a3c5e6d278ded0c85d3fb6ecacf4` and exposed from `ProgressionEntryView.swift` at `0a012414e6ba5e25a13f0f2fb80d816546b3155a`.

Current behavior:
- uses local Tracker sessions only;
- same effective sport is mandatory;
- if useful distance exists, matching prioritizes distance, then duration, with elevation as a nuance;
- otherwise matching prioritizes duration, with heart rate only as a nuance when available;
- minimum displayed similarity is 55%;
- reference session can be changed from the view;
- comparison keeps dimensions separate: pace/speed, average HR, Tracker effort, elevation gain, energy, cadence and weather context when available;
- no global “better/worse” score;
- matching score is only for finding comparable sessions and does not affect health, recovery or effort scores;
- future route fingerprinting is intentionally deferred until it can be made trustworthy.

Progression now exposes:
- Volume récent;
- Charge multi-source;
- Récupération lab;
- Séances similaires.

### iPhone Recovery Lab

Recovery Lab contains:
- Tracker Recovery Intelligence;
- Daily Brief;
- Sleep Lab;
- Correlation Lab;
- Behavior Journal;
- Vitals Nuit;
- Cardio Fitness;
- Physiological Profile.

### Watch wellness sync / Status depth

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
- one-minute HR recovery.

`WatchRecentHistory.swift` persists the optional wellness payload while remaining backward-compatible with older v6/v5/v4 history caches.

`WatchStatusDepthView.swift` vertical Status pages:
1. Devices;
2. Health/GPS sensors;
3. Recovery;
4. Cardio / Night;
5. Load.

Global Watch major-function navigation remains horizontal; Status uses vertical/Crown depth.

## External benchmark / retained guardrails

Research file:
`apps/watch-sensor-lab/RESEARCH_PRODUCT_BENCHMARK_2026-09-11.md`

Retained conclusions:
- do not create a fake cardiovascular-age feature from VO2 max alone; Oura CVA uses estimated pulse-wave velocity from PPG waveform;
- do not claim a workload ratio predicts injury;
- do not infer road/trail/gravel without trustworthy map/source data;
- personal discoveries require sufficient data and visible sample sizes;
- WorkoutKit is a possible future structured Plans module but must not silently replace current Watch workout authority;
- medically sensitive HealthKit context such as hypertension notification events must stay separate from sport-readiness scoring.

## Apple Fitness/Forme source icon

Current iPhone project explicitly uses `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` and a normal universal 1024×1024 iOS AppIcon PNG.

The previously observed white/missing source icon in Fitness/Forme is **NOT declared fixed**. Do not modify the icon asset blindly. A future device candidate must verify a newly recorded workout for:
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

None of the following should be described as device-validated yet:
- current Today Command Center and Daily Brief;
- Recovery Lab;
- Sleep Lab;
- Correlation Lab;
- Behavior Journal;
- night vitals display;
- physiology/cardio lab;
- multi-source training load;
- Matched Activity / Séances similaires UI and real-session matching;
- wellness digest arriving/persisting/rendering on a real Watch;
- Watch Recovery/Cardio status pages fitting all real Watch sizes;
- active Watch four-page redesign;
- active iPhone sport-aware shell;
- map/terrain presentation;
- current effort UI;
- new workout type/source icon in Apple Fitness/Forme;
- current combined code on physical iPhone/Watch.

## Next exact step — deliberate device candidate

The analytical tranche is now mature enough that the next high-value step is **one deliberate real-device candidate before adding another major UI layer**.

Normal CI must remain artifact-free. When the user explicitly chooses to make the candidate:
1. create one deliberate `[device-artifact]` build or manual workflow dispatch on the intended branch/ref;
2. record the exact candidate BUILD SHA and artifact metadata;
3. use `UPDATE_WATCH_SENSOR_LAB.ps1` from the **verified correct dedicated worktree**;
4. verify the downloaded IPA corresponds exactly to the intended BUILD SHA and record its SHA-256;
5. install with the already-validated iLoader workflow;
6. test iPhone Today / Recovery / Load / Journal / Séances similaires;
7. test Watch idle / Status depth / wellness sync and layout;
8. record one short real WALK;
9. inspect active iPhone/Watch screens and Apple Fitness/Forme activity type, source name and source icon;
10. record hardware results and any regression in this HANDOFF.

A generated artifact is not an installation; an installation is not physical behavior validation.

## Subsequent work after the device checkpoint

1. Extend analytical history to 30/60/90 days for Correlation Lab.
2. Add behavior-impact analysis only after enough journal history exists; preserve yes/no sample-count gates.
3. Research/implement transparent Fitness / Fatigue / Form only when enough load history is available.
4. Continue sport-specific metric/detail cards and trustworthy map/terrain-source research.
5. Add route fingerprinting to matched activities only when the route match can be made reliable and explainable.
6. Evaluate WorkoutKit as a separate structured Plans module after existing active-workout UX is physically validated.

## Do not modify casually

- Watch workout authority / HealthKit workout ownership;
- recorder/session semantics already validated;
- explicit Apple / Tracker / user effort provenance;
- existing exact-SHA GitHub Actions + `UPDATE_WATCH_SENSOR_LAB.ps1` + iLoader deployment pipeline;
- artifact-free normal CI policy.

No merge to `main`, release, promotion, destructive Git operation, or cross-app propagation without explicit user approval.
