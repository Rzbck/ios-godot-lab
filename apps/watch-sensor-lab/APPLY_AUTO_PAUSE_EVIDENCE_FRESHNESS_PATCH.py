#!/usr/bin/env python3
"""Final Watch auto-pause evidence-freshness patch.

Runs after auto-pause fusion and auto-resume runtime integration. It fixes the
2026-09-15 field failure where a workout could never pause for two independent
reasons:
1. CMMotionActivity.startDate is the transition time, so an already-stationary
   state may begin before the workout and must not be used as callback freshness;
2. currentSpeedMps is filtered state and may remain frozen on the final moving
   value when no later usable speed sample updates it.

The patch keeps state semantics separate from sample freshness: pause uses the
arrival time of the current stationary classification, while GPS speed only
vetoes pause for a short window after the speed filter was actually updated.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WATCH = ROOT / "watch/Sources/SensorModel.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


watch = WATCH.read_text(encoding="utf-8")

# Track observation/sample clocks separately from the existing semantic state.
watch = replace_once_or_present(
    watch,
    '''    private var lastAutoResumeAt = Date.distantPast // AUTO_RESUME_REPAUSE_HYSTERESIS_STATE
''',
    '''    private var lastAutoResumeAt = Date.distantPast // AUTO_RESUME_REPAUSE_HYSTERESIS_STATE
    private var lastAutoPauseMotionObservationAt = Date.distantPast // AUTO_PAUSE_MOTION_OBSERVATION_CLOCK
    private var lastAutoPauseSpeedEvidenceAt = Date.distantPast // AUTO_PAUSE_SPEED_EVIDENCE_CLOCK
''',
    "// AUTO_PAUSE_MOTION_OBSERVATION_CLOCK",
    "watch pause evidence clocks",
)

watch = replace_once_or_present(
    watch,
    '''            lastAutoResumeAt = .distantPast // AUTO_RESUME_RESET_REPAUSE_HYSTERESIS
            resetPresentationData(keepActivity: true)
''',
    '''            lastAutoResumeAt = .distantPast // AUTO_RESUME_RESET_REPAUSE_HYSTERESIS
            lastAutoPauseMotionObservationAt = .distantPast // AUTO_PAUSE_RESET_MOTION_OBSERVATION
            lastAutoPauseSpeedEvidenceAt = .distantPast // AUTO_PAUSE_RESET_SPEED_EVIDENCE
            resetPresentationData(keepActivity: true)
''',
    "// AUTO_PAUSE_RESET_MOTION_OBSERVATION",
    "watch reset pause evidence clocks",
)

# startDate describes when the classified activity began. For a user who was
# already still before pressing Start, that can legitimately predate the workout.
# Capture callback arrival separately for live stop-detection freshness.
watch = replace_once_or_present(
    watch,
    '''            guard activity.confidence != .low else { return }
            // Core Motion can deliver a delayed classification. Its original
''',
    '''            guard activity.confidence != .low else { return }
            self.lastAutoPauseMotionObservationAt = Date() // AUTO_PAUSE_MOTION_OBSERVATION_RECEIVED
            // Core Motion can deliver a delayed classification. Its original
''',
    "// AUTO_PAUSE_MOTION_OBSERVATION_RECEIVED",
    "watch capture live motion observation arrival",
)

# Stamp speed freshness only when the speed filter itself changes. A later GPS
# callback with unusable speed must not keep an old moving value fresh forever.
watch = replace_once_or_present(
    watch,
    '''                currentSpeedMps =
                    currentSpeedMps == 0
                        ? clipped
                        : currentSpeedMps * 0.80 + clipped * 0.20
''',
    '''                currentSpeedMps =
                    currentSpeedMps == 0
                        ? clipped
                        : currentSpeedMps * 0.80 + clipped * 0.20
                lastAutoPauseSpeedEvidenceAt = location.timestamp // AUTO_PAUSE_SPEED_EVIDENCE_MOVING
''',
    "// AUTO_PAUSE_SPEED_EVIDENCE_MOVING",
    "watch stamp accepted moving speed evidence",
)

watch = replace_once_or_present(
    watch,
    '''                    currentSpeedMps =
                        currentSpeedMps * 0.55
                        + min(nativeSpeed, 1.5) * 0.45

                    if currentSpeedMps < 0.35 {
''',
    '''                    currentSpeedMps =
                        currentSpeedMps * 0.55
                        + min(nativeSpeed, 1.5) * 0.45
                    lastAutoPauseSpeedEvidenceAt = location.timestamp // AUTO_PAUSE_SPEED_EVIDENCE_LOW_MOTION

                    if currentSpeedMps < 0.35 {
''',
    "// AUTO_PAUSE_SPEED_EVIDENCE_LOW_MOTION",
    "watch stamp low-motion speed evidence",
)

# Stop detection needs a longer-lived current-state observation than resume
# evidence. Its window must outlive the pause dwell. Speed has the opposite
# semantics: only a recently updated value may veto a stationary classification.
watch = replace_once_or_present(
    watch,
    '''    private var freshMotionWasStationary: Bool {
        Date().timeIntervalSince(lastMotionEvidenceAt) <= autoEvidenceFreshness && lastMotionWasStationary
    }

    private var freshMotionCandidate: ActivityKind? {
''',
    '''    private var freshMotionWasStationary: Bool {
        Date().timeIntervalSince(lastMotionEvidenceAt) <= autoEvidenceFreshness && lastMotionWasStationary
    }

    private var freshAutoPauseMotionWasStationary: Bool { // AUTO_PAUSE_STATE_FRESHNESS
        let age = Date().timeIntervalSince(lastAutoPauseMotionObservationAt)
        return age >= 0
            && age <= WatchAutoPauseSettings.stationaryEvidenceFreshness(for: displayActivity)
            && lastMotionWasStationary
    }

    private var autoPauseSpeedEvidenceAge: TimeInterval { // AUTO_PAUSE_SPEED_FRESHNESS
        Date().timeIntervalSince(lastAutoPauseSpeedEvidenceAt)
    }

    private var autoPauseSpeedEvidenceFresh: Bool {
        let age = autoPauseSpeedEvidenceAge
        return age >= 0
            && age <= WatchAutoPauseSettings.speedEvidenceFreshness(for: displayActivity)
    }

    private var freshMotionCandidate: ActivityKind? {
''',
    "// AUTO_PAUSE_STATE_FRESHNESS",
    "watch derive pause-specific evidence freshness",
)

# Initial and periodic staging must use pause-specific state/sample freshness.
watch = replace_once_or_present(
    watch,
    '''            activity: displayActivity,
            stationary: freshMotionWasStationary,
            speedMps: currentSpeedMps,
            cadenceSPM: freshCadenceSPM
''',
    '''            activity: displayActivity,
            stationary: freshAutoPauseMotionWasStationary,
            speedMps: currentSpeedMps,
            speedFresh: autoPauseSpeedEvidenceFresh,
            cadenceSPM: freshCadenceSPM
''',
    "speedFresh: autoPauseSpeedEvidenceFresh",
    "watch stage pause uses fresh speed veto",
)

# Dwell confirmation must re-evaluate the same evidence semantics.
watch = replace_once_or_present(
    watch,
    '''                    activity: self.displayActivity,
                    stationary: self.freshMotionWasStationary,
                    speedMps: self.currentSpeedMps,
                    cadenceSPM: self.freshCadenceSPM
''',
    '''                    activity: self.displayActivity,
                    stationary: self.freshAutoPauseMotionWasStationary,
                    speedMps: self.currentSpeedMps,
                    speedFresh: self.autoPauseSpeedEvidenceFresh,
                    cadenceSPM: self.freshCadenceSPM
''',
    "speedFresh: self.autoPauseSpeedEvidenceFresh",
    "watch confirm pause uses fresh speed veto",
)

# Keep enough evidence in the candidate event to diagnose the next field run.
watch = replace_once_or_present(
    watch,
    '''            "speed_mps": currentSpeedMps,
            "cadence_spm": freshCadenceSPM,
            "motion_stationary": freshMotionWasStationary,
''',
    '''            "speed_mps": currentSpeedMps,
            "speed_fresh": autoPauseSpeedEvidenceFresh,
            "speed_age_s": autoPauseSpeedEvidenceAge.isFinite ? autoPauseSpeedEvidenceAge : -1,
            "cadence_spm": freshCadenceSPM,
            "motion_stationary": freshAutoPauseMotionWasStationary,
            "motion_observation_age_s": Date().timeIntervalSince(lastAutoPauseMotionObservationAt),
''',
    '"speed_fresh": autoPauseSpeedEvidenceFresh',
    "watch pause candidate freshness telemetry",
)

for token in [
    "// AUTO_PAUSE_MOTION_OBSERVATION_CLOCK",
    "// AUTO_PAUSE_SPEED_EVIDENCE_CLOCK",
    "// AUTO_PAUSE_RESET_MOTION_OBSERVATION",
    "// AUTO_PAUSE_RESET_SPEED_EVIDENCE",
    "// AUTO_PAUSE_MOTION_OBSERVATION_RECEIVED",
    "// AUTO_PAUSE_SPEED_EVIDENCE_MOVING",
    "// AUTO_PAUSE_SPEED_EVIDENCE_LOW_MOTION",
    "// AUTO_PAUSE_STATE_FRESHNESS",
    "// AUTO_PAUSE_SPEED_FRESHNESS",
    "speedFresh: autoPauseSpeedEvidenceFresh",
    "speedFresh: self.autoPauseSpeedEvidenceFresh",
    '"speed_fresh": autoPauseSpeedEvidenceFresh',
]:
    if token not in watch:
        raise SystemExit(f"auto-pause evidence freshness missing token: {token}")

for marker in [
    "// AUTO_PAUSE_MOTION_OBSERVATION_CLOCK",
    "// AUTO_PAUSE_SPEED_EVIDENCE_CLOCK",
    "// AUTO_PAUSE_RESET_MOTION_OBSERVATION",
    "// AUTO_PAUSE_RESET_SPEED_EVIDENCE",
    "// AUTO_PAUSE_MOTION_OBSERVATION_RECEIVED",
    "// AUTO_PAUSE_SPEED_EVIDENCE_MOVING",
    "// AUTO_PAUSE_SPEED_EVIDENCE_LOW_MOTION",
    "// AUTO_PAUSE_STATE_FRESHNESS",
    "// AUTO_PAUSE_SPEED_FRESHNESS",
]:
    if watch.count(marker) != 1:
        raise SystemExit(f"auto-pause evidence freshness duplicated marker: {marker}")

WATCH.write_text(watch, encoding="utf-8")
print("AUTO PAUSE EVIDENCE FRESHNESS PATCH: OK")
