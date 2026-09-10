import Foundation
import WatchConnectivity

private struct PhoneRecentActivityDigest: Codable {
    let sessionID: String
    let activity: String
    let startedAt: TimeInterval
    let duration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double
}

final class PhoneRecentHistoryBridge {
    private let reviewStore = ActivityReviewStore()

    func publish(summaries: [TrackerSummary]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let digests = summaries.prefix(8).map { summary in
            PhoneRecentActivityDigest(
                sessionID: summary.sessionID,
                activity: reviewStore.effectiveActivity(for: summary),
                startedAt: summary.startedAt.timeIntervalSince1970,
                duration: summary.duration,
                distanceMeters: summary.distanceMeters,
                activeEnergyKcal: summary.activeEnergyKcal,
                elevationGainMeters: summary.elevationGainMeters
            )
        }
        guard let data = try? JSONEncoder().encode(digests) else { return }

        session.transferUserInfo([
            "type": "tracker_recent_history_v4",
            "data": data,
            "timestamp": Date().timeIntervalSince1970,
        ])
    }
}
