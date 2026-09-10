# Watch Sensor Lab — Product intelligence research and implementation plan

Date: 2026-09-10

## Purpose

Build Watch Tracker into a premium, compact, depth-first sports and recovery product without inventing medical certainty. Every derived metric must expose its provenance, personal baseline, confidence and missing inputs.

This document supplements `PRODUCT_UX_MASTERPLAN_2026-09-10.md` and the active HANDOFF. It records the research decisions behind future implementation so they are not lost between chats.

## Product north star

The product should answer five questions quickly:

1. **What have I done today?**
2. **How is my body trending compared with my own normal?**
3. **How hard was the latest workout, and why?**
4. **Am I accumulating more or less training than usual?**
5. **What detail do I need now?** — tap/depth rather than permanent clutter.

Primary UI principle: summary first, depth on tap. Watch is glance/action first; iPhone is analysis/explanation first.

## Research benchmark

### Apple / platform

Apple HIG and platform documentation reinforce:
- Watch workout screens should be glanceable and show only the most useful live metrics and controls;
- active-workout state needs visually distinct, readable presentation;
- Digital Crown / vertical pages are preferred for sequential depth;
- hierarchy should remain shallow;
- iPhone is the better place for complex chart interaction;
- charts must prioritize data over axes/decoration and remain accessible;
- maps on iPhone should be interactive; Watch map presentation must remain compact;
- Health data access must be purposeful and privacy-minimal.

### Nielsen Norman Group

Progressive disclosure: show frequent/high-value information first and defer secondary/advanced information behind an obvious interaction. This validates the app-wide strategy:
- top card = immediate answer;
- tappable card = focused depth;
- advanced analysis = secondary screen;
- avoid dashboards that expose every capability simultaneously.

### WHOOP

Useful concepts to adapt, not copy:
- Recovery based on personal physiological baselines rather than population averages;
- HRV, resting HR, sleep, respiratory rate and temperature as separate contributors;
- strain distinct from calories and distinct from recovery;
- sleep need and training pressure influence each other;
- behavior journaling only becomes meaningful after repeated yes/no observations rather than one-off correlations;
- show contributor detail behind the headline score.

### Oura

Useful concepts to adapt, not copy:
- readiness uses both short and long baselines;
- resilience is intentionally slower-moving than daily readiness;
- stress and recovery can be overlaid visually;
- calibration periods are explicit;
- users should focus on long-term trends rather than treating a single score as diagnosis;
- cardiovascular/fitness metrics should expose trend and calibration state.

### Garmin

Useful concepts to adapt, not copy:
- training readiness combines acute load, HRV status, recovery context, sleep and recent stress;
- training status is a trend interpretation, not just one workout;
- VO2 max remains useful but should not be the only training-status input;
- heat/altitude context can modify interpretation when trustworthy data exists.

### Komoot

Useful concepts for maps:
- route presentation is activity-aware;
- sport selection changes which paths/surfaces matter;
- surface/way type is a cartographic-data problem, not something to infer confidently from GPS speed alone;
- elevation and difficulty belong next to map geometry.

### Visual design references

Specialized watch/fitness concepts consistently use:
- very high contrast during motion;
- a single strong accent on dark surfaces;
- large numeric typography;
- arcs/waves/mini charts as secondary visual encoding;
- minimal permanent controls;
- immersive sport-specific screens.

Dribbble/concept work is inspiration only, never authority for platform behavior or physiology.

## Physiology / personal context

### Age

Use cases:
- adult age-based HRmax estimate only as a fallback;
- age-aware interpretation of Apple-provided cardio fitness only where Apple exposes sufficient data;
- profile completeness/freshness.

Do NOT penalize recovery merely because a user is older.

### Weight

Use cases:
- profile freshness;
- energy/calorie context where an actual calculation requires mass;
- derived absolute oxygen consumption display from relative VO2 max if useful;
- future pace/power/vertical-efficiency context where physically justified.

Do NOT multiply recovery or readiness directly by weight.

### Height

Use cases:
- profile context and data freshness;
- cadence/stride interpretation only if validated;
- Apple itself uses height in activity/cardio-fitness estimation, but Watch Tracker should not duplicate Apple’s hidden model.

### Biological sex

Do not request/read until a concrete feature genuinely requires it. Apple already accounts for it in its own cardio-fitness system. Privacy-minimal permission remains preferred.

## Heart-rate maximum and zones

Reference hierarchy:
1. user-defined/personal HRmax;
2. age-predicted adult fallback;
3. session peak only as last resort.

Adult fallback currently planned: Tanaka-style `208 - 0.7 × age`.

Important limitations:
- age equations have substantial individual error;
- adult formula is not used for minors;
- session peak is not physiological HRmax unless the session was actually maximal;
- every zone screen must display which reference was used.

Future possibility: establish a robust observed personal high-HR reference only after enough high-quality workouts, but never silently call it laboratory HRmax.

## VO2 max

Apple Health VO2 max is already a relative quantity in mL/kg/min.

Rules:
- primary display = Apple Health value + trend + source/date;
- do not divide by body mass again;
- optional derived absolute context: `relative VO2 × body mass / 1000 = approximate L/min`;
- do not generate a fake Apple cardio-fitness classification if the public framework does not provide the classification;
- distinguish Apple estimate from clinical/laboratory measurement;
- trend, best recent value, rolling baseline and change rate are more useful than a decorative single number.

Research note: Apple states its Watch cardio-fitness estimate uses age, sex, weight, height and medications affecting heart rate, and is generated from supported outdoor walking/running/hiking contexts.

## Heart-rate recovery

Use `heartRateRecoveryOneMinute` from Apple Health when readable.

Presentation:
- latest value + date/source;
- personal trend/baseline;
- no diagnostic threshold in the app without a dedicated medically validated feature;
- useful as one cardio-recovery trend, not a standalone readiness verdict.

## Sleep system

### Raw night model

Capture/read where available:
- sleep start/end;
- total asleep time;
- awake time;
- Core / Deep / REM / unspecified asleep stages;
- interruptions;
- sleep efficiency/continuity;
- source app/device;
- HRV, resting HR, respiratory rate and sleeping wrist temperature near the night;
- future: naps handled separately from main sleep.

### Personal sleep baseline

Use robust personal statistics over recent history, not a universal 8-hour target.

Current direction:
- median sleep duration baseline;
- bedtime consistency against personal median;
- recent sleep deficit relative to personal baseline;
- staged sleep shown descriptively, not scored against simplistic population percentages.

Population guidance can be shown as educational context only. Research consensus supports at least seven hours regularly for healthy adults, while athlete consensus recommends individualized sleep need rather than one fixed target for everyone.

### Sleep score policy

Do NOT clone or claim Apple Sleep Score.

Watch Tracker may expose a transparent **Sleep context / Tracker sleep component** built from:
- duration vs personal baseline;
- consistency;
- continuity/interruptions;
- confidence based on available nights.

Every contributor must be visible.

### Future sleep need

Candidate formula architecture, to validate before implementation:
- personal baseline sleep need;
- recent sleep deficit carry-over;
- unusually high training strain/load modifier;
- nap credit;
- travel/time-zone modifier if reliable timezone history exists;
- no recommendation presented as treatment.

## Recovery / readiness intelligence

### Daily Tracker Recovery

Transparent contributor architecture:
- sleep context;
- HRV stability vs personal baseline;
- resting-HR stability vs personal baseline;
- recent training pressure;
- respiratory-rate stability;
- sleeping wrist-temperature stability.

Rules:
- missing contributors are ignored, never replaced by zero;
- confidence is shown separately from score;
- robust baseline statistics preferred over means when outliers are likely;
- age/weight do not directly penalize the score;
- labels should describe signals (`stable`, `variable`, `recovery to prioritize`) rather than diagnose illness.

### Medium-term resilience

Future feature:
- slower 14–28 day signal;
- balance of daytime physiological stress, recovery time, nighttime recovery and training pressure;
- intentionally changes more slowly than daily recovery;
- requires calibration before display.

### Daytime physiological stress

Future research/implementation:
- derive only if Health/Watch data coverage is sufficient;
- resting windows must be separated from exercise and obvious motion;
- HR vs personal resting range + HRV + movement context can contribute;
- never label ordinary emotional states or illness from physiology alone;
- show `physiological activation` / `stress signal`, not psychological diagnosis.

## Effort / strain

Three independent effort provenances are mandatory:
1. Apple workout effort entered by user when available;
2. Apple estimated workout effort when available;
3. Watch Tracker estimate from recorded HR-zone exposure, duration, continuity, terrain and environment;
4. Watch Tracker user-entered perceived effort stored separately.

No source silently overwrites another.

Future Tracker load can use:
- HR-zone weighted duration / TRIMP-like context for sessions with good HR coverage;
- session-RPE × duration context where user RPE exists;
- Apple effort × duration where Apple effort is readable;
- sport-specific external load (distance/elevation/power) as separate dimension.

Do not collapse muscular and cardiovascular load into one number unless the inputs justify it.

## Training load and injury-risk policy

7-day vs previous-28-day context is useful for understandable workload comparison and is consistent with current Apple product presentation.

However:
- do not market an acute/chronic workload ratio as an injury predictor;
- literature contains substantial methodological criticism and conflicting evidence;
- no `safe zone = no injury` UI;
- use `recent load compared with your recent baseline`, plus actual components and confidence.

## Behavior / journal intelligence — future differentiator

Potential high-value feature:
- optional quick journal: caffeine late, alcohol, late meal, travel, nap, hydration perception, soreness, stress perception, illness feeling, etc.;
- no conclusion from one occurrence;
- unlock an `impact` only after sufficient repeated yes/no exposure;
- use within-person comparison and confidence interval/effect uncertainty;
- explicitly mark correlation, never causation.

This is one of the strongest differentiators to research after reliable physiology baselines exist.

## Sports-specific intelligence

### Running

Prioritize:
- pace/current/average;
- cadence;
- HR zone;
- running power when Health provides it;
- stride length;
- ground contact time;
- vertical oscillation;
- elevation/grade;
- route comparison;
- future personal critical-pace/performance trend only after research validation.

### Walking / hiking

Prioritize:
- duration, distance, pace;
- HR;
- elevation gain/loss;
- grade;
- route/map;
- surface/way type only from trustworthy map data;
- weather/heat/wind context.

### Cycling

Prioritize:
- speed;
- cadence when readable;
- cycling power / FTP Health types when readable and justified;
- HR zone;
- elevation/grade;
- route/surface.

### Swimming

Prioritize:
- laps/lengths/stroke data only if actual data source supports them;
- distance;
- pace;
- HR caveat under water;
- no meaningless GPS map for pool swimming.

### Strength / HIIT

Do not pretend HR alone represents muscular load.

Future:
- session RPE;
- set/rep/load entry or automatic IMU research;
- muscular-load dimension separate from cardio load;
- rest interval analysis.

## Maps / terrain

### Implemented / near-term

- standard/hybrid/satellite presentation;
- route bounds;
- start/end;
- elevation profile;
- gain/loss;
- grade;
- route-first sport-specific layout.

### Required for Komoot-grade terrain

Need trustworthy cartographic dataset/API containing way/surface data.

Candidate research direction:
- OpenStreetMap-based way/surface tags or another licensed routing provider;
- offline/cache/privacy/cost/licensing assessment first;
- map matching GPS track to ways before assigning road/trail/gravel;
- confidence + mixed/unknown classifications;
- never infer paved/trail solely from user speed.

## Weather / environment

Use existing recorded weather context for workout explanation:
- temperature/apparent temperature;
- humidity;
- wind speed/direction/gust;
- headwind/tailwind component where route direction supports it;
- elevation/altitude context.

Future analytics:
- compare similar routes in different conditions;
- explain pace/HR deviations with environment as context, not causal proof;
- heat acclimation feature only after sufficient repeated data and research validation.

## Revolutionary but defensible product ideas

Prioritized research backlog:

1. **Explainable Daily Brief** — one compact card: today activity + recovery + sleep + training pressure; tap any contributor.
2. **Same-point comparison** — current week/month versus previous period at the exact same elapsed point.
3. **Adaptive depth** — cards automatically prioritize what changed most, while all metrics remain reachable.
4. **Data Confidence Layer** — every score/chart can reveal coverage, source, baseline size and algorithm version.
5. **Similar Session Explorer** — compare today’s workout against genuinely comparable past sessions (same sport, duration/distance/route context).
6. **Condition-adjusted performance context** — pace/power/HR comparison annotated by wind, temperature, grade and pauses.
7. **Personal Response Lab** — learn how workload and optional journal behaviors correlate with next-night sleep/recovery, only after enough samples.
8. **Recovery trajectory** — not just today’s score; visualize whether several signals are returning toward personal baseline.
9. **Route fingerprint** — elevation, turns, surface once map-matched, weather and performance combined into a reusable route identity.
10. **Sport-aware Watch cards** — live cards chosen by actual activity, with tap depth and Crown pages instead of one generic dashboard.
11. **Calibration mode** — tell the user exactly which intelligence features are still learning and what data is missing.
12. **Algorithm provenance view** — version, source and confidence available without polluting the main UI.

## UI system direction

### iPhone

- Today is first and answers the day in one screen before scrolling;
- strong hero + one intelligence card + activity cards + trends;
- 2-column compact metric grid only for peer metrics;
- full-width cards for concepts requiring explanation;
- cards always show tap affordance if they have depth;
- use animated/current-vs-reference overlays rather than percentage text alone;
- route/elevation cards use large visual plot area;
- advanced filters live behind clear secondary controls.

### Watch

- no generic long dashboard;
- major context as pages, depth by Crown/vertical page/tap;
- primary action remains visually dominant;
- max 2–3 small controls per row;
- large changing numbers, monospaced digits;
- one accent family per page;
- use color/material as context, not decoration;
- charts are miniature summaries, not interactive analytical canvases;
- focus state/selection should be obvious while in motion.

## Accessibility / performance

- all meaningful charts require accessibility summaries;
- do not encode meaning by color alone;
- respect Dynamic Type / minimumScaleFactor on compact cards;
- no high-frequency SwiftUI recomputation from expensive Health queries;
- Health analysis runs on demand/background queues and publishes compact snapshots to UI;
- cache derived daily snapshots by source-data revision/time window later if profiling shows repeated Health queries are costly;
- Watch receives compact derived summaries rather than raw historical Health data.

## Implementation sequence from current branch

1. Apple workout effort provenance reader + UI.
2. Transparent sleep/recovery engine with confidence.
3. Physiological profile: age, weight, height, VO2 max, 1-minute HR recovery.
4. HRmax reference hierarchy and transparent zones.
5. Surface Daily Recovery on Today and Watch Status/Progression.
6. Add VO2/cardio-fitness trend depth and personal change rate.
7. Replace duration-only recent volume with multi-dimensional Tracker load while retaining raw volume.
8. Sleep need / debt / nap model after data-quality validation.
9. Similar-session comparison.
10. Conditions-adjusted workout comparison.
11. Cartographic map matching/surface research and implementation.
12. Behavior-response journal with minimum sample requirements.
13. Medium-term resilience/stress model only after calibration/data coverage is proven.
14. Hardware reliability matrix before release-quality claim.

## Explicit non-goals / safety rails

- no medical diagnosis;
- no injury-risk prediction from ACWR;
- no fake road/trail/surface classification;
- no fake VO2 max derived from ordinary workouts when Apple Health already provides a provenance-aware estimate;
- no hidden merge of Apple effort, Tracker estimate and user RPE;
- no population average silently replacing missing personal data;
- no age/weight penalty in daily recovery;
- no claim that a generated IPA is physically validated;
- no recorder/session-authority changes inside a pure analytics/UI tranche.
