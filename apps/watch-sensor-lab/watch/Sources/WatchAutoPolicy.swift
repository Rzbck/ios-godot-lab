import CoreMotion
import Foundation

struct WatchAutoDecision: Equatable {
    let activity: ActivityKind
    let confidence: String
    let provenance: String
    let dwellSeconds: TimeInterval
}

enum WatchAutoPolicy {
    private static let maximumReactiveDwell: TimeInterval = 2.5

    static func decision(
        from motion: CMMotionActivity,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        elevationGainMeters: Double,
        elevationLossMeters: Double,
        speedMps: Double = 0,
        cadenceSPM: Double = 0
    ) -> WatchAutoDecision? {
        _ = elapsedSeconds
        _ = distanceMeters
        _ = elevationGainMeters
        _ = elevationLossMeters

        return decision(
            from: TrackerMotionEvidence(
                walking: motion.walking,
                running: motion.running,
                cycling: motion.cycling,
                stationary: motion.stationary,
                confidence: motionConfidence(motion.confidence)
            ),
            speedMps: speedMps,
            cadenceSPM: cadenceSPM
        )
    }

    static func decision(
        from evidence: TrackerMotionEvidence,
        speedMps: Double,
        cadenceSPM: Double
    ) -> WatchAutoDecision? {
        WatchAutoHealthReconciler.shared.bind(to: SensorModel.shared)

        guard let decision = TrackerAutoPolicy.decision(
            from: evidence,
            speedMps: speedMps,
            cadenceSPM: cadenceSPM
        ) else {
            return nil
        }

        return WatchAutoDecision(
            activity: decision.activity,
            confidence: decision.confidence,
            provenance: decision.provenance,
            dwellSeconds: min(decision.dwellSeconds, maximumReactiveDwell)
        )
    }

    static func shouldStagePause(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double
    ) -> Bool {
        TrackerAutoPolicy.shouldStagePause(
            activity: activity,
            enabled: WatchAutoPauseSettings.isEnabled(for: activity),
            stationary: stationary,
            speedMps: speedMps,
            cadenceSPM: cadenceSPM
        )
    }

    static func pauseDwell(for activity: ActivityKind) -> TimeInterval {
        WatchAutoPauseSettings.pauseDwell(for: activity)
    }

    static func resumeDecision(
        activity: ActivityKind,
        evidence: TrackerAutoResumeEvidence
    ) -> TrackerAutoResumeDecision {
        TrackerAutoPolicy.resumeDecision(
            activity: activity,
            enabled: WatchAutoPauseSettings.isEnabled(for: activity),
            evidence: evidence
        )
    }

    static func shouldStageResume(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?,
        gpsEvidenceConfirmed: Bool = false,
        motionEvidenceFresh: Bool = false,
        cadenceEvidenceFresh: Bool = false
    ) -> Bool {
        TrackerAutoPolicy.shouldStageResume(
            activity: activity,
            enabled: WatchAutoPauseSettings.isEnabled(for: activity),
            stationary: stationary,
            speedMps: speedMps,
            cadenceSPM: cadenceSPM,
            motionCandidate: motionCandidate,
            gpsEvidenceConfirmed: gpsEvidenceConfirmed,
            motionEvidenceFresh: motionEvidenceFresh,
            cadenceEvidenceFresh: cadenceEvidenceFresh
        )
    }

    static func shouldStageResume(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?,
        gpsEvidenceConfirmed: Bool,
        motionEvidenceFresh: Bool,
        cadenceEvidenceFresh: Bool
    ) -> Bool {
        TrackerAutoPolicy.shouldStageResume(
            activity: activity,
            enabled: WatchAutoPauseSettings.isEnabled(for: activity),
            stationary: stationary,
            speedMps: speedMps,
            cadenceSPM: cadenceSPM,
            motionCandidate: motionCandidate,
            gpsEvidenceConfirmed: gpsEvidenceConfirmed,
            motionEvidenceFresh: motionEvidenceFresh,
            cadenceEvidenceFresh: cadenceEvidenceFresh
        )
    }

    static func resumeDwell(for activity: ActivityKind) -> TimeInterval {
        WatchAutoPauseSettings.resumeDwell(for: activity)
    }

    static func confidenceLabel(_ confidence: CMMotionActivityConfidence) -> String {
        motionConfidence(confidence).label
    }

    private static func motionConfidence(
        _ confidence: CMMotionActivityConfidence
    ) -> TrackerMotionConfidence {
        switch confidence {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        @unknown default: return .low
        }
    }
}
