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
            ContentView()
                .environmentObject(model)
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
            if model.running {
                ActiveWorkoutView()
            } else {
                ReadyWorkoutView()
            }
        }
        .animation(.snappy, value: model.running)
        .onAppear {
            model.activateSession()
        }
    }
}

private struct ReadyWorkoutView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("WATCH TRACKER")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text("Prêt")
                        .font(.title2.weight(.heavy))
                }
                Spacer()
                Image(systemName: "figure.run.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }

            HStack(spacing: 6) {
                WatchStatusChip(symbol: "iphone", ready: model.phoneReachable)
                WatchStatusChip(symbol: "heart.fill", ready: model.healthAuthorized)
                WatchStatusChip(symbol: "location.fill", ready: model.horizontalAccuracy >= 0)
            }

            Button {
                model.start()
            } label: {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)

            Text(model.sessionStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }
}

private struct ActiveWorkoutView: View {
    var body: some View {
        TabView {
            WatchPrimaryMetricsPage()
            WatchRoutePage()
            WatchClimbPage()
            WatchControlsPage()
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct WatchPrimaryMetricsPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.isPaused ? Color.orange : Color.green)
                        .frame(width: 7, height: 7)
                    Text(model.isPaused ? "PAUSE" : "LIVE")
                        .font(.caption2.weight(.black))
                }
                Spacer()
                Image(systemName: model.phoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                    .foregroundStyle(model.phoneReachable ? Color.green : Color.secondary)
            }

            Text(formatDuration(model.elapsedSeconds))
                .font(.system(size: 33, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.75)

            HStack(spacing: 7) {
                WatchMetricCard(
                    title: "DISTANCE",
                    value: formatDistance(model.distanceMeters),
                    unit: model.distanceMeters >= 1000 ? "km" : "m",
                    symbol: "figure.run"
                )
                WatchMetricCard(
                    title: "CŒUR",
                    value: model.heartRate > 0 ? String(format: "%.0f", model.heartRate) : "—",
                    unit: "bpm",
                    symbol: "heart.fill",
                    accent: .red
                )
            }

            HStack {
                Label(String(format: "%.1f km/h", model.currentSpeedMps * 3.6), systemImage: "speedometer")
                Spacer()
                Text("+\(Int(model.elevationGainMeters)) m")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}

private struct WatchRoutePage: View {
    @EnvironmentObject private var model: SensorModel
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $position, interactionModes: []) {
                UserAnnotation()
                if model.route.count > 1 {
                    MapPolyline(coordinates: model.route)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))

            Text("PARCOURS")
                .font(.caption2.weight(.black))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onChange(of: model.route.count) { _, _ in
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
}

private struct WatchClimbPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("TERRAIN")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "mountain.2.fill")
                    .foregroundStyle(.orange)
            }

            WatchWideMetric(
                title: "Altitude",
                value: String(format: "%.0f m", model.altitudeMeters),
                symbol: "mountain.2"
            )

            HStack(spacing: 7) {
                WatchMetricCard(title: "MONTÉE", value: String(format: "%.0f", model.elevationGainMeters), unit: "m", symbol: "arrow.up.right", accent: .orange)
                WatchMetricCard(title: "DESCENTE", value: String(format: "%.0f", model.elevationLossMeters), unit: "m", symbol: "arrow.down.right", accent: .cyan)
            }

            HStack {
                Text("FC moy.")
                Spacer()
                Text(model.averageHeartRate > 0 ? String(format: "%.0f bpm", model.averageHeartRate) : "—")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
    }
}

private struct WatchControlsPage: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        VStack(spacing: 9) {
            Text("SESSION")
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)

            Button {
                model.isPaused ? model.resume() : model.pause()
            } label: {
                Label(model.isPaused ? "Reprendre" : "Pause", systemImage: model.isPaused ? "play.fill" : "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isPaused ? .green : .orange)
            .controlSize(.large)

            Button(role: .destructive) {
                model.stop()
            } label: {
                Label("Terminer", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("SHA \(BuildInfo.gitSHA)")
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
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
            .frame(height: 34)
            .background(.white.opacity(0.07), in: Capsule())
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
                Image(systemName: symbol)
                    .foregroundStyle(accent)
                Text(title)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
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

private struct WatchWideMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
        }
        .padding(9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func formatDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, secs)
        : String(format: "%02d:%02d", minutes, secs)
}

private func formatDistance(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.2f", meters / 1000) }
    return String(format: "%.0f", meters)
}
