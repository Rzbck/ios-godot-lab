# HANDOFF — Product intelligence / wellness / multi-source load

Date: 2026-09-11

## Objective

Continue Watch Sensor Lab as a premium sports/wellness app while preserving the already-established Watch workout authority and recorder semantics.

Current product priorities:
- Today first;
- compact depth-first iPhone/Watch UI;
- transparent sleep/recovery/cardio intelligence with personal baselines and confidence;
- explicit Apple / Tracker / user effort provenance;
- multi-source training-load context without medical/injury claims;
- personal discoveries only with enough observations and visible sample sizes;
- maps/terrain and sport-aware live UI;
- no opaque or fabricated health values.

## Repository / branch / resume point

- repository: `Rzbck/ios-godot-lab`
- app: `apps/watch-sensor-lab`
- active branch: `feat/watch-sensor-product-shell-maps-20260910`
- exact latest CI-validated build-producing code SHA: `ef5dce3c2fc0c00fc6524a7c4245e47100e0bb8a`
- previous CI-valid matched-session navigation SHA: `0a012414e6ba5e25a13f0f2fb80d816546b3155a`
- matched-session implementation SHA: `1ab087fe0718a3c5e6d278ded0c85d3fb6ecacf4`
- parent tooling/storage-policy commits:
  - `244d53c713efd32658673167eef8021710c35488` — candidate-only GitHub artifacts
  - `b76e0651dce7baad2a5d68ffdc3862be7d3a6bc7` — updater resolves only retained device artifacts
- local Windows worktree path was not re-verified in this chat; before local commands resolve it from `git worktree list`, then verify branch, status and exact HEAD.

This HANDOFF commit is docs-only. On resume, verify actual branch HEAD and distinguish later docs-only HEAD from the build-producing SHA above.

## Latest CI checkpoint

Workflow: `.github/workflows/watch-sensor-lab-bootstrap.yml`

- build SHA: `ef5dce3c2fc0c00fc6524a7c4245e47100e0bb8a`
- commit: `feat(tracker): extend correlations to 30 60 90 days`
- run: `34567268759`
- job: `103161874656`
- conclusion: **SUCCESS**
- iPhone build: **SUCCESS**
- watchOS build: **SUCCESS**
- HealthKit declaration checks: **SUCCESS**
- combined iPhone + embedded Watch assembly: **SUCCESS**
- exact-SHA packaging: **SUCCESS**
- device artifact upload: **SKIPPED by design**
- workflow artifacts: **0**
- hardware validation: **NOT performed**

Intermediate run `34567236165` on `e311dadcd4bc198751f31a7476d8e63a91f02232` was **CANCELLED by design** when the newer branch commit arrived, confirming branch-scoped `cancel-in-progress` behavior.

Do not describe this checkpoint as installed or physically validated.

## GitHub Actions / artifact policy

Current verified behavior:
- normal build-relevant push runs full iPhone + Watch CI;
- normal push stores **0 device artifacts**;
- artifact upload happens only for a deliberate device candidate (`[device-artifact]`) or manual `workflow_dispatch`;
- candidate retention: 2 days;
- docs/HANDOFF/tooling-only changes do not trigger app CI;
- branch-scoped `cancel-in-progress` keeps only the newest relevant build running.

Verified artifact-free runs include:
- `34564308303` on `244d53c7...`;
- `34565274225` on `a741407f...`;
- `34566090256` on `61689574...`;
- `34566476368` on `1ab087fe...`;
- `34566730079` on `0a012414...`;
- `34567268759` on `ef5dce3c...`.

`UPDATE_WATCH_SENSOR_LAB.ps1` distinguishes branch HEAD from BUILD SHA, checks build-input equivalence, locates or dispatches a retained candidate artifact, verifies metadata/SHA-256 and downloads the exact IPA. Never treat a green no-artifact CI run as an installable IPA.

## Implemented product intelligence

### Today / Daily Brief

`TodayCommandCenterView.swift` places `TrackerDailyBriefCard()` directly under the Today hero.

Daily Brief uses readable personal signals, recent baselines, explicit confidence/provenance and missing-data handling. It does not use causal or medical wording.

### Recovery / Sleep / Night vitals

`TrackerRecoveryIntelligence.swift` provides personal-baseline recovery using sleep, HRV, resting HR, respiratory rate, wrist temperature and workload context. Missing factors reduce confidence instead of becoming zero.

`TrackerSleepLabView.swift` includes latest-night duration vs baseline, continuity, interruptions, bedtime regularity, 7-day sleep shortfall, Core/Deep/REM when available, 14-night trend and Vitals Nuit.

`TrackerNightVitals.swift` reads overnight HR, HRV, respiratory rate, wrist temperature and oxygen saturation when accessible, with source/sample context.

Tracker does not recreate or market its analysis as Apple Sleep Score.

### Physiology / Cardio

`TrackerPhysiologyProfile.swift` contextualizes age, body mass, height, VO2 max and one-minute HR recovery. Adult HRmax estimate (`208 - 0.7 * age`) is fallback context only.

`TrackerCardioFitnessLab.swift` exposes VO2 max / HR recovery / resting HR / weight trends with source/date context.

### Effort provenance

Apple perceived effort, Apple estimated effort, Tracker estimated effort and user-entered RPE remain separate and never overwrite one another silently.

### Multi-source training load

`TrainingLoadIntelligenceView.swift` keeps four independent dimensions:
1. Apple Health workout volume, recent 7 days vs previous 28-day weekly average;
2. session-RPE = active minutes × explicit user RPE;
3. Tracker estimated effort trend;
4. current Tracker Recovery context.

Missing RPE is never replaced by Tracker estimation. Workload ratios are descriptive only; no ACWR injury prediction.

### Correlation Lab — 30 / 60 / 90 days, CI validated

New `TrackerCorrelationHistoryReader.swift` reads long analytical history directly from accessible Apple Health data without changing the short 14-night Sleep Lab UI history.

`TrackerCorrelationLab.swift` now supports selectable **30 / 60 / 90 day** windows for:
- sleep duration vs next-day HRV;
- sleep duration vs next-day resting HR;
- previous-day workout minutes vs following sleep duration.

Behavior:
- each selected window reloads the corresponding HealthKit history;
- `r` is recalculated from the actual selected-window pairs;
- raw pair count `n` is visible;
- minimum 10 pairs before relationship wording;
- multi-source sleep duplicates are reduced by choosing the best-documented source for each night;
- no causal, diagnostic or medical interpretation.

### Local behavior journal

`TrackerBehaviorJournal.swift` stores optional local behavior tags such as caffeine, alcohol, late meal/screen, meditation, sauna, mobility, hydration, nap, high perceived stress, travel and feeling sick.

Tags do not write to HealthKit and do not modify Recovery/training-load scores. Behavior-impact analysis remains gated on sufficient yes/no samples.

### Matched activity / Séances similaires — CI validated

`MatchedActivityComparisonView.swift` is exposed from Progression.

Current matching:
- same effective sport mandatory;
- useful-distance sessions prioritize distance then duration, with elevation as nuance;
- otherwise duration is primary and HR may be a nuance;
- minimum similarity 55%;
- reference session can be changed;
- comparison keeps pace/speed, average HR, Tracker effort, D+, energy, cadence and weather separate;
- no global “better/worse” score;
- matching score does not affect health/recovery/effort scores;
- route fingerprinting intentionally deferred until reliable/explainable.

Progression exposes:
- Volume récent;
- Charge multi-source;
- Récupération lab;
- Séances similaires.

### Watch wellness sync / Status depth

The existing recent-history v6 WatchConnectivity transfer also carries a compact wellness digest when available: Recovery/confidence, sleep, workload context, night HR/HRV/respiration/temperature/O₂, VO2 max and one-minute HR recovery.

Watch Status depth remains:
1. Devices;
2. Health/GPS sensors;
3. Recovery;
4. Cardio / Night;
5. Load.

Global Watch major navigation remains horizontal; Status depth remains vertical/Crown-based.

## Important retained guardrails

- no fake cardiovascular age from VO2 max alone;
- no workload-ratio injury prediction;
- no road/trail/gravel inference without trustworthy source data;
- personal discoveries require sufficient data + sample counts;
- WorkoutKit, if used later, must be a separate Plans module and must not replace current Watch workout authority;
- medically sensitive HealthKit context must stay separate from sport readiness scoring.

## Apple Fitness/Forme source icon

The previously observed white/missing source icon is **NOT declared fixed**. Do not change AppIcon blindly. A real device candidate must verify a newly recorded workout for activity type, source app name and source icon.

## NOT physically validated yet

None of these should be described as device-validated yet:
- Today Command Center / Daily Brief;
- Recovery Lab / Sleep Lab / 30-60-90 Correlation Lab / Behavior Journal;
- night vitals, physiology/cardio lab, multi-source load;
- Séances similaires matching and UI;
- wellness digest on a real Watch;
- Watch Status depth/layout on real sizes;
- active Watch four-page redesign;
- active iPhone sport-aware shell;
- map/terrain presentation;
- effort UI;
- Apple Fitness/Forme source type/name/icon;
- current combined code on physical iPhone/Watch.

## Next exact step — one deliberate device candidate

The analytical tranche is mature enough that the next high-value step is **one real-device checkpoint before another major UI/analytics layer**.

When the user chooses the candidate:
1. create one deliberate device-artifact build/manual dispatch on the intended branch;
2. record exact BUILD SHA and artifact metadata;
3. run `UPDATE_WATCH_SENSOR_LAB.ps1` from the verified correct dedicated worktree;
4. verify exact IPA BUILD SHA + SHA-256;
5. install with the existing iLoader workflow;
6. inspect iPhone Today / Recovery / Load / Journal / Correlation 30-60-90 / Séances similaires;
7. inspect Watch idle / Status depth / wellness sync/layout;
8. record one short real WALK;
9. inspect active iPhone/Watch screens and Apple Fitness/Forme activity type/source/icon;
10. record hardware results/regressions here.

A generated artifact is not an installation; an installation is not physical behavior validation.

## Remaining product work after the device checkpoint

1. Behavior-impact engine only after enough journal history exists, with yes/no sample-count gates.
2. Transparent Fitness / Fatigue / Form only when enough load history exists.
3. Continue sport-specific metric/detail cards and trustworthy map/terrain-source research.
4. Add route fingerprinting to matched activities only when route matching is reliable and explainable.
5. Evaluate WorkoutKit as a separate structured Plans module after existing active-workout UX is physically validated.
6. Continue premium UI refinement based on real iPhone/Watch observations rather than theoretical layout alone.

## Do not modify casually

- Watch workout authority / HealthKit workout ownership;
- recorder/session semantics already validated;
- explicit Apple / Tracker / user effort provenance;
- exact-SHA GitHub Actions + `UPDATE_WATCH_SENSOR_LAB.ps1` + iLoader pipeline;
- artifact-free normal CI policy.

No merge to `main`, release, promotion, destructive Git operation or cross-app propagation without explicit user approval.


## Invariant iPhone / Watch — workflow partagé

À partir du chantier `fix/watch-auto-run-integrity-20260911`, toute fonction de
workflow utilisateur commune doit exister sur iPhone et Apple Watch.

Le contrat de compilation est `TrackerSharedWorkflowSurface` dans
`Shared/TrackerShared.swift`.

Les fonctions couvertes sont au minimum :
- choix d'activité ;
- démarrage ;
- activation/désactivation de l'auto-pause ;
- pause ;
- reprise ;
- validation de fin ;
- conservation des segments Auto ou correction utilisateur ;
- purge des données de test.

La Watch reste autoritaire pour l'état réel de la séance et les capteurs.
L'iPhone peut commander le même workflow mais ne possède pas une deuxième
machine d'état concurrente.

Une fonction réellement spécifique au matériel peut rester spécifique à un
appareil, mais elle doit être identifiée explicitement comme telle. Une étape
de workflow utilisateur commune ne doit jamais être ajoutée à une seule UI.

`CHECK_WORKFLOW_PARITY.py` est exécuté par la CI. Une divergence du contrat
commun doit faire échouer le build au lieu d'être découverte sur le terrain.


## Correction historique HealthKit — invariant transactionnel

Une correction d’activité historique est un workflow partagé iPhone / Watch
(`historicalActivityCorrection`), avec exécution HealthKit autoritaire sur la
Watch.

Ordre obligatoire :
1. conserver les fichiers raw Tracker et l’ActivityReview ;
2. retrouver les workouts gérés par Watch Tracker via `session_id` ;
3. charger les samples, événements et routes AVANT mutation ;
4. construire le workout du nouveau type ;
5. reconstruire sa route ;
6. relire le remplacement depuis HealthKit et vérifier type, bornes, samples,
   distance et route ;
7. seulement après validation, supprimer l’ancien workout ;
8. si une étape avant 7 échoue, supprimer uniquement le remplacement et
   conserver l’original.

La correction ne réécrit jamais `samples.jsonl`.

Migration terrain en attente :
- session `1789141684582`
- activité confirmée par l’utilisateur : `cycling`
- ne pas considérer la migration validée avant retour
  `health_manual_correction_completed` et vérification matérielle dans Santé.
