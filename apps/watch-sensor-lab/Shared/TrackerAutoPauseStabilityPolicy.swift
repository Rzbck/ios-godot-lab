import Foundation

/// Conservative, platform-neutral stop detection for Watch auto-pause.
///
/// False pauses are more disruptive than slightly late pauses, so production
/// requires stationary Core Motion evidence plus sport-specific low-motion
/// evidence. Unsupported activities fail closed and keep recording.
enum TrackerAutoPauseStabilityPolicy {
    static func supports(_ activity: ActivityKind) -> Bool {
        switch activity {
        case .walking, .hiking, .running, .trackAndField, .cycling, .handCycling:
            return true
        default:
            return false
        }
    }

    static func shouldStagePause(
        activity: ActivityKind,
        enabled: Bool,
        stationary: Bool,
        speedMps: Double,
        speedFresh: Bool = true,
        cadenceSPM: Double
    ) -> Bool {
        guard enabled, supports(activity), stationary else { return false }

        let speed = max(0, speedMps)
        let cadence = max(0, cadenceSPM)

        switch activity {
        case .walking, .hiking:
            // A fresh moving speed vetoes pause. An old filtered speed is not
            // evidence that the person is still moving: stationary Core Motion
            // plus essentially absent cadence may still arm the dwell.
            return (!speedFresh || speed <= 0.35) && cadence < 10

        case .running, .trackAndField:
            return (!speedFresh || speed <= 0.45) && cadence < 25

        case .cycling, .handCycling:
            // CMPedometer is not cycling cadence. A fresh moving GPS speed is a
            // veto; stale speed is unknown and cannot override stationary motion.
            return !speedFresh || speed <= 0.40

        default:
            return false
        }
    }

    static func pauseDwell(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .walking, .hiking:
            return 6.0
        case .running, .trackAndField:
            return 4.0
        case .cycling, .handCycling:
            return 4.0
        default:
            return 6.0
        }
    }

    static func resumeDwell(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .walking, .hiking:
            return 1.0
        case .running, .trackAndField, .cycling, .handCycling:
            return 0.8
        default:
            return 1.0
        }
    }

    /// Maximum age of the callback that confirmed the current stationary state.
    /// CMMotionActivity.startDate is the transition time, not the observation
    /// arrival time, so an already-stationary workout must not be rejected just
    /// because that state began before the workout started.
    static func stationaryEvidenceFreshness(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .walking, .hiking:
            return 12.0
        case .running, .trackAndField, .cycling, .handCycling:
            return 10.0
        default:
            return 10.0
        }
    }

    /// A filtered speed is only a movement veto for a short time after that
    /// speed was actually updated. Without this, the final moving value can
    /// remain frozen indefinitely when Core Location stops producing usable
    /// speed samples.
    static func speedEvidenceFreshness(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .walking, .hiking, .running, .trackAndField, .cycling, .handCycling:
            return 4.0
        default:
            return 4.0
        }
    }

    /// Hysteresis after a confirmed automatic resume. This gives Core Motion,
    /// CMPedometer and Core Location enough time to repopulate fresh active-state
    /// evidence before stop detection can arm again.
    static func repauseCooldown(for activity: ActivityKind) -> TimeInterval {
        switch activity {
        case .walking, .hiking:
            return 10.0
        case .running, .trackAndField:
            return 8.0
        case .cycling, .handCycling:
            return 6.0
        default:
            return 10.0
        }
    }
}
