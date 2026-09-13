import Foundation

/// Pure, platform-independent arbitration for live session controls.
///
/// iPhone and Apple Watch must use the same policy so delayed or duplicated
/// WatchConnectivity / workout-mirroring messages cannot make the two devices
/// fight over session state. This file intentionally has no HealthKit,
/// WatchConnectivity, CoreLocation, or UI dependency and is therefore fully
/// deterministic under XCTest.
enum TrackerControlAction: String, Codable, CaseIterable {
    case pause
    case resume
    case stop
}

enum TrackerControlResult: String, Codable, Equatable {
    case accepted
    case expired
    case sessionMismatch = "session_mismatch"
    case staleRevision = "stale_revision"
    case stateMismatch = "state_mismatch"
    case invalidFinishActivity = "invalid_finish_activity"
    case unsupported
}

enum TrackerControlPhase: String, Codable, Equatable {
    case ready
    case active
    case paused
}

struct TrackerControlRequest: Equatable {
    let action: TrackerControlAction
    let token: String
    let sessionID: String
    let baseRevision: Int64
    let issuedAt: TimeInterval
    let finishDisposition: TrackerFinishDisposition?
    let finalActivity: ActivityKind?
}

struct TrackerControlContext: Equatable {
    let sessionID: String
    let authorityRevision: Int64
    let phase: TrackerControlPhase

    var isRunning: Bool {
        phase == .active || phase == .paused
    }
}

struct TrackerControlDecision: Equatable {
    let result: TrackerControlResult
    let shouldApply: Bool
    let isDuplicate: Bool

    static func reject(_ result: TrackerControlResult) -> Self {
        Self(result: result, shouldApply: false, isDuplicate: false)
    }

    static func accept() -> Self {
        Self(result: .accepted, shouldApply: true, isDuplicate: false)
    }

    static func duplicate(replaying result: TrackerControlResult) -> Self {
        Self(result: result, shouldApply: false, isDuplicate: true)
    }
}

enum TrackerControlCodec {
    static func encode(action: TrackerControlAction, token: String) -> String {
        "control:\(action.rawValue):\(token)"
    }

    static func decode(_ raw: String?) -> (action: TrackerControlAction, token: String)? {
        guard let raw, raw.hasPrefix("control:") else { return nil }
        let parts = raw.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard
            parts.count == 3,
            let action = TrackerControlAction(rawValue: String(parts[1])),
            !parts[2].isEmpty
        else {
            return nil
        }
        return (action, String(parts[2]))
    }

    static func acknowledgement(token: String, result: TrackerControlResult) -> String {
        "ack:\(token):\(result.rawValue)"
    }

    static func parseAcknowledgement(
        _ raw: String?
    ) -> (token: String, result: TrackerControlResult)? {
        guard let raw, raw.hasPrefix("ack:") else { return nil }
        let parts = raw.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard
            parts.count == 3,
            !parts[1].isEmpty,
            let result = TrackerControlResult(rawValue: String(parts[2]))
        else {
            return nil
        }
        return (String(parts[1]), result)
    }
}

enum TrackerControlPolicy {
    static let maximumCommandAge: TimeInterval = 8

    static func evaluate(
        request: TrackerControlRequest,
        context: TrackerControlContext,
        now: TimeInterval,
        lastToken: String?,
        lastResult: TrackerControlResult?
    ) -> TrackerControlDecision {
        if request.token == lastToken {
            return .duplicate(replaying: lastResult ?? .unsupported)
        }

        guard now - request.issuedAt <= maximumCommandAge else {
            return .reject(.expired)
        }

        guard context.isRunning, request.sessionID == context.sessionID else {
            return .reject(.sessionMismatch)
        }

        guard request.baseRevision == context.authorityRevision else {
            return .reject(.staleRevision)
        }

        switch request.action {
        case .pause:
            guard context.phase == .active else {
                return .reject(.stateMismatch)
            }
            return .accept()

        case .resume:
            guard context.phase == .paused else {
                return .reject(.stateMismatch)
            }
            return .accept()

        case .stop:
            let disposition = request.finishDisposition ?? .preserveDetectedSegments
            if disposition == .forceSingleActivity {
                guard let finalActivity = request.finalActivity, !finalActivity.isAutomatic else {
                    return .reject(.invalidFinishActivity)
                }
            }
            return .accept()
        }
    }
}
