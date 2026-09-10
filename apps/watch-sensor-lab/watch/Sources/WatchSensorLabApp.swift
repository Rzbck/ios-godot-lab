import HealthKit
import SwiftUI
import WatchKit

@main
struct WatchSensorLabWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @StateObject private var model = SensorModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(model)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        DispatchQueue.main.async {
            SensorModel.shared.startFromPhoneConfiguration(workoutConfiguration)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        Group {
            if model.running { ActiveWorkoutView() } else { ReadyWatchHomeView() }
        }
        .animation(.snappy, value: model.running)
        .onAppear { model.activateSession() }
    }
}

private struct ReadyWatchHomeView: View {
    @State private var selectedPage = 0
    @State private var showHistory = false

    var body: some View {
        TabView(selection: $selectedPage) {
            WatchLaunchPage().tag(0)
            WatchProgressionDepthView().tag(1)
            WatchVisualRecentPage(showHistory: $showHistory).tag(2)
            WatchStatusDepthView().tag(3)
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showHistory) {
            WatchRecentHistoryView()
        }
    }
}

private struct WatchLaunchPage: View {
    @EnvironmentObject private var model: SensorModel
    @State private var showSportPicker = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("PRÊT")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                WatchTinyStatus(symbol: "iphone", ready: model.phoneReachable, accent: .cyan)
                WatchTinyStatus(symbol: "heart.fill", ready: model.healthAuthorized, accent: .pink)
                WatchTinyStatus(symbol: "location.fill", ready: model.horizontalAccuracy >= 0, accent: .mint)
            }

            Spacer(minLength: 0)

            Button { showSportPicker = true } label: {
                VStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 30, weight: .black))
                    Text("Démarrer")
                        .font(.title3.weight(.black))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 92)
                .background(
                    LinearGradient(colors: [.cyan, .mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                Label(model.selectedActivity.label, systemImage: model.selectedActivity.symbol)
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                Button {
                    model.setAutoPauseEnabled(!model.autoPauseEnabled)
                } label: {
                    Image(systemName: model.autoPauseEnabled ? "pause.circle.fill" : "pause.circle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(model.autoPauseEnabled ? Color.orange : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.autoPauseEnabled ? "Pause automatique activée" : "Pause automatique désactivée")
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showSportPicker) {
            WatchSportStartPicker()
        }
    }
}

private struct WatchSportStartPicker: View {
    @EnvironmentObject private var model: SensorModel
    @Environment(\.dismiss) private var dismiss

    private var pages: [[ActivityKind]] {
        let priority: [ActivityKind] = [
            .automatic, .walking, .running, .cycling,
            .hiking, .swimming, .rowing, .swimBikeRun,
            .functionalStrengthTraining, .traditionalStrengthTraining, .highIntensityIntervalTraining, .elliptical,
            .yoga, .soccer, .tennis, .basketball,
        ]
        let prioritySet = Set(priority.map(\.rawValue))
        let remaining = ActivityKind.allCases.filter { !prioritySet.contains($0.rawValue) }
        let ordered = priority + remaining
        return stride(from: 0, to: ordered.count, by: 4).map { index in
            Array(ordered[index..<min(index + 4, ordered.count)])
        }
    }

    var body: some View {
        TabView {
            ForEach(Array(pages.enumerated()), id: \.offset) { index, activities in
                VStack(spacing: 7) {
                    HStack {
                        Text(index == 0 ? "CHOISIR & DÉMARRER" : "SPORTS")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(index + 1)/\(pages.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                        ForEach(activities) { activity in
                            Button {
                                model.selectActivity(activity)
                                model.start()
                                dismiss()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: activity.symbol)
                                        .font(.title3.weight(.bold))
                                    Text(activity.label)
                                        .font(.system(size: 10, weight: .bold))
                                        .lineLimit(2)
                                        .minimumScaleFactor(0.65)
                                        .multilineTextAlignment(.center)
                                }
                                .foregroundStyle(sportAccent(activity))
                                .frame(maxWidth: .infinity)
                                .frame(height: 61)
                                .background(sportAccent(activity).opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .tabViewStyle(.verticalPage)
    }

    private func sportAccent(_ activity: ActivityKind) -> Color {
        switch activity {
        case .automatic: return .cyan
        case .walking, .hiking: return .mint
        case .running, .trackAndField: return .orange
        case .cycling, .handCycling: return .yellow
        case .swimming, .rowing, .paddleSports, .waterFitness, .waterPolo, .waterSports, .sailing, .surfingSports, .underwaterDiving: return .blue
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining, .crossTraining, .highIntensityIntervalTraining: return .red
        case .yoga, .mindAndBody, .pilates, .taiChi, .flexibility: return .purple
        default: return .pink
        }
    }
}

private struct WatchVisualRecentPage: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared
    @Binding var showHistory: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("RÉCENTES")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(history.activities.count)")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.pink)
            }

            if let latest = history.activities.first {
                Button { showHistory = true } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: latest.activityKind?.symbol ?? "figure.mixed.cardio")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(latest.activityKind?.label ?? latest.activity)
                                    .font(.headline.weight(.black))
                                    .lineLimit(1)
                                Text(latest.date, format: .dateTime.day().month().hour().minute())
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }

                        HStack(spacing: 7) {
                            WatchVisualMetric(value: compactVisualDuration(latest.duration), label: "temps", symbol: "clock.fill", accent: .cyan)
                            WatchVisualMetric(value: compactVisualDistance(latest.distanceMeters), label: "distance", symbol: "location.fill", accent: .mint)
                        }
                    }
                    .padding(9)
                    .background(
                        LinearGradient(colors: [.orange.opacity(0.16), .pink.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Synchronisation iPhone…")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Button { showHistory = true } label: {
                Label("Tout voir", systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.pink)
            .disabled(history.activities.isEmpty)
        }
        .padding(.horizontal, 4)
    }
}

private struct WatchTinyStatus: View {
    let symbol: String
    let ready: Bool
    let accent: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(ready ? accent : Color.secondary.opacity(0.45))
            .frame(width: 17, height: 17)
            .background((ready ? accent : Color.secondary).opacity(0.10), in: Circle())
    }
}

private struct WatchVisualMetric: View {
    let value: String
    let label: String
    let symbol: String
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption.weight(.black))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private func compactVisualDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes)m"
}

private func compactVisualDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}
