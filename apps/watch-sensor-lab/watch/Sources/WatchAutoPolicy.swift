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
        elevationLossMeters: Double
    ) -> WatchAutoDecision? {
        guard motion.confidence != .low else { return nil }

        let confidence = confidenceLabel(motion.confidence)
        if motion.running {
            return WatchAutoDecision(activity: .running, confidence: confidence, provenance: "Core Motion · course", dwellSeconds: 7)
        }
        if motion.cycling {
            return WatchAutoDecision(activity: .cycling, confidence: confidence, provenance: "Core Motion · vélo", dwellSeconds: 9)
        }
        if motion.walking {
            let verticalTravel = elevationGainMeters + elevationLossMeters
            let terrainRatio = distanceMeters > 300 ? verticalTravel / distanceMeters : 0
            let hikingEvidence = elapsedSeconds >= 10 * 60
                && distanceMeters >= 700
                && verticalTravel >= 45
                && terrainRatio >= 0.035

            if hikingEvidence {
                let inferredConfidence = motion.confidence == .high && terrainRatio >= 0.05 ? "élevée" : "moyenne"
                return WatchAutoDecision(
                    activity: .hiking,
                    confidence: inferredConfidence,
                    provenance: "Inférence Watch Tracker · marche + terrain/dénivelé",
                    dwellSeconds: 30
                )
            }
            return WatchAutoDecision(activity: .walking, confidence: confidence, provenance: "Core Motion · marche", dwellSeconds: 8)
        }
        return nil
    }

    static func shouldStagePause(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double
    ) -> Bool {
        guard stationary else { return false }
        switch activity {
        case .walking, .hiking:
            return speedMps <= 1.2 && cadenceSPM < 30
        case .running, .trackAndField:
            return speedMps <= 1.5 && cadenceSPM < 55
        case .cycling, .handCycling:
            return speedMps <= 2.0
        default:
            return speedMps <= 1.0
        }
    }

    static func pauseDwell(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .cycling, .handCycling: return 7
        case .running, .trackAndField: return 9
        case .walking, .hiking: return 11
        default: return 12
        }
    }

    static func shouldStageResume(
        activity: ActivityKind,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?
    ) -> Bool {
        guard !stationary else { return false }
        switch activity {
        case .walking, .hiking:
            return speedMps >= 0.7 || cadenceSPM >= 35 || motionCandidate == .walking || motionCandidate == .hiking
        case .running, .trackAndField:
            return speedMps >= 1.2 || cadenceSPM >= 65 || motionCandidate == .running
        case .cycling, .handCycling:
            return speedMps >= 1.4 || motionCandidate == .cycling
        default:
            return speedMps >= 0.7 || motionCandidate != nil
        }
    }

    static func resumeDwell(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .cycling, .handCycling: return 3
        case .running, .trackAndField: return 3
        case .walking, .hiking: return 4
        default: return 4
        }
    }

    static func confidenceLabel(_ confidence: CMMotionActivityConfidence) -> String {
        switch confidence {
        case .high: return "élevée"
        case .medium: return "moyenne"
        case .low: return "faible"
        @unknown default: return "inconnue"
        }
    }
}
