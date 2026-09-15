import Foundation

enum TrackerPendingPlanRetryTrigger: Equatable {
    case initialBind
    case connectivityActivated
    case reachabilityChanged(isReachable: Bool)
}

enum TrackerFinishPersistencePolicy {
    static func forcedFinalActivity(
        event: String,
        payload: [String: Any]
    ) -> ActivityKind? {
        guard event == "final_activity_confirmed",
              let raw = payload["to"] as? String,
              let activity = ActivityKind(rawValue: raw),
              !activity.isAutomatic else { return nil }
        return activity
    }

    static func shouldSchedulePendingPlans(
        pendingCount: Int,
        reconciliationIsActive: Bool,
        trigger: TrackerPendingPlanRetryTrigger
    ) -> Bool {
        guard pendingCount > 0, !reconciliationIsActive else { return false }

        switch trigger {
        case .initialBind, .connectivityActivated:
            return true
        case .reachabilityChanged(let isReachable):
            return isReachable
        }
    }
}
