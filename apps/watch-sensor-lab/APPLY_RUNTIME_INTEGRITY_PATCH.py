#!/usr/bin/env python3
"""Build-time runtime-integrity patch for field regressions found on 2026-09-14.

This candidate fixes two proven product failures without changing the historical
recovery entry point:

1. A newly finished workout could trap the iPhone summary with a disabled
   `Terminé` button after the legacy post-hoc activity picker was intentionally
   retired. Final activity confirmation already happens before STOP; the summary
   must therefore be dismissible even when no ActivityReviewRecord exists.
2. Auto mode can start HealthKit with provisional `walking`, then finish as a
   user-confirmed single sport (for example cycling). The existing Watch-side
   reconciler already knows how to rebuild a provisional Auto container after
   HealthKit is durable, but it was only bound from the motion-classification
   path and a final force-single choice did not collapse its plan. We bind it for
   every Auto workout and make the explicit final choice authoritative for the
   reconciliation plan.

The original HealthKit workout remains untouched until the existing reconciler
has created replacement objects. This patch does not relax any historical V4
recovery safety gate.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WATCH_MODEL = ROOT / "watch/Sources/SensorModel.swift"
WATCH_RECONCILER = ROOT / "watch/Sources/WatchAutoHealthReconciler.swift"
PHONE_SUMMARY = ROOT / "iphone/Sources/PostActivitySummaryView.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


watch = WATCH_MODEL.read_text(encoding="utf-8")
reconciler = WATCH_RECONCILER.read_text(encoding="utf-8")
phone_summary = PHONE_SUMMARY.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# iPhone post-workout summary: do not deadlock after the legacy historical
# correction control was retired. The actual Auto final choice is made before
# STOP in PhoneFinishActivityReview / WatchFinishActivityReview.
# ---------------------------------------------------------------------------
phone_summary = replace_once_or_present(
    phone_summary,
    "    private var activityConfirmed: Bool { review != nil }\n",
    "    // Final activity confirmation is a pre-STOP workflow decision.\n"
    "    // This post-workout screen is read-only and must never trap the user\n"
    "    // waiting for a legacy ActivityReviewRecord that it no longer creates.\n"
    "    private var activityConfirmed: Bool { true }\n",
    "private var activityConfirmed: Bool { true }",
    "phone summary dismissal gate",
)

phone_summary = replace_once_or_present(
    phone_summary,
    "                    ActivityReviewCard(summary: summary, requiresConfirmation: true) { saved in\n",
    "                    ActivityReviewCard(summary: summary, requiresConfirmation: false) { saved in\n",
    "ActivityReviewCard(summary: summary, requiresConfirmation: false)",
    "phone summary read-only review card",
)

# ---------------------------------------------------------------------------
# Watch Auto reconciliation lifecycle: bind for every Auto workout, not only
# after Core Motion happened to emit a classifiable sample.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''            phase = .active
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
            if selectedActivity.isAutomatic {
                automaticActivityStartedAt = startedAt ?? Date()
            }
''',
    '''            phase = .active
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
            if selectedActivity.isAutomatic {
                // Auto HealthKit reconciliation is lifecycle-critical. Binding
                // cannot depend on Core Motion producing a later decision.
                WatchAutoHealthReconciler.shared.bind(to: self)
                automaticActivityStartedAt = startedAt ?? Date()
            }
''',
    "Binding cannot depend on Core Motion",
    "watch Auto reconciler lifecycle binding",
)

# Explicit force-single confirmation must also collapse the reconciliation plan
# to that one sport. Otherwise the provisional `walking` segment survives into
# HealthKit even though the user confirmed cycling/running/etc.
watch = replace_once_or_present(
    watch,
    '''        if selectedActivity.isAutomatic,
           let confirmedActivity,
           !confirmedActivity.isAutomatic {

            closeAutomaticActivityAccounting(at: Date())

            let previous = effectiveActivity
            effectiveActivity = confirmedActivity
''',
    '''        if selectedActivity.isAutomatic,
           let confirmedActivity,
           !confirmedActivity.isAutomatic {

            let confirmationDate = Date()
            WatchAutoHealthReconciler.shared.forceSingleActivity(
                sessionID: sessionID,
                activity: confirmedActivity,
                sessionStartedAt: startedAt ?? confirmationDate
            )
            closeAutomaticActivityAccounting(at: confirmationDate)

            let previous = effectiveActivity
            effectiveActivity = confirmedActivity
''',
    "WatchAutoHealthReconciler.shared.forceSingleActivity(",
    "watch final force-single reconciliation",
)

# Reconciler API used above. It preserves the real session start and replaces
# the in-memory plan with exactly one confirmed activity. Normal STOP handling
# then closes/enqueues the plan and existing retry logic waits for the original
# HealthKit workout + route to become durable before replacement.
reconciler = replace_once_or_present(
    reconciler,
    "    func repairHistoricalActivity(\n",
    '''    func forceSingleActivity(
        sessionID: String,
        activity: ActivityKind,
        sessionStartedAt: Date
    ) {
        guard !sessionID.isEmpty, !activity.isAutomatic else { return }

        let start: Date
        var routeExpected = false

        if let plan = activePlan, plan.sessionID == sessionID {
            start = plan.segments.map(\\.startedAt).min() ?? sessionStartedAt
            routeExpected = plan.routeExpected
        } else {
            // Defensive fallback. Normal Auto sessions are bound at start, but
            // retaining the true session start avoids a zero-length plan if a
            // lifecycle callback was missed.
            start = sessionStartedAt
        }

        activePlan = Plan(
            sessionID: sessionID,
            segments: [
                Segment(
                    activity: activity,
                    startedAt: start,
                    endedAt: nil
                )
            ],
            stoppedAt: nil,
            routeExpected: routeExpected
        )

        emit(
            event: "health_auto_force_single_selected",
            sessionID: sessionID,
            payload: [
                "activity": activity.rawValue,
                "plan_start": start.timeIntervalSince1970,
            ]
        )
    }

    func repairHistoricalActivity(
''',
    "func forceSingleActivity(",
    "watch force-single plan API",
)

PHONE_SUMMARY.write_text(phone_summary, encoding="utf-8")
WATCH_MODEL.write_text(watch, encoding="utf-8")
WATCH_RECONCILER.write_text(reconciler, encoding="utf-8")

# Fail closed: a candidate build is rejected if any runtime-critical primitive
# is missing after patch application.
phone_after = PHONE_SUMMARY.read_text(encoding="utf-8")
watch_after = WATCH_MODEL.read_text(encoding="utf-8")
reconciler_after = WATCH_RECONCILER.read_text(encoding="utf-8")

for token in [
    "private var activityConfirmed: Bool { true }",
    "ActivityReviewCard(summary: summary, requiresConfirmation: false)",
]:
    if token not in phone_after:
        raise SystemExit(f"phone finish-integrity token missing: {token}")

for token in [
    "WatchAutoHealthReconciler.shared.bind(to: self)",
    "WatchAutoHealthReconciler.shared.forceSingleActivity(",
]:
    if token not in watch_after:
        raise SystemExit(f"watch finish-integrity token missing: {token}")

for token in [
    "func forceSingleActivity(",
    'event: "health_auto_force_single_selected"',
]:
    if token not in reconciler_after:
        raise SystemExit(f"reconciler finish-integrity token missing: {token}")

print("RUNTIME INTEGRITY BUILD PATCH: OK")
