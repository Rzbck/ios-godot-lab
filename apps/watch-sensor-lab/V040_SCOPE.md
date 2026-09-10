# Watch Tracker v0.4 — master scope and validation ledger

Date: 2026-09-10

This is the authoritative v0.4 requirement/validation ledger. A requirement is not complete because it compiles: final closure requires real-device validation, or a proven platform limitation with an accepted alternative.

Status vocabulary: `TODO`, `IMPLEMENTED`, `CI_VALIDATED`, `PHYSICALLY_VALIDATED`, `PARTIAL`, `BLOCKED_BY_PLATFORM`.

## Immutable regression baseline

- physical baseline app SHA: `1bbd803f491651acb9f4ccb0b2518c4f71d5c55e`
- version: `0.3.1 (4)`
- CI run: `34451272790` — SUCCESS
- preserved session: `1789026745407`
- archive: `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\walk-20260910-111806.zip`
- never delete/rewrite this baseline.

## Current v0.4 line

- repository: `Rzbck/ios-godot-lab`
- branch: `feat/watch-sensor-v040-20260910`
- Windows worktree: `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-v040`
- first v0.4 hardware candidate: `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`, run `34468523258` — SUCCESS; iPhone + Watch launch and history preservation physically validated.
- analytics milestone: `cf6b9550a54cb36f1111e94a5a2054384c3a1564`, run `34481920623` — SUCCESS.
- mixed-Auto HealthKit code milestone: `7ed592b7b44473545f516857b2f6ad451b74d70f`, run `34484069701` — SUCCESS.
- mixed-Auto artifact id: `10154989894`.
- mixed-Auto artifact digest: `sha256:94dce10d0e3b462f896b840d4dae80e37f5d8b0e43b66557cb1429cfa6d842e1`.
- `7ed592b7...` compiled iPhone + watchOS, verified HealthKit declarations, assembled companion, packaged exact-SHA IPA and uploaded artifact.
- mixed-Auto HealthKit runtime behavior is **NOT physically validated yet**.

## Mandatory requirements

### Correctness / sensor evidence

- `V040-001` — **Correct HealthKit semantics for Auto** — `CI_VALIDATED / PARTIAL`.
  - Auto starts with the current effective sport, never fake `.mixedCardio`.
  - New Watch-side `WatchAutoHealthReconciler` keeps the live workout untouched while recording, then only for genuinely mixed Auto sessions rewrites the saved HealthKit representation into separately typed segment workouts sharing the Watch Tracker session id.
  - It carries app-owned HR/energy/distance samples, workout events and route points into segment time windows.
  - Transaction rule: original workout is deleted only after every replacement succeeds; replacement objects are rolled back on failure. If route/workout is not durable yet, reconciliation waits/retries and preserves the original.
  - Single-sport Auto sessions are left untouched.
  - Remaining: real-device proof in Health/Fitness for Walk→Run→Walk and Cycle/mixed cases, including route, calories/HR association and failure fallback.

- `V040-002` — **Reject implausible GPS/speed spikes / trustworthy max speed** — `CI_VALIDATED`, hardware validation pending.
- `V040-003` — **Reliable elevation gain/loss** — `CI_VALIDATED`, hardware validation pending; barometer preferred, filtered GPS fallback.
- `V040-004` — **Fix zero gyroscope** — `CI_VALIDATED`, hardware validation pending; device-motion rotation rate preferred, raw gyro fallback, source logged.
- `V040-005` — **Bounded event/diagnostic logging** — `CI_VALIDATED`, hardware validation pending.
- `V040-006` — **Record Watch GPS for Watch/iPhone comparison** — `CI_VALIDATED`, hardware validation pending.
- `V040-007` — **Physically verify HealthKit workout + route + exact deletion** — `TODO physical test`.
- `V040-008` — **Deliberate Auto field tests** — `TODO physical test`: Walk→Run→Walk, separate Cycle, then mixed/multisport.

### Startup / live UI

- `V040-009` — **Remove redundant Watch badge obscuring iPhone map** — `CI_VALIDATED`, UX validation pending.
- `V040-010` — **Compact GPS / Watch / Health readiness UI** — `CI_VALIDATED`, UX validation pending.
- `V040-011` — **Stable startup values/placeholders** — `CI_VALIDATED / PARTIAL`, hardware validation pending.
- `V040-012` — **Real-time active calories on iPhone + Watch** — `CI_VALIDATED`, hardware validation pending; never invent legacy calories.
- `V040-013` — **Horizontal Watch live-data pages** — `CI_VALIDATED`, UX validation pending.

### Rich live/post-session metrics

- `V040-014` — **Cadence / steps / pedestrian pace where available** — `CI_VALIDATED / PARTIAL`; hardware quality/availability pending.
- `V040-015` — **Walking gait/balance/asymmetry/step length/double support** — `CI_VALIDATED / PARTIAL`; contextual Health data, not fake live sensors; hardware availability pending.
- `V040-016` — **Respiration-related data** — `CI_VALIDATED / PARTIAL`; contextual Health data only unless a separately labelled estimator is later built.
- `V040-017` — **Richer HR/running metrics** — `CI_VALIDATED / PARTIAL`; HR average/max + five relative zones/time-in-zone + contextual running metrics exist; hardware validation and pace/speed zones remain.
- `V040-018` — **Sensor availability/quality indicators** — `CI_VALIDATED / PARTIAL`; GPS accuracy, gyro source, Auto confidence/provenance and segment sample counts exist; unified quality score remains optional.

### Weather / effort context

- `V040-019` — **Persist environmental context outdoors** — `CI_VALIDATED`, network/hardware validation pending; Open-Meteo provider, coarse snapshots, temperature/apparent temperature/humidity/pressure/wind/gust/direction/code.
- `V040-020` — **Use weather to interpret effort** — `CI_VALIDATED / PARTIAL`; environmental summary + route-heading/headwind component exist; field validation/tuning pending. Never use wrist temperature as ambient.

### History / summaries

- `V040-021` — **Persistent iPhone history** — `PHYSICALLY_VALIDATED / PARTIAL`; first upgrade preserved baseline; new v0.4 session persistence/detail still needs physical validation.
- `V040-022` — **Proper post-activity summary** — `CI_VALIDATED / PARTIAL`; forced activity confirmation/correction, route/core metrics, pauses, HR zones, Auto provenance, segments, environment, Health context and technical trace exist; UX validation pending.
- `V040-023` — **Recent history on Watch** — `CI_VALIDATED`, sync/offline persistence hardware validation pending.
- `V040-024` — **Schema/build/algorithm provenance** — `CI_VALIDATED`, migration validation pending.
- `V040-025` — **Never purge history during normal update** — `PHYSICALLY_VALIDATED for first upgrade / PARTIAL`; revalidate future upgrades/Watch history.

### Auto-pause

- `V040-026` — **Optional auto-pause** — `CI_VALIDATED / PARTIAL`.
  - Watch owns execution; global master enable + per-sport Walk/Hike/Run/Cycle profiles, enable flags and pause dwell exist.
  - Resume dwell and thresholds are sport-aware; stationary + speed/cadence evidence used; manual/auto pauses distinct.
  - Remaining: field-tune thresholds/dwell and prove manual Pause precedence.

### Auto classification / hiking

- `V040-027` — **Conservative Auto Walk/Run/Cycle** — `CI_VALIDATED`, hardware transition tests pending.
- `V040-028` — **Hiking inference** — `CI_VALIDATED / PARTIAL`; conservative app inference from walking + sustained terrain/elevation, clearly not claimed as native Core Motion Hiking; field tuning pending.
- `V040-029` — **Expose Auto confidence/provenance** — `CI_VALIDATED / PARTIAL`; Watch live + iPhone summary/history distinguish Core Motion from Watch Tracker inference; UX validation pending.

### Multisport / triathlon / general mixed

- `V040-030` — **First-class session segments** — `CI_VALIDATED / PARTIAL`.
  - Durable segment boundaries, delayed Watch recovery, and per-segment active time/pause/distance/calories/D+/D-/HR/speed/cadence analysis exist.
  - New mixed-Auto HealthKit reconciliation maps the same master session id to semantically typed HealthKit segment workouts after STOP.
  - Remaining: physical disconnect/recovery and Health/Fitness verification.

- `V040-031` — **Manual triathlon in one HealthKit `swimBikeRun` session** — `CI_VALIDATED`, hardware validation pending.
- `V040-032` — **Automatic triathlon transitions** — `CI_VALIDATED / PARTIAL`; conservative candidates/dwell + manual controls remain; real swim/bike/run validation pending.
- `V040-033` — **General mixed outing in one Watch Tracker master session** — `CI_VALIDATED / PARTIAL`.
  - Internal master session and Auto segments exist.
  - HealthKit now has a post-STOP transactional mapping to separate correctly typed workouts for arbitrary mixed Auto (for example bike→walk→run→bike), rather than abusing triathlon children.
  - Remaining: physical proof that Health/Fitness shows correct segment workouts/routes and that failure preserves original data.

- `V040-034` — **Automatic mixed-sport transition detection** — `CI_VALIDATED / PARTIAL`.
  - Conservative Auto Walk/Run/Cycle/Hike transitions already drive first-class segments; the HealthKit mapping now follows those segments after STOP.
  - Remaining: dedicated field validation, false-positive tuning, explicit mixed-master manual override UX if needed.

## Additional accepted roadmap

- `V040-035` — automatic km/mile splits — `TODO`.
- `V040-036` — HR/pace/speed zones — `CI_VALIDATED / PARTIAL`; HR zones done, pace/speed zones pending.
- `V040-037` — configurable haptic alerts — `TODO`.
- `V040-038` — rolling pace/speed — `TODO`.
- `V040-039` — GPX/TCX/FIT export — `TODO`.
- `V040-040` — cross-session/baseline comparison — `TODO`.
- `V040-041` — unified sensor/data-quality score — `TODO`.
- `V040-042` — legacy-history HealthKit enrichment — `TODO`; only from confidently matched app-owned workouts, never guessed values.

## Definition of v0.4 done

Do not call v0.4 finished merely because it compiles. Completion requires all mandatory `V040-001`…`V040-034` to be physically validated or explicitly blocked by proven platform constraints with an accepted alternative; preserved baseline history; exact-SHA identity for physical builds; no authority/sync regression; HealthKit type/route/deletion checks; and a new extracted field corpus compared quantitatively with baseline `1789026745407`.

## Update rule

Move statuses only from evidence. CI is not physical validation.
