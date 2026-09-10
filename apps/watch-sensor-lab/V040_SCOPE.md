# Watch Tracker v0.4 — master scope and validation ledger

Date: 2026-09-10

This file is the authoritative implementation ledger for v0.4. It exists so no field-test feedback or user requirement is lost while the code evolves.

## Scope contract

All requirements explicitly requested by the user after the first real field walk are part of the v0.4 product scope unless a platform/hardware limitation is proven. A requirement may only be closed in one of these ways:

1. `PHYSICALLY_VALIDATED` on real iPhone/Apple Watch;
2. `BLOCKED_BY_PLATFORM` with concrete technical evidence and an alternative documented, then explicitly accepted by the user.

Do not silently drop, rename away, or treat a partially implemented foundation as complete.

Status vocabulary:

- `TODO`: not implemented yet.
- `IMPLEMENTED`: code exists but exact CI has not validated it.
- `CI_VALIDATED`: exact-SHA CI compiled/packaged it; hardware behavior still unproven.
- `PHYSICALLY_VALIDATED`: user observed the intended behavior on real hardware.
- `PARTIAL`: foundation exists but the full acceptance criterion is not met.
- `BLOCKED_BY_PLATFORM`: only after verified platform limitation; requires documented alternative + user acceptance.

## Immutable regression baseline

- physical field-test app SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- app version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- preserved main field session: `1789026745407`
- preserved PC archive: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- baseline must not be deleted or rewritten.

## Current v0.4 line

- repository: `Rzbck/ios-godot-lab`
- branch: `feat/watch-sensor-v040-20260910`
- dedicated Windows worktree confirmed: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`
- first v0.4 code/CI head: `b8702027f2546189326e747e8c842177120c303c`
- first v0.4 CI run: `34464673739` — SUCCESS
- validated summary/segments/Health-context slice SHA: `89e04aa508e978a21627a98cccc4a21e99f64278`
- CI run: `34467626579` — SUCCESS
- artifact id: `10148264237`
- artifact digest: `sha256:aceb8151cd847f103e5dbcdfe4de7a0539f9151ba41ff7e9ca781e176fc9be58`
- validated Watch-recent-history slice SHA: `af38d7c7fc90f44873bdd4bf00e79960bd2c821c`
- CI run: `34468156004` — SUCCESS
- artifact id: `10148457809`
- artifact digest: `sha256:d2140e14b0750f1d606240adc0b96e8b0cce481e21c800c917b4e4a46a45f992`
- first hardware candidate SHA: `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`
- candidate CI run: `34468523258` — SUCCESS
- downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\3efcc2cd313f\WatchSensorLab-companion-unsigned-3efcc2cd313f.ipa`
- downloaded IPA SHA-256: `07b8aa7bec9e0716b569f6f5ec925c8299d4d3056405acd10a5451f8f1dc798f`
- first hardware checkpoint: iPhone launches, Apple Watch launches, existing baseline history remains visible on iPhone after upgrade.
- field validation of new v0.4 metrics is deferred until the user next goes outside.
- generic iLoader/watchOS-publication work is a separate chantier and must not contaminate this tracker scope/repo.

## Mandatory requirements from field analysis + user feedback

### Correctness and sensor evidence

- `V040-001` — **Correct HealthKit semantics for Auto** — `CI_VALIDATED / PARTIAL`.
  - Current v0.4 no longer starts Auto as `.mixedCardio`; it starts with the current effective type (Walking by default).
  - Remaining acceptance criterion: if Auto changes Walk -> Run -> Cycle during one session, HealthKit representation must remain semantically correct rather than leaving the entire workout typed as the initial sport.
  - General mixed outings must use a segment model.

- `V040-002` — **Reject implausible GPS/speed spikes and make max speed trustworthy** — `CI_VALIDATED`, hardware validation pending.
  - Sport-aware plausibility ceilings and stricter Watch GPS delta filtering exist.
  - Acceptance: a real walk/run/ride must not reproduce the ~30 km/h walking spike seen in the baseline unless raw evidence justifies it.

- `V040-003` — **Reliable elevation gain/loss** — `CI_VALIDATED`, hardware validation pending.
  - Watch now prefers `CMAltimeter` relative-altitude changes; filtered GPS altitude is fallback.
  - Acceptance: compare v0.4 D+/D- to known route/elevation and baseline; no cumulative GPS-noise explosion.

- `V040-004` — **Fix zero gyroscope** — `CI_VALIDATED`, hardware validation pending.
  - `CMDeviceMotion.rotationRate` is preferred; raw gyro is fallback; source is logged.
  - Acceptance: real Watch field log contains non-zero plausible rotation data and records the source.

- `V040-005` — **Bounded event/diagnostic logging** — `CI_VALIDATED`, hardware validation pending.
  - START/control requests, phase changes, stale authority, Auto candidates/transitions, HealthKit/mirroring errors and Watch events are logged without high-rate console spam.
  - Acceptance: next extracted session can reconstruct START/PAUSE/RESUME/STOP, Auto decisions and transport/reconnect failures.

- `V040-006` — **Record Watch GPS for Watch/iPhone comparison** — `CI_VALIDATED`, hardware validation pending.
  - Watch sends `watch_location` samples with accuracy, native speed, implied speed, accepted/rejected distance delta and activity context.
  - Acceptance: next corpus supports point/time comparison of Watch vs iPhone GPS and distance.

- `V040-007` — **Physically verify HealthKit workout + route + exact deletion** — `TODO physical test`.
  - Acceptance: workout appears with correct type, route is visible/coherent, and app deletion removes only Watch Tracker-owned workout/route data.

- `V040-008` — **Deliberate Auto field tests** — `TODO physical test`.
  - Walk -> Run -> Walk.
  - Separate Cycle test.
  - Later mixed/multisport transition tests.

### Startup and live UI

- `V040-009` — **Remove redundant Watch badge obscuring iPhone map** — `CI_VALIDATED`, hardware/UX validation pending.
  - Header now contains history access instead of the redundant Watch capsule.

- `V040-010` — **Compact GPS / Watch / Health readiness UI on iPhone** — `CI_VALIDATED`, hardware/UX validation pending.

- `V040-011` — **Stop startup values jumping visibly** — `CI_VALIDATED / PARTIAL`, hardware validation pending.
  - Initial GPS/altitude/distance/speed display is gated behind acquisition state/placeholders.
  - Acceptance: real startup looks stable; add further display smoothing only if hardware still visibly jumps.

- `V040-012` — **Real-time active calories on iPhone and Watch** — `CI_VALIDATED`, new-session hardware validation pending.
  - Baseline v0.3.1 summary does not contain calories, so its history row cannot display a stored calorie value. Do not invent one.
  - Future enrichment from a confidently matched HealthKit workout may backfill legacy display context.

- `V040-013` — **Horizontal swipe for additional Watch live data pages** — `CI_VALIDATED`, hardware/UX validation pending.
  - Live metrics page contains a horizontal inner pager while main workout navigation remains vertical.

### Rich live/post-session metrics

- `V040-014` — **Cadence / step count / pedestrian pace where available** — `CI_VALIDATED / PARTIAL`.
  - `CMPedometer` cadence and steps are implemented and exposed.
  - Remaining: validate hardware availability/cadence quality; expose additional pedestrian pace/derived metrics where useful.

- `V040-015` — **Walking gait/balance/asymmetry/step length/double support** — `CI_VALIDATED / PARTIAL`, hardware/data-availability validation pending.
  - Post-session Health context now queries Apple-produced walking speed, step length, asymmetry, double-support and Walking Steadiness when available.
  - These are explicitly labelled as contextual Health data, not fake live Watch Tracker sensors.
  - Acceptance: verify real device permissions and which metrics actually exist for the baseline/new sessions.

- `V040-016` — **Respiration-related data** — `CI_VALIDATED / PARTIAL`.
  - Post-session Health context can show Apple respiratory-rate samples found around the activity window.
  - It is explicitly labelled contextual, not workout-live respiration.
  - Remaining: decide whether a separate experimental workout-time estimator is useful; if implemented it must be clearly labelled estimated/experimental and separately validated.

- `V040-017` — **Richer heart-rate / running metrics** — `CI_VALIDATED / PARTIAL`.
  - Current/average/max HR and calories exist.
  - Post-session Health context now queries HR max/recovery and, when available, running speed, running power, stride length, ground contact time and vertical oscillation.
  - Remaining: zones/time-in-zone and physical availability/quality checks on compatible hardware.

- `V040-018` — **Sensor availability/quality indicators** — `CI_VALIDATED / PARTIAL`.
  - Acquisition placeholders, GPS accuracy and gyro source exist.
  - Expand to explicit quality/provenance for metrics used in summaries.

### Weather / environmental effort context

- `V040-019` — **Persist environmental context with every outdoor session** — `CI_VALIDATED`, hardware/network validation pending.
  - v0.4 model stores provider, timestamp, coordinates, temperature, apparent temperature, humidity, pressure, wind speed, wind direction, gusts and weather code.
  - Current provider implementation is Open-Meteo to avoid adding an unvalidated WeatherKit entitlement to the iLoader signing path.
  - Captures are coarse snapshots, not per-GPS-point spam.

- `V040-020` — **Use weather to improve interpretation of effort** — `CI_VALIDATED / PARTIAL`, physical/network validation pending.
  - Post-session analyzer computes average temperature/apparent temperature/humidity/pressure/wind, peak gust and a descriptive headwind/tailwind component derived from route heading + meteorological wind direction.
  - The summary explicitly labels this as environmental context, not a medical score.
  - Remaining: validate real snapshots, tune route/segment correlation and later use environmental context in cross-session comparisons.
  - Never treat Apple Watch wrist temperature as ambient temperature.

### History and summaries

- `V040-021` — **Persistent activity history on iPhone** — `PHYSICALLY_VALIDATED / PARTIAL`.
  - Upgrade installation of candidate `3efcc2cd...` preserved and displayed the pre-v0.4 baseline activity on the real iPhone.
  - Remaining acceptance: create a new v0.4 activity, verify it persists across relaunch/update, then validate detail/route/metrics from the new schema.

- `V040-022` — **Proper post-activity summary** — `CI_VALIDATED / PARTIAL`, hardware/UX validation pending.
  - A just-finished session is now automatically presented after STOP.
  - Summary includes route, distance, active time, pace, average/max HR, calories, D+/D-, max speed, cadence, persistent segments, environmental effort context, contextual Health metrics and technical trace.
  - Remaining: explicit pause totals/events and zones/time-in-zone; refine presentation after real-device feedback.

- `V040-023` — **Recent activity/history access on Apple Watch** — `CI_VALIDATED`, hardware/sync validation pending.
  - iPhone publishes compact digests for the 8 most recent sessions through WatchConnectivity queued user info.
  - Watch persists them locally and exposes an `Activités récentes` screen with sport/date/duration/distance/calories/D+.
  - Acceptance: confirm history arrives after upgrading/opening iPhone and remains viewable on Watch without immediate phone reachability.

- `V040-024` — **Schema/build/algorithm provenance for historical activities** — `CI_VALIDATED`, hardware/migration validation pending.
  - Acceptance: old summaries decode, new summaries identify schema/app/build/algorithm and remain interpretable after algorithm changes.

- `V040-025` — **Never purge history during normal update/install** — `PHYSICALLY_VALIDATED for first upgrade / PARTIAL`.
  - Candidate `3efcc2cd...` was installed as an upgrade and the original field-walk history remained visible on the iPhone.
  - Purge remains explicit only.
  - Remaining: revalidate on later v0.4 upgrades and confirm no Watch-side history loss/regression.

### Auto-pause

- `V040-026` — **Optional auto-pause** — `CI_VALIDATED / PARTIAL`.
  - Global toggle exists, Watch owns execution, activity-specific delays exist, hysteresis and manual/auto distinction exist.
  - Remaining: user-facing settings should become activity-specific rather than one global preference; field-tune thresholds separately for walk/run/cycle; verify manual Pause always wins.

### Auto classification / hiking

- `V040-027` — **Conservative Auto Walk/Run/Cycle** — `CI_VALIDATED`, transition hardware tests pending.
  - Keep confidence/hysteresis; false switches are worse than delayed switches.

- `V040-028` — **Hiking/randonnée inference** — `TODO`.
  - Use motion + sustained outdoor walking + terrain/elevation/context; do not pretend Core Motion has a native hiking category.
  - Early versions may label “Randonnée probable” and ask/allow confirmation.

- `V040-029` — **Expose Auto confidence/provenance** — `TODO / PARTIAL`.
  - Auto candidate/change events exist internally.
  - Remaining: user/debug/history representation must distinguish Apple classification from our inferred classifier.

### Multisport / triathlon / mixed outings

- `V040-030` — **First-class session segments** — `CI_VALIDATED / PARTIAL`.
  - v0.4 now derives and persists segment summaries from durable Auto/multisport transition events at session finish, including activity, start/end and distance when cumulative location evidence is available.
  - Auto changes and manual triathlon transitions therefore become visible in the post-session summary/history.
  - Remaining: guarantee segment-event delivery across Watch/iPhone disconnection, persist richer segment metrics (energy/HR/elevation), and support general mixed-master semantics.

- `V040-031` — **Manual triathlon in one HealthKit `swimBikeRun` session** — `CI_VALIDATED`, hardware validation pending.
  - Current code supports swim -> transition -> bike -> transition -> run through explicit Watch advancement.
  - Acceptance: one coherent Health/Fitness workout with segment/transition behavior verified physically.

- `V040-032` — **Automatic triathlon transitions** — `TODO`.
  - Must come after reliable manual transitions and field evidence.

- `V040-033` — **General mixed outing in one Watch Tracker master session** — `TODO`.
  - Example: bike -> walk -> run -> bike.
  - HealthKit objects must remain semantically correct even if Watch Tracker presents one master activity.

- `V040-034` — **Automatic mixed-sport transition detection** — `TODO`.
  - High confidence/hysteresis required; manual override must always exist.

### Additional product improvements accepted for the roadmap

These are recommended additions discovered during tracker-product research and should be tracked after the mandatory correctness/product work above:

- `V040-035` — automatic km/mile splits — `TODO`.
- `V040-036` — HR/pace/speed zones and post-session time-in-zone — `TODO`.
- `V040-037` — configurable haptic alerts — `TODO`.
- `V040-038` — rolling pace/speed rather than only instantaneous values — `TODO`.
- `V040-039` — GPX/TCX/FIT export strategy — `TODO`.
- `V040-040` — compare a session against previous/baseline activities — `TODO`.
- `V040-041` — sensor/data-quality score and missingness indicators — `TODO`.
- `V040-042` — legacy-history HealthKit enrichment — `TODO`.
  - For old summaries that predate calories/richer fields, optionally attach contextual values only after confidently matching the app-owned HealthKit workout. Never synthesize or guess missing historical values.

## Definition of v0.4 done

Do not describe v0.4 as finished merely because it compiles.

For the user-requested scope, completion requires:

- every mandatory `V040-001` through `V040-034` either `PHYSICALLY_VALIDATED`, or explicitly `BLOCKED_BY_PLATFORM` with evidence + an accepted alternative;
- historical baseline `1789026745407` still preserved externally and not silently deleted from the app during upgrade tests;
- exact-SHA CI artifact/install identity recorded for every physical test build;
- no regression of Watch-authoritative START/PAUSE/RESUME/STOP synchronization;
- HealthKit type/route/deletion behavior physically checked;
- next extracted field corpus compared against the 2026-09-10 baseline for speed, elevation, gyro, GPS continuity and Auto behavior.

## Update rule

Every meaningful code milestone must update this ledger in the same development cycle. Move statuses forward only with evidence. Never mark `PHYSICALLY_VALIDATED` from CI or code inspection alone.
