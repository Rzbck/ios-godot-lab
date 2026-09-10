import HealthKit
import MapKit
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
            WatchStartPage().tag(0)
            WatchProgressionPage().tag(1)
            WatchHistoryLauncherPage(showHistory: $showHistory).tag(2)
        }
        .tabViewStyle(.page)
        .sheet(isPresented: $showHistory) {
            WatchRecentHistoryView()
        }
    }
}

private struct WatchStartPage: View {
    @EnvironmentObject private var model: SensorModel

    private var activityBinding: Binding<ActivityKind> {
        Binding(get: { model.selectedActivity }, set: { model.selectActivity($0) })
    }

    private var autoPauseBinding: Binding<Bool> {
        Binding(get: { model.autoPauseEnabled }, set: { model.setAutoPauseEnabled($0) })
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: model.selectedActivity.symbol)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.green)
                Text(model.selectedActivity.label)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer()
            }

            Picker("Activité", selection: activityBinding) {
                ForEach(ActivityKind.allCases) { activity in
                    Label(activity.label, systemImage: activity.symbol).tag(activity)
                }
            }
            .pickerStyle(.navigationLink)

            HStack(spacing: 5) {
                WatchStatusChip(symbol: "iphone", ready: model.phoneReachable)
                WatchStatusChip(symbol: "heart.fill", ready: model.healthAuthorized)
                WatchStatusChip(symbol: "location.fill", ready: model.horizontalAccuracy >= 0)
            }

            Toggle("Pause auto", isOn: autoPauseBinding)
                .font(.caption.weight(.semibold))
                .tint(.mint)

            Button { model.start() } label: {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
        }
        .padding(.horizontal, 3)
    }
}

private struct WatchProgressionPage: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PROGRESSION", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("7 J")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.mint)
            }

            HStack(spacing: 7) {
                WatchProgressMetric(value: "\(history.sevenDays.count)", label: "SÉANCES")
                WatchProgressMetric(value: compactWatchDuration(history.sevenDays.duration), label: "TEMPS")
            }

            HStack(spacing: 7) {
                WatchProgressMetric(value: compactWatchDistance(history.sevenDays.distanceMeters), label: "DISTANCE")
                WatchProgressMetric(value: weeklyComparison, label: "VS 28 J")
            }

            Text(history.activities.isEmpty
                 ? "Ouvre l’iPhone pour synchroniser Santé + Tracker."
                 : "Données issues de l’historique synchronisé depuis l’iPhone.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 3)
    }

    private var weeklyComparison: String {
        let baseline = history.twentyEightDays.duration / 4
        guard baseline > 0 else { return "—" }
        let delta = (history.sevenDays.duration - baseline) / baseline
        if abs(delta) < 0.05 { return "≈" }
        return String(format: "%+.0f%%", delta * 100)
    }
}

private struct WatchHistoryLauncherPage: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared
    @Binding var showHistory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("RÉCENTES", systemImage: "clock.arrow.circlepath")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(history.activities.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.mint)
            }

            if let latest = history.activities.first {
                HStack(spacing: 9) {
                    Image(systemName: latest.activityKind?.symbol ?? "figure.mixed.cardio")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.activityKind?.label ?? latest.activity)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Text(latest.date, format: .dateTime.day().month().hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 7) {
                    WatchProgressMetric(value: compactWatchDistance(latest.distanceMeters), label: "DIST")
                    WatchProgressMetric(value: compactWatchDuration(latest.duration), label: "TEMPS")
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Synchronisation iPhone…")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            Button { showHistory = true } label: {
                Label("Voir l’historique", systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(history.activities.isEmpty)
        }
        .padding(.horizontal, 3)
    }
}

private struct ActiveWorkoutView: View {
    var body: some View {
        TabView {
            WatchPrimaryMetricsPage()
            WatchEffortMetricsPage()
            WatchRouteTerrainPage()
            WatchControlsPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct WatchPrimaryMetricsPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(model.isPaused ? Color.orange : Color.green)
                    .frame(width: 7, height: 7)
                Text(primaryStateLabel)
                    .font(.caption2.weight(.black))
                    .lineLimit(1)
                Spacer()
                Image(systemName: model.phoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(model.phoneReachable ? Color.green : Color.secondary)
            }

            Text(formatDuration(model.elapsedSeconds))
                .font(.system(size: 36, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.78)

            HStack(spacing: 8) {
                WatchMetricCard(
                    title: "DISTANCE",
                    value: model.elapsedSeconds > 4 ? formatDistance(model.distanceMeters) : "—",
                    unit: model.distanceMeters >= 1000 ? "km" : "m",
                    symbol: model.displayActivity.symbol
                )
                WatchMetricCard(
                    title: "CŒUR",
                    value: model.heartRate > 0 ? String(format: "%.0f", model.heartRate) : "—",
                    unit: "bpm",
                    symbol: "heart.fill",
                    accent: .red
                )
            }

            HStack(spacing: 8) {
                Label(speedLabel, systemImage: "speedometer")
                Spacer()
                Label(model.elapsedSeconds > 4 ? "+\(Int(model.elevationGainMeters)) m" : "D+ —", systemImage: "arrow.up.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private var primaryStateLabel: String {
        if model.isPaused { return model.autoPaused ? "PAUSE AUTO" : "PAUSE" }
        if model.selectedActivity.isAutomatic { return "AUTO · \(model.effectiveActivity.label.uppercased())" }
        if model.selectedActivity == .swimBikeRun, model.multisportTransition { return "TRANSITION" }
        return model.displayActivity.label.uppercased()
    }

    private var speedLabel: String {
        guard model.horizontalAccuracy >= 0, model.elapsedSeconds > 4 else { return "GPS…" }
        return String(format: "%.1f km/h", model.currentSpeedMps * 3.6)
    }
}

private struct WatchEffortMetricsPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("EFFORT")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.mint)
            }

            HStack(spacing: 8) {
                WatchMetricCard(
                    title: "CALORIES",
                    value: model.activeEnergyKcal > 0 ? String(format: "%.0f", model.activeEnergyKcal) : "—",
                    unit: "kcal",
                    symbol: "flame.fill",
                    accent: .orange
                )
                WatchMetricCard(
                    title: "CADENCE",
                    value: model.cadenceSPM > 0 ? String(format: "%.0f", model.cadenceSPM) : "—",
                    unit: "pas/min",
                    symbol: "metronome.fill",
                    accent: .cyan
                )
            }

            HStack(spacing: 8) {
                WatchMetricCard(
                    title: "FC MOY.",
                    value: model.averageHeartRate > 0 ? String(format: "%.0f", model.averageHeartRate) : "—",
                    unit: "bpm",
                    symbol: "heart.text.square.fill",
                    accent: .red
                )
                WatchMetricCard(
                    title: "PAS",
                    value: model.steps > 0 ? "\(model.steps)" : "—",
                    unit: "pas",
                    symbol: "shoeprints.fill"
                )
            }
        }
        .padding(.horizontal, 2)
    }
}

private struct WatchRouteTerrainPage: View {
    @EnvironmentObject private var model: SensorModel
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 7) {
            Map(position: $position, interactionModes: []) {
                UserAnnotation()
                if model.route.count > 1 {
                    MapPolyline(coordinates: model.route)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack(spacing: 8) {
                CompactTerrainValue(
                    title: "ALT",
                    value: model.elapsedSeconds > 4 ? "\(Int(model.altitudeMeters)) m" : "—"
                )
                CompactTerrainValue(
                    title: "D+",
                    value: model.elapsedSeconds > 4 ? "+\(Int(model.elevationGainMeters)) m" : "—"
                )
                CompactTerrainValue(
                    title: "GPS",
                    value: model.horizontalAccuracy >= 0 ? "±\(Int(model.horizontalAccuracy)) m" : "—"
                )
            }
        }
        .onAppear { recenter() }
        .onChange(of: model.route.count) { _, _ in recenter() }
    }

    private func recenter() {
        guard let coordinate = model.currentCoordinate else { return }
        position = .region(
            MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
        )
    }
}

private struct WatchControlsPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 2)

            if model.selectedActivity == .swimBikeRun, model.canAdvanceTriathlon {
                Button { model.advanceTriathlon() } label: {
                    Label(
                        model.multisportTransition ? "Démarrer suivant" : "Transition",
                        systemImage: model.multisportTransition ? "forward.fill" : "arrow.triangle.2.circlepath"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            Button { model.isPaused ? model.resume() : model.pause() } label: {
                Label(
                    model.isPaused ? "Reprendre" : "Pause",
                    systemImage: model.isPaused ? "play.fill" : "pause.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isPaused ? .green : .orange)
            .controlSize(.large)

            Button(role: .destructive) { model.stop() } label: {
                Label("Terminer", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 2)
    }
}

private struct WatchStatusChip: View {
    let symbol: String
    let ready: Bool

    var body: some View {
        Image(systemName: symbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.white.opacity(0.07), in: Capsule())
    }
}

private struct WatchProgressMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
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

private struct WatchMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var accent: Color = .green

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.68)
                .lineLimit(1)

            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CompactTerrainValue: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private func compactWatchDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes)m"
}

private func compactWatchDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1fkm", meters / 1000) : String(format: "%.0fm", meters)
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}

private func formatDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f", meters / 1000) : String(format: "%.0f", meters)
}
