#!/usr/bin/env python3
"""Fuse raw Watch inertial stillness into auto-pause and make Auto HealthKit-safe.

Field session 1789490785613 showed a long physical stop where Watch cadence was
0, step count was frozen and Watch GPS speed was near zero, while
CMMotionActivity continued reporting walking. Requiring `.stationary` therefore
made auto-pause impossible. This patch adds a conservative rolling inertial
stillness vote from the Watch accelerometer/gyroscope; sport-specific speed and
cadence remain vetoes and the existing dwell/hysteresis remain unchanged.

The same field session was saved by HealthKit as mixedCardio. Auto is an app
selection mode, not a real HealthKit sport, so automatic now uses walking as a
safe provisional HealthKit type and the Watch defensively normalizes any legacy
mixedCardio configuration before starting the HKWorkoutSession. Existing Auto
health reconciliation remains responsible for replacing a provisional workout
when the detected final/segmented activity differs.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WATCH = ROOT / "watch/Sources/SensorModel.swift"
SHARED = ROOT / "Shared/TrackerShared.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


watch = WATCH.read_text(encoding="utf-8")
shared = SHARED.read_text(encoding="utf-8")

# Auto is not a HealthKit workout category. Never serialize the selection mode
# itself as mixedCardio; use the existing walking initial effective activity as
# a provisional type until Auto reconciliation confirms the real sport.
shared = replace_once_or_present(
    shared,
    "        case .automatic: return .mixedCardio\n",
    "        case .automatic: return .walking // AUTO_HEALTHKIT_SAFE_PLACEHOLDER\n",
    "// AUTO_HEALTHKIT_SAFE_PLACEHOLDER",
    "shared Auto HealthKit placeholder",
)

# Rolling inertial state. It is only one stillness vote; speed/cadence and the
# normal pause dwell still have to agree before pauseCore can run.
watch = replace_once_or_present(
    watch,
    "    private var lastAutoPauseSpeedEvidenceAt = Date.distantPast // AUTO_PAUSE_SPEED_EVIDENCE_CLOCK\n",
    """    private var lastAutoPauseSpeedEvidenceAt = Date.distantPast // AUTO_PAUSE_SPEED_EVIDENCE_CLOCK
    private var inertialAutoPauseWindow: [(at: Date, quiet: Bool)] = [] // AUTO_PAUSE_INERTIAL_WINDOW_STATE
    private var lastInertialAutoPauseSampleAt = Date.distantPast
    private var inertialAutoPauseStill = false
    private var inertialAutoPauseQuietFraction = 0.0
""",
    "// AUTO_PAUSE_INERTIAL_WINDOW_STATE",
    "watch inertial pause state",
)

watch = replace_once_or_present(
    watch,
    """            lastAutoPauseSpeedEvidenceAt = .distantPast // AUTO_PAUSE_RESET_SPEED_EVIDENCE
            resetPresentationData(keepActivity: true)
""",
    """            lastAutoPauseSpeedEvidenceAt = .distantPast // AUTO_PAUSE_RESET_SPEED_EVIDENCE
            inertialAutoPauseWindow.removeAll(keepingCapacity: true) // AUTO_PAUSE_RESET_INERTIAL_WINDOW
            lastInertialAutoPauseSampleAt = .distantPast
            inertialAutoPauseStill = false
            inertialAutoPauseQuietFraction = 0
            resetPresentationData(keepActivity: true)
""",
    "// AUTO_PAUSE_RESET_INERTIAL_WINDOW",
    "watch reset inertial pause state",
)

# Raw Watch motion is the fallback source because the field trace proves the
# high-level classifier can remain walking during a real stop.
watch = replace_once_or_present(
    watch,
    """            self.gyroZ = frame.gyroZ
            self.gyroSource = frame.gyroSource
            self.sendMotionIfNeeded()
""",
    """            self.gyroZ = frame.gyroZ
            self.gyroSource = frame.gyroSource
            self.updateInertialAutoPauseEvidence( // AUTO_PAUSE_INERTIAL_SAMPLE
                accelX: frame.accelX,
                accelY: frame.accelY,
                accelZ: frame.accelZ,
                gyroX: frame.gyroX,
                gyroY: frame.gyroY,
                gyroZ: frame.gyroZ
            )
            self.sendMotionIfNeeded()
""",
    "// AUTO_PAUSE_INERTIAL_SAMPLE",
    "watch feed inertial pause detector",
)

watch = replace_once_or_present(
    watch,
    """    private func startMotion() {
""",
    """    private var freshInertialAutoPauseStill: Bool { // AUTO_PAUSE_INERTIAL_FRESHNESS
        let age = Date().timeIntervalSince(lastInertialAutoPauseSampleAt)
        return age >= 0
            && age <= TrackerInertialStillnessPolicy.sampleFreshness
            && inertialAutoPauseStill
    }

    private func updateInertialAutoPauseEvidence(
        accelX: Double,
        accelY: Double,
        accelZ: Double,
        gyroX: Double,
        gyroY: Double,
        gyroZ: Double
    ) {
        let now = Date()
        let quiet = TrackerInertialStillnessPolicy.isQuietSample(
            accelX: accelX,
            accelY: accelY,
            accelZ: accelZ,
            gyroX: gyroX,
            gyroY: gyroY,
            gyroZ: gyroZ
        )

        inertialAutoPauseWindow.append((at: now, quiet: quiet))
        inertialAutoPauseWindow.removeAll {
            now.timeIntervalSince($0.at) > TrackerInertialStillnessPolicy.windowDuration
        }
        lastInertialAutoPauseSampleAt = now

        guard let first = inertialAutoPauseWindow.first else {
            inertialAutoPauseStill = false
            inertialAutoPauseQuietFraction = 0
            return
        }

        let quietCount = inertialAutoPauseWindow.reduce(into: 0) { total, sample in
            if sample.quiet { total += 1 }
        }
        let totalCount = inertialAutoPauseWindow.count
        inertialAutoPauseQuietFraction = totalCount > 0
            ? Double(quietCount) / Double(totalCount)
            : 0
        inertialAutoPauseStill = TrackerInertialStillnessPolicy.isStill(
            windowCoverage: now.timeIntervalSince(first.at),
            quietSamples: quietCount,
            totalSamples: totalCount
        )
    }

    private func startMotion() {
""",
    "// AUTO_PAUSE_INERTIAL_FRESHNESS",
    "watch inertial pause detector",
)

# Fuse the high-level classifier with raw inertial evidence. This preserves all
# existing sport-specific speed/cadence vetoes and pause dwell logic.
watch = replace_once_or_present(
    watch,
    """            activity: displayActivity,
            stationary: freshAutoPauseMotionWasStationary,
            speedMps: currentSpeedMps,
""",
    """            activity: displayActivity,
            stationary: freshAutoPauseMotionWasStationary || freshInertialAutoPauseStill, // AUTO_PAUSE_FUSED_STILLNESS_STAGE
            speedMps: currentSpeedMps,
""",
    "// AUTO_PAUSE_FUSED_STILLNESS_STAGE",
    "watch stage pause fused stillness",
)

watch = replace_once_or_present(
    watch,
    """                    activity: self.displayActivity,
                    stationary: self.freshAutoPauseMotionWasStationary,
                    speedMps: self.currentSpeedMps,
""",
    """                    activity: self.displayActivity,
                    stationary: self.freshAutoPauseMotionWasStationary || self.freshInertialAutoPauseStill, // AUTO_PAUSE_FUSED_STILLNESS_CONFIRM
                    speedMps: self.currentSpeedMps,
""",
    "// AUTO_PAUSE_FUSED_STILLNESS_CONFIRM",
    "watch confirm pause fused stillness",
)

# Expose exactly which stillness source armed a candidate in the next field run.
watch = replace_once_or_present(
    watch,
    """            \"motion_stationary\": freshAutoPauseMotionWasStationary,
            \"motion_observation_age_s\": Date().timeIntervalSince(lastAutoPauseMotionObservationAt),
""",
    """            \"motion_stationary\": freshAutoPauseMotionWasStationary,
            \"motion_observation_age_s\": Date().timeIntervalSince(lastAutoPauseMotionObservationAt),
            \"inertial_still\": freshInertialAutoPauseStill, // AUTO_PAUSE_INERTIAL_TELEMETRY
            \"inertial_quiet_fraction\": inertialAutoPauseQuietFraction,
            \"stillness_source\": freshAutoPauseMotionWasStationary
                ? \"core_motion_stationary\"
                : (freshInertialAutoPauseStill ? \"watch_inertial\" : \"none\"),
""",
    "// AUTO_PAUSE_INERTIAL_TELEMETRY",
    "watch pause candidate inertial telemetry",
)

# Defensive normalization: even if an older iPhone/system launch hands the
# Watch a mixedCardio configuration, Auto must start from the real provisional
# effective sport instead of saving a fake mixed-cardio workout.
watch = replace_once_or_present(
    watch,
    """        }()

        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: config.activityType) {
""",
    """        }()

        if selectedActivity.isAutomatic && config.activityType == .mixedCardio { // AUTO_HEALTHKIT_NORMALIZE_INCOMING_CONFIG
            config.activityType = effectiveActivity.healthKitType
            config.locationType = .outdoor
        }

        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: config.activityType) {
""",
    "// AUTO_HEALTHKIT_NORMALIZE_INCOMING_CONFIG",
    "watch normalize incoming Auto HealthKit configuration",
)

for token in [
    "// AUTO_HEALTHKIT_SAFE_PLACEHOLDER",
    "// AUTO_PAUSE_INERTIAL_WINDOW_STATE",
    "// AUTO_PAUSE_RESET_INERTIAL_WINDOW",
    "// AUTO_PAUSE_INERTIAL_SAMPLE",
    "// AUTO_PAUSE_INERTIAL_FRESHNESS",
    "// AUTO_PAUSE_FUSED_STILLNESS_STAGE",
    "// AUTO_PAUSE_FUSED_STILLNESS_CONFIRM",
    "// AUTO_PAUSE_INERTIAL_TELEMETRY",
    "// AUTO_HEALTHKIT_NORMALIZE_INCOMING_CONFIG",
]:
    combined = shared + "\n" + watch
    if token not in combined:
        raise SystemExit(f"inertial/HealthKit patch missing token: {token}")

for marker in [
    "// AUTO_HEALTHKIT_SAFE_PLACEHOLDER",
    "// AUTO_PAUSE_INERTIAL_WINDOW_STATE",
    "// AUTO_PAUSE_RESET_INERTIAL_WINDOW",
    "// AUTO_PAUSE_INERTIAL_SAMPLE",
    "// AUTO_PAUSE_INERTIAL_FRESHNESS",
    "// AUTO_PAUSE_FUSED_STILLNESS_STAGE",
    "// AUTO_PAUSE_FUSED_STILLNESS_CONFIRM",
    "// AUTO_PAUSE_INERTIAL_TELEMETRY",
    "// AUTO_HEALTHKIT_NORMALIZE_INCOMING_CONFIG",
]:
    combined = shared + "\n" + watch
    if combined.count(marker) != 1:
        raise SystemExit(f"inertial/HealthKit patch duplicated marker: {marker}")

SHARED.write_text(shared, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
print("AUTO PAUSE INERTIAL + HEALTHKIT PATCH: OK")
