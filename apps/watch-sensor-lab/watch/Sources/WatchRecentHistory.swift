import Combine
import Foundation
import SwiftUI
import WatchConnectivity

struct WatchRecentActivityDigest: Codable, Identifiable, Equatable {
    let sessionID: String
    let activity: String
    let startedAt: TimeInterval
    let duration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double

    var id: String { sessionID }
    var date: Date { Date(timeIntervalSince1970: startedAt) }
    var activityKind: ActivityKind? { ActivityKind(rawValue: activity) }
}

struct WatchHistoryWindowStats: Codable, Equatable {
    let count: Int
    let duration: TimeInterval
    let distanceMeters: Double

    static let zero = WatchHistoryWindowStats(count: 0, duration: 0, distanceMeters: 0)
}

struct WatchHistoryDayBucket: Codable, Equatable, Identifiable {
    let dayStart: TimeInterval
    let count: Int
    let duration: TimeInterval
    let distanceMeters: Double

    var id: TimeInterval { dayStart }
    var date: Date { Date(timeIntervalSince1970: dayStart) }
}

private struct WatchRecentHistoryEnvelopeV6: Codable {
    let activities: [WatchRecentActivityDigest]
    let today: WatchHistoryWindowStats
    let sevenDays: WatchHistoryWindowStats
    let twentyEightDays: WatchHistoryWindowStats
    let daily28: [WatchHistoryDayBucket]
}

private struct WatchRecentHistoryEnvelopeV5: Codable {
    let activities: [WatchRecentActivityDigest]
    let sevenDays: WatchHistoryWindowStats
    let twentyEightDays: WatchHistoryWindowStats
}

final class WatchRecentHistoryStore: ObservableObject {
    static let shared = WatchRecentHistoryStore()

    @Published private(set) var activities: [WatchRecentActivityDigest] = []
    @Published private(set) var today: WatchHistoryWindowStats = .zero
    @Published private(set) var sevenDays: WatchHistoryWindowStats = .zero
    @Published private(set) var twentyEightDays: WatchHistoryWindowStats = .zero
    @Published private(set) var daily28: [WatchHistoryDayBucket] = []

    private let defaultsKey = "tracker.recentHistoryV6"
    private let v5DefaultsKey = "tracker.recentHistoryV5"
    private let legacyDefaultsKey = "tracker.recentHistoryV4"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(WatchRecentHistoryEnvelopeV6.self, from: data) {
            activities = decoded.activities
            today = decoded.today
            sevenDays = decoded.sevenDays
            twentyEightDays = decoded.twentyEightDays
            daily28 = decoded.daily28
            return
        }

        if let data = UserDefaults.standard.data(forKey: v5DefaultsKey),
           let decoded = try? JSONDecoder().decode(WatchRecentHistoryEnvelopeV5.self, from: data) {
            activities = decoded.activities
            sevenDays = decoded.sevenDays
            twentyEightDays = decoded.twentyEightDays
            return
        }

        if let data = UserDefaults.standard.data(forKey: legacyDefaultsKey),
           let decoded = try? JSONDecoder().decode([WatchRecentActivityDigest].self, from: data) {
            activities = decoded
        }
    }

    @discardableResult
    func ingest(_ userInfo: [String: Any]) -> Bool {
        guard let type = userInfo["type"] as? String,
              let data = userInfo["data"] as? Data else { return false }

        if type == "tracker_recent_history_v6",
           let decoded = try? JSONDecoder().decode(WatchRecentHistoryEnvelopeV6.self, from: data) {
            DispatchQueue.main.async {
                self.activities = Array(decoded.activities.prefix(16))
                self.today = decoded.today
                self.sevenDays = decoded.sevenDays
                self.twentyEightDays = decoded.twentyEightDays
                self.daily28 = Array(decoded.daily28.suffix(28))
                let persisted = WatchRecentHistoryEnvelopeV6(
                    activities: self.activities,
                    today: self.today,
                    sevenDays: self.sevenDays,
                    twentyEightDays: self.twentyEightDays,
                    daily28: self.daily28
                )
                if let encoded = try? JSONEncoder().encode(persisted) {
                    UserDefaults.standard.set(encoded, forKey: self.defaultsKey)
                }
            }
            return true
        }

        if type == "tracker_recent_history_v5",
           let decoded = try? JSONDecoder().decode(WatchRecentHistoryEnvelopeV5.self, from: data) {
            DispatchQueue.main.async {
                self.activities = Array(decoded.activities.prefix(16))
                self.sevenDays = decoded.sevenDays
                self.twentyEightDays = decoded.twentyEightDays
                let persisted = WatchRecentHistoryEnvelopeV5(
                    activities: self.activities,
                    sevenDays: self.sevenDays,
                    twentyEightDays: self.twentyEightDays
                )
                if let encoded = try? JSONEncoder().encode(persisted) {
                    UserDefaults.standard.set(encoded, forKey: self.v5DefaultsKey)
                }
            }
            return true
        }

        if type == "tracker_recent_history_v4",
           let decoded = try? JSONDecoder().decode([WatchRecentActivityDigest].self, from: data) {
            DispatchQueue.main.async {
                self.activities = Array(decoded.prefix(8))
                if let persisted = try? JSONEncoder().encode(self.activities) {
                    UserDefaults.standard.set(persisted, forKey: self.legacyDefaultsKey)
                }
            }
            return true
        }

        return false
    }
}

extension SensorModel {
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        _ = WatchRecentHistoryStore.shared.ingest(userInfo)
    }
}

struct WatchRecentHistoryView: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        Group {
            if history.activities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Aucune activité synchronisée")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Ouvre l’app iPhone avec la Watch connectée.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8)
            } else {
                TabView {
                    ForEach(history.activities) { activity in
                        WatchHistoryActivityPage(activity: activity)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .navigationTitle("Activités")
    }
}

private struct WatchHistoryActivityPage: View {
    let activity: WatchRecentActivityDigest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: activity.activityKind?.symbol ?? "figure.mixed.cardio")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.mint)
                Text(activity.activityKind?.label ?? activity.activity)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
            }

            Text(activity.date, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 7) {
                watchHistoryMetric(formatWatchHistoryDistance(activity.distanceMeters), "DIST")
                watchHistoryMetric(formatWatchHistoryDuration(activity.duration), "TEMPS")
            }

            HStack(spacing: 7) {
                watchHistoryMetric(
                    activity.activeEnergyKcal.map { String(format: "%.0f", $0) } ?? "—",
                    "KCAL"
                )
                watchHistoryMetric(
                    activity.elevationGainMeters > 0 ? String(format: "+%.0f m", activity.elevationGainMeters) : "—",
                    "D+"
                )
            }
        }
        .padding(.horizontal, 4)
    }

    private func watchHistoryMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.68)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

func formatWatchHistoryDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : String(format: "%d min", minutes)
}

func formatWatchHistoryDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}
