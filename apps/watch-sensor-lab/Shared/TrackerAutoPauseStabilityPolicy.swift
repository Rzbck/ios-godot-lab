import Foundation

/// Conservative, platform-neutral stop detection for Watch auto-pause.
///
/// False pauses are more disruptive than slightly late pauses, so production
/// requires fresh stationary Core Motion evidence plus sport-specific low-motion
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
        cadenceSPM: Double
    ) -> Bool {
        guard enabled, supports(activity), stationary else { return false }

        let speed = max(0, speedMps)
        let cadence = max(0, cadenceSPM)

        switch activity {
        case .walking, .hiking:
            // Walking GPS often reports zero indoors or between fixes. Never let
            // GPS-zero alone pause a moving pedestrian; Core Motion must also be
            // stationary and fresh cadence must be essentially absent.
            return speed <= 0.35 && cadence < 10

        case .running, .trackAndField:
            return speed <= 0.45 && cadence < 25

        case .cycling, .handCycling:
            // CMPedometer is not cycling cadence. Require stationary Core Motion
            // and a near-zero location speed instead of step cadence.
            return speed <= 0.40

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
