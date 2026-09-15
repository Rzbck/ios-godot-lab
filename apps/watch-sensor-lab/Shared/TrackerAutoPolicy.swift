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

        // A real running cadence is a much better discriminator than a stale
        // walking flag. Keep the speed floor low enough for an easy jog.
        if speed >= 1.7, cadence >= 95 {
            return TrackerAutoDecision(
                activity: .running,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS + cadence · course",
                dwellSeconds: 2.0
            )
        }

        // Cycling often produces little/no pedometer cadence. If Core Motion is
        // stuck on walking but GPS clearly shows locomotion too fast for normal
        // walking and foot cadence is low, prefer cycling.
        if speed >= 3.0, cadence >= 35, cadence < 95 {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS · vélo",
                dwellSeconds: 2.0
            )
        }

        // With no step cadence, only a clearly cycling-grade speed overrides
        // a walking label. A fast run with a temporarily missing pedometer
        // sample stays undecided instead of being mis-recorded as cycling.
        if speed >= 5.0, cadence == 0 {
            return TrackerAutoDecision(
                activity: .cycling,
                confidence: motionTrusted ? confidence : "capteurs",
                provenance: "GPS · vélo",
                dwellSeconds: 2.0
            )
        }

        // A walking label at running/cycling speed is contradictory when the
        // cadence does not resolve it. Keep the current Auto sport instead of
        // falling back to the historical Walking default.
        if motionTrusted, evidence.walking, speed < 3.0 {
            return TrackerAutoDecision(
                activity: .walking,
                confidence: confidence,
                provenance: "Core Motion · marche",
                dwellSeconds: 2.5
            )
        }

        // Sensor fallback when Core Motion has not produced a usable semantic
        // label yet. It intentionally covers only obvious locomotion.
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

    /// Auto-pause must work when a workout starts and the person remains
    /// still. A credible GPS fix, trusted stationary motion, or a prior real
    /// movement may arm the pause candidate; the regular pause dwell still
    /// decides whether the pause actually happens.
    static func canArmPause(
        activity: ActivityKind,
        elapsedSeconds: TimeInterval,
        horizontalAccuracy: Double,
        movementObserved: Bool,
        motionMovementObserved: Bool = false,
        stationaryEvidence: Bool = false
    ) -> Bool {
        _ = activity
        _ = elapsedSeconds
        if stationaryEvidence || motionMovementObserved || movementObserved {
            return true
        }
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
            // Generic outdoor fallback for the rest of the Apple activity
            // catalog. The master auto-pause toggle remains the only setting.
            return (stationary && speed <= 0.8)
                || speed <= 0.20
        }
    }

    static func shouldStageResume(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        cadenceSPM: Double,
        motionCandidate: ActivityKind?,
        gpsEvidenceConfirmed: Bool = false,
        motionEvidenceFresh: Bool = false,
        cadenceEvidenceFresh: Bool = false
    ) -> Bool {
        guard enabled else { return false }
        let cadenceFloor: Double
        switch activity {
        case .walking, .hiking: cadenceFloor = 32
        case .running, .trackAndField: cadenceFloor = 60
        default: cadenceFloor = 35
        }

        // Resuming is intentionally stricter than pausing. A GPS probe earns
        // `gpsEvidenceConfirmed` only after multiple recent, precise moving
        // fixes. Without it, a fresh semantic motion callback and a fresh
        // cadence sample must agree. A value cached before the pause never
        // counts as either source.
        if gpsEvidenceConfirmed { return true }

        let motionShowsMovement = motionEvidenceFresh
            && !stationary
            && motionCandidate != nil
        let cadenceShowsMovement = cadenceEvidenceFresh
            && cadenceSPM >= cadenceFloor
        return motionShowsMovement && cadenceShowsMovement
    }
}
