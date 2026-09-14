import CoreMotion
import Foundation

struct WatchAutoDecision: Equatable {
    let activity: ActivityKind
    let confidence: String
    let provenance: String
    let dwellSeconds: TimeInterval
}

enum WatchAutoPolicy {
    static func decision(
        from motion: CMMotionActivity,
        elapsedSeconds: TimeInterval,
        distanceMeters: Double,
        elevationGainMeters: Double,
        elevationLossMeters: Double,
        speedMps: Double = 0,
        cadenceSPM: Double = 0
    ) -> WatchAutoDecision? {
        // Keep reconciliation lifecycle binding at the platform boundary.
        // Classification itself is delegated to the pure shared policy so CI
        // can replay the exact same rules without physical motion.
        WatchAutoHealthReconciler.shared.bind(to: SensorModel.shared)

        _ = elapsedSeconds
        _ = distanceMeters
        _ = elevationGainMeters
        _ = elevationLossMeters

        let evidence = TrackerMotionEvidence(
            walking: motion.walking,
            running: motion.running,
            cycling: motion.cycling,
            stationary: motion.stationary,
            confidence: motionConfidence(motion.confidence)
        )

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
            dwellSeconds: decision.dwellSeconds
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

    static func shouldStageResume(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?
    ) -> Bool {
        TrackerAutoPolicy.shouldStageResume(
            activity: activity,
            enabled: WatchAutoPauseSettings.isEnabled(for: activity),
            stationary: stationary,
            speedMps: speedMps,
            cadenceSPM: cadenceSPM,
            motionCandidate: motionCandidate
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
