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
    func publish(summaries: [TrackerSummary]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        let digests = summaries.prefix(8).map {
            PhoneRecentActivityDigest(
                sessionID: $0.sessionID,
                activity: $0.activity,
                startedAt: $0.startedAt.timeIntervalSince1970,
                duration: $0.duration,
                distanceMeters: $0.distanceMeters,
                activeEnergyKcal: $0.activeEnergyKcal,
                elevationGainMeters: $0.elevationGainMeters
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
