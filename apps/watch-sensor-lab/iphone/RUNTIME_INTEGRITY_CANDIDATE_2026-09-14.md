# Runtime integrity candidate — 2026-09-14

## Goal

Repair field regressions proven by a real Watch-started Auto cycling workout:

- Auto-pause did not trigger as expected; do not alter thresholds until the exact session telemetry is inspected.
- iPhone post-workout summary could not be dismissed because `Terminé` stayed disabled.
- The user confirmed Cycling at finish and the local Tracker summary showed Cycling, while Apple Fitness stored the HealthKit workout as Outdoor Walking.

## Repository / branch

- Repository: `Rzbck/ios-godot-lab`
- App: `apps/watch-sensor-lab`
- Branch: `fix/watch-runtime-integrity-20260914`
- Base: `d74f1231f152fef7d65961797132bc67fa9fdcd5`

## Historical audit

- `fix/watch-auto-run-integrity-20260911` at `b355cca10bc173536f61972914710cc6d30e4c07` is an ancestor of the base candidate.
- That older state still had a post-workout activity picker and called the safe Watch-side historical correction transaction.
- Commit `18a39b6cc84ce5e85523b80e396b782b1d83c548` (`fix(tracker): retire legacy historical correction controls`) intentionally removed those controls while the summary dismissal gate remained dependent on an `ActivityReviewRecord`. This created the post-workout deadlock.
- Auto-pause safety is currently applied at build time by `SESSION_SYNC_PATCH.py -> APPLY_AUTO_PAUSE_SAFETY_PATCH.py`; the checked-in `SensorModel.swift` intentionally still contains the pre-patch implementation. Do not infer the installed runtime from the raw Swift file without accounting for the build-time patch chain.
- The Watch Auto HealthKit reconciler already contains retry logic and supports rebuilding a provisional `walking` Auto container as the real single sport, but it was bound from the Core Motion decision path and did not receive an explicit force-single final plan.

## Candidate changes

`APPLY_RUNTIME_INTEGRITY_PATCH.py` is chained after the existing terminal-sync patch. It:

1. makes the read-only post-workout iPhone summary dismissible without requiring a legacy `ActivityReviewRecord`;
2. binds `WatchAutoHealthReconciler` for every Auto workout lifecycle instead of waiting for a Core Motion decision;
3. makes an explicit final `forceSingleActivity` confirmation collapse the reconciliation plan to exactly the confirmed sport while retaining the real session start;
4. relies on the existing reconciler retry path to wait for the original HealthKit workout/route to become durable before rebuilding the semantic container.

## Not validated yet

- CI/build result for this branch.
- Physical iPhone + Apple Watch behavior.
- The exact cause of the 2026-09-14 auto-pause non-trigger.
- Preservation/rendering of the affected 10:21 workout after a targeted Walking -> Cycling repair.

## Safety constraints

- Do not delete the affected HealthKit workout before read-only audit.
- Do not change auto-pause thresholds until telemetry proves the failure mode.
- Do not merge to `main` or promote a release without explicit user approval.
- Keep historical V4 recovery safety gates unchanged.

## Next exact steps

1. Run CI for this branch and fix any compile/static-test issue before producing an IPA.
2. When the user is back at the Windows PC, read the installed build SHA and `last_summary`; verify the candidate session by its ~5.90 km / ~22 min signature, then run `WSL.ps1 recovery <session_id>` and recent logs.
3. Audit the affected normal HealthKit workout before any targeted type correction.
4. Use the telemetry to determine why auto-pause did not stage/trigger and then fix that cause separately.
