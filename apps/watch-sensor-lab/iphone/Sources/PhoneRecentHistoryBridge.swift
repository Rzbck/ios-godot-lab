import Foundation
import WatchConnectivity

struct PhoneRecentActivityDigest: Codable {
    let sessionID: String
    let activity: String
    let startedAt: TimeInterval
    let duration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double
}

struct PhoneHistoryWindowStats: Codable {
    let count: Int
    let duration: TimeInterval
    let distanceMeters: Double
}

struct PhoneRecentHistoryEnvelope: Codable {
    let activities: [PhoneRecentActivityDigest]
    let sevenDays: PhoneHistoryWindowStats
    let twentyEightDays: PhoneHistoryWindowStats
}

final class PhoneRecentHistoryBridge {
    private let reviewStore = ActivityReviewStore()
    private let healthReader = HealthWorkoutHistoryReader()

    func publish(summaries: [TrackerSummary]) {
        healthReader.loadAll { [weak self] healthRecords in
            self?.prepareAndDeliver(summaries: summaries, healthRecords: healthRecords)
        }
    }

    private func prepareAndDeliver(summaries: [TrackerSummary], healthRecords: [HealthWorkoutRecord]) {
        guard WCSession.isSupported() else { return }

        let localIDs = Set(summaries.map(\.sessionID))
        var digests: [PhoneRecentActivityDigest] = summaries.map { summary in
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

        digests.append(contentsOf: healthRecords.compactMap { record in
            if let trackerSessionID = record.trackerSessionID, localIDs.contains(trackerSessionID) {
                return nil
            }
            return PhoneRecentActivityDigest(
                sessionID: "health:\(record.id.uuidString)",
                activity: record.activity.rawValue,
                startedAt: record.startedAt.timeIntervalSince1970,
                duration: record.duration,
                distanceMeters: record.distanceMeters,
                activeEnergyKcal: record.activeEnergyKcal,
                elevationGainMeters: 0
            )
        })

        digests.sort { $0.startedAt > $1.startedAt }

        let envelope = PhoneRecentHistoryEnvelope(
            activities: Array(digests.prefix(16)),
            sevenDays: stats(for: digests, days: 7),
            twentyEightDays: stats(for: digests, days: 28)
        )

        guard let data = try? JSONEncoder().encode(envelope) else { return }
        deliver(data: data, attempt: 0)
    }

    private func deliver(data: Data, attempt: Int) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            guard attempt < 5 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.deliver(data: data, attempt: attempt + 1)
            }
            return
        }

        session.transferUserInfo([
            "type": "tracker_recent_history_v5",
            "data": data,
            "timestamp": Date().timeIntervalSince1970,
        ])
    }

    private func stats(for activities: [PhoneRecentActivityDigest], days: Int) -> PhoneHistoryWindowStats {
        let threshold = Date().addingTimeInterval(-TimeInterval(days) * 24 * 3600)
        let recent = activities.filter { Date(timeIntervalSince1970: $0.startedAt) >= threshold }
        return PhoneHistoryWindowStats(
            count: recent.count,
            duration: recent.reduce(0) { $0 + $1.duration },
            distanceMeters: recent.reduce(0) { $0 + $1.distanceMeters }
        )
    }
}
