import Foundation

enum TrackerMotionConfidence: String, Codable, Equatable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "faible"
        case .medium: return "moyenne"
        case .high: return "élevée"
        }
    }
}

/// Platform-neutral motion evidence used by Auto mode.
///
/// CoreMotion is adapted into this value at the watchOS boundary. Tests and
/// future replay tools can build the same evidence without any physical motion.
struct TrackerMotionEvidence: Codable, Equatable {
    var walking: Bool
    var running: Bool
    var cycling: Bool
    var stationary: Bool
    var confidence: TrackerMotionConfidence

    init(
        walking: Bool = false,
        running: Bool = false,
        cycling: Bool = false,
        stationary: Bool = false,
        confidence: TrackerMotionConfidence = .high
    ) {
        self.walking = walking
        self.running = running
        self.cycling = cycling
        self.stationary = stationary
        self.confidence = confidence
    }
}

struct TrackerAutoDecision: Equatable {
    let activity: ActivityKind
    let confidence: String
    let provenance: String
    let dwellSeconds: TimeInterval
}

/// Deterministic Auto-mode rules with no HealthKit/CoreMotion/UserDefaults/UI
/// dependency. Production adapters supply platform evidence and preferences;
/// CI supplies synthetic evidence and replays it at full speed.
enum TrackerAutoPolicy {
    static func decision(
        from evidence: TrackerMotionEvidence
    ) -> TrackerAutoDecision? {
        guard evidence.confidence != .low else { return nil }

        let confidence = evidence.confidence.label
        if evidence.running {
            return TrackerAutoDecision(
                activity: .running,
                confidence: confidence,
                provenance: "Core Motion · course",
                dwellSeconds: 7
            )
        }
        if evidence.cycling {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: confidence,
                provenance: "Core Motion · vélo",
                dwellSeconds: 9
            )
        }
        if evidence.walking {
            return TrackerAutoDecision(
                activity: .walking,
                confidence: confidence,
                provenance: "Core Motion · marche",
                dwellSeconds: 8
            )
        }
        return nil
    }

    static func shouldStagePause(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double
    ) -> Bool {
        guard enabled else { return false }

        switch activity {
        case .walking, .hiking:
            return speedMps <= 0.45
                || (stationary && speedMps <= 0.9 && cadenceSPM < 45)
        case .running, .trackAndField:
            return speedMps <= 0.35
                || (stationary && speedMps <= 1.0 && cadenceSPM < 60)
        case .cycling, .handCycling:
            return speedMps <= 0.50
                || (stationary && speedMps <= 1.2)
        default:
            return speedMps <= 0.35
                || (stationary && speedMps <= 0.8)
        }
    }

    static func shouldStageResume(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?
    ) -> Bool {
        guard enabled, !stationary else { return false }

        switch activity {
        case .walking, .hiking:
            return speedMps >= 0.7
                || cadenceSPM >= 35
                || motionCandidate == .walking
                || motionCandidate == .hiking
        case .running, .trackAndField:
            return speedMps >= 1.2
                || cadenceSPM >= 65
                || motionCandidate == .running
        case .cycling, .handCycling:
            return speedMps >= 1.4
                || motionCandidate == .cycling
        default:
            return speedMps >= 0.7
                || motionCandidate != nil
        }
    }
}
