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
    /// Internal stabilization only. This is deliberately not a user setting.
    let dwellSeconds: TimeInterval
}

struct TrackerAutoResumeEvidence: Equatable {
    var speedMps: Double
    var gpsFresh: Bool
    var gpsReliable: Bool
    var gpsSustained: Bool
    var cadenceSPM: Double
    var cadenceFresh: Bool
    var stationary: Bool
    var motionCandidate: ActivityKind?
    var motionFresh: Bool
}

struct TrackerAutoResumeDecision: Equatable {
    let shouldResume: Bool
    let reason: String
    let agreeingEvidenceCount: Int
}

/// Deterministic Auto-mode rules with no HealthKit/CoreMotion/UserDefaults/UI
/// dependency. Production adapters supply platform evidence and preferences;
/// CI supplies synthetic evidence and replays it at full speed.
enum TrackerAutoPolicy {
    static func decision(
        from evidence: TrackerMotionEvidence,
        speedMps: Double = 0,
        cadenceSPM: Double = 0
    ) -> TrackerAutoDecision? {
        let speed = max(0, speedMps)
        let cadence = max(0, cadenceSPM)
        let motionTrusted = evidence.confidence != .low
        let confidence = evidence.confidence.label

        // Core Motion remains the strongest semantic signal when it is clear.
        // Fresh GPS/cadence is used to prevent the historical failure where a
        // fast bicycle ride stayed classified as walking for the whole workout.
        if motionTrusted, evidence.running {
            return TrackerAutoDecision(
                activity: .running,
                confidence: confidence,
                provenance: "Core Motion · course",
                dwellSeconds: 2.0
            )
        }

        if motionTrusted, evidence.cycling {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: confidence,
                provenance: "Core Motion · vélo",
                dwellSeconds: 2.0
            )
        }

        if speed >= 1.7, cadence >= 95 {
            return TrackerAutoDecision(
                activity: .running,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS + cadence · course",
                dwellSeconds: 2.0
            )
        }

        if speed >= 3.0, cadence >= 35, cadence < 95 {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS · vélo",
                dwellSeconds: 2.0
            )
        }

        if speed >= 5.0, cadence == 0 {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS · vélo",
                dwellSeconds: 2.0
            )
        }

        if motionTrusted, evidence.walking, speed < 3.0 {
            return TrackerAutoDecision(
                activity: .walking,
                confidence: confidence,
                provenance: "Core Motion · marche",
                dwellSeconds: 2.5
            )
        }

        if speed >= 0.55, speed < 2.2, cadence >= 35 {
            return TrackerAutoDecision(
                activity: .walking,
                confidence: "capteurs",
                provenance: "GPS + cadence · marche",
                dwellSeconds: 2.5
            )
        }

        return nil
    }

    /// Legacy arming rule retained for replay compatibility. Production adaptive
    /// auto-pause uses `canArmAdaptivePause`, which accepts trustworthy stationary
    /// evidence at startup instead of requiring a fake first movement.
    static func canArmPause(
        activity: ActivityKind,
        elapsedSeconds: TimeInterval,
        horizontalAccuracy: Double,
        movementObserved: Bool,
        motionMovementObserved: Bool = false
    ) -> Bool {
        _ = activity
        _ = elapsedSeconds
        if motionMovementObserved { return true }
        guard movementObserved else { return false }
        return horizontalAccuracy >= 0 && horizontalAccuracy <= 30
    }

    /// Adaptive production rule: an actual sensor observation is enough to arm
    /// pause. A good GPS fix with zero speed or any trusted Core Motion state can
    /// therefore pause a workout that started while the user was already still.
    static func canArmAdaptivePause(
        horizontalAccuracy: Double,
        motionEvidenceObserved: Bool
    ) -> Bool {
        if motionEvidenceObserved { return true }
        return horizontalAccuracy >= 0 && horizontalAccuracy <= 30
    }

    static func shouldStagePause(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double
    ) -> Bool {
        guard enabled else { return false }
        let speed = max(0, speedMps)
        let cadence = max(0, cadenceSPM)

        switch activity {
        case .walking, .hiking:
            return (stationary && speed <= 0.9 && cadence < 35)
                || (speed <= 0.22 && cadence < 25)
        case .running, .trackAndField:
            return (stationary && speed <= 1.0 && cadence < 50)
                || (speed <= 0.22 && cadence < 40)
        case .cycling, .handCycling:
            return (stationary && speed <= 1.2)
                || speed <= 0.30
        default:
            return (stationary && speed <= 0.8)
                || speed <= 0.20
        }
    }

    static func resumeDecision(
        activity: ActivityKind,
        enabled: Bool,
        evidence: TrackerAutoResumeEvidence
    ) -> TrackerAutoResumeDecision {
        guard enabled else {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "disabled",
                agreeingEvidenceCount: 0
            )
        }

        let speed = max(0, evidence.speedMps)
        let cadence = max(0, evidence.cadenceSPM)

        let speedThreshold: Double
        let strongSoloSpeedThreshold: Double
        let cadenceThreshold: Double?

        switch activity {
        case .walking, .hiking:
            speedThreshold = 0.65
            strongSoloSpeedThreshold = 1.0
            cadenceThreshold = 32
        case .running, .trackAndField:
            speedThreshold = 1.0
            strongSoloSpeedThreshold = 1.6
            cadenceThreshold = 60
        case .cycling, .handCycling:
            speedThreshold = 1.1
            strongSoloSpeedThreshold = 2.0
            cadenceThreshold = nil
        default:
            speedThreshold = 0.6
            strongSoloSpeedThreshold = 1.2
            cadenceThreshold = nil
        }

        let gpsMoving = evidence.gpsFresh
            && evidence.gpsReliable
            && evidence.gpsSustained
            && speed >= speedThreshold

        let strongGPS = evidence.gpsFresh
            && evidence.gpsReliable
            && evidence.gpsSustained
            && speed >= strongSoloSpeedThreshold

        let cadenceMoving: Bool
        if let cadenceThreshold {
            cadenceMoving = evidence.cadenceFresh && cadence >= cadenceThreshold
        } else {
            cadenceMoving = false
        }

        let motionMatches: Bool
        switch activity {
        case .walking, .hiking:
            motionMatches = evidence.motionCandidate == .walking
                || evidence.motionCandidate == .hiking
        case .running, .trackAndField:
            motionMatches = evidence.motionCandidate == .running
                || evidence.motionCandidate == .trackAndField
        case .cycling, .handCycling:
            motionMatches = evidence.motionCandidate == .cycling
                || evidence.motionCandidate == .handCycling
        default:
            motionMatches = evidence.motionCandidate != nil
        }

        let motionMoving = evidence.motionFresh
            && !evidence.stationary
            && motionMatches

        if gpsMoving && motionMoving {
            return TrackerAutoResumeDecision(
                shouldResume: true,
                reason: "gps_motion_consensus",
                agreeingEvidenceCount: 2
            )
        }

        if gpsMoving && cadenceMoving {
            return TrackerAutoResumeDecision(
                shouldResume: true,
                reason: "gps_cadence_consensus",
                agreeingEvidenceCount: 2
            )
        }

        if cadenceMoving && motionMoving {
            return TrackerAutoResumeDecision(
                shouldResume: true,
                reason: "cadence_motion_consensus",
                agreeingEvidenceCount: 2
            )
        }

        // Strong, sustained and quality-checked GPS can stand alone. This keeps
        // cycling responsive when Core Motion remains incorrectly stuck on
        // walking, while rejecting a single coordinate jump.
        if strongGPS {
            return TrackerAutoResumeDecision(
                shouldResume: true,
                reason: "strong_sustained_gps",
                agreeingEvidenceCount: 1
            )
        }

        if evidence.cadenceSPM > 0 && !evidence.cadenceFresh {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "stale_cadence_rejected",
                agreeingEvidenceCount: 0
            )
        }

        if speed > 0 && (!evidence.gpsFresh || !evidence.gpsReliable) {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "unreliable_gps_rejected",
                agreeingEvidenceCount: 0
            )
        }

        if evidence.gpsFresh && evidence.gpsReliable && !evidence.gpsSustained {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "single_gps_sample_rejected",
                agreeingEvidenceCount: 0
            )
        }

        if motionMoving {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "motion_only_rejected",
                agreeingEvidenceCount: 1
            )
        }

        if cadenceMoving {
            return TrackerAutoResumeDecision(
                shouldResume: false,
                reason: "cadence_only_rejected",
                agreeingEvidenceCount: 1
            )
        }

        return TrackerAutoResumeDecision(
            shouldResume: false,
            reason: "insufficient_fresh_evidence",
            agreeingEvidenceCount: 0
        )
    }

    /// Compatibility surface for older deterministic tests/callers. Runtime code
    /// now supplies explicit freshness/quality through `resumeDecision`.
    static func shouldStageResume(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?
    ) -> Bool {
        resumeDecision(
            activity: activity,
            enabled: enabled,
            evidence: TrackerAutoResumeEvidence(
                speedMps: speedMps,
                gpsFresh: speedMps > 0,
                gpsReliable: speedMps > 0,
                gpsSustained: speedMps > 0,
                cadenceSPM: cadenceSPM,
                cadenceFresh: cadenceSPM > 0,
                stationary: stationary,
                motionCandidate: motionCandidate,
                motionFresh: motionCandidate != nil || stationary
            )
        ).shouldResume
    }
}
