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

final class WatchRecentHistoryStore: ObservableObject {
    static let shared = WatchRecentHistoryStore()

    @Published private(set) var activities: [WatchRecentActivityDigest] = []

    private let defaultsKey = "tracker.recentHistoryV4"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([WatchRecentActivityDigest].self, from: data) else { return }
        activities = decoded
    }

    @discardableResult
    func ingest(_ userInfo: [String: Any]) -> Bool {
        guard userInfo["type"] as? String == "tracker_recent_history_v4",
              let data = userInfo["data"] as? Data,
              let decoded = try? JSONDecoder().decode([WatchRecentActivityDigest].self, from: data) else { return false }

        DispatchQueue.main.async {
            self.activities = Array(decoded.prefix(8))
            if let persisted = try? JSONEncoder().encode(self.activities) {
                UserDefaults.standard.set(persisted, forKey: self.defaultsKey)
            }
        }
        return true
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
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("ACTIVITÉS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.mint)
                }

                if history.activities.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "figure.walk")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("Aucune activité synchronisée")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                        Text("Ouvre l’app iPhone pour envoyer l’historique récent.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(history.activities) { activity in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(
                                    activity.activityKind?.label ?? activity.activity,
                                    systemImage: activity.activityKind?.symbol ?? "figure.mixed.cardio"
                                )
                                .font(.caption.weight(.bold))
                                Spacer()
                                Text(activity.date, format: .dateTime.day().month())
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 8) {
                                Text(formatWatchHistoryDistance(activity.distanceMeters))
                                Text(formatWatchHistoryDuration(activity.duration))
                                if let kcal = activity.activeEnergyKcal {
                                    Text(String(format: "%.0f kcal", kcal))
                                }
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()

                            if activity.elevationGainMeters > 0 {
                                Text(String(format: "+%.0f m D+", activity.elevationGainMeters))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 3)
        }
    }
}

private func formatWatchHistoryDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : String(format: "%d min", minutes)
}

private func formatWatchHistoryDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}
