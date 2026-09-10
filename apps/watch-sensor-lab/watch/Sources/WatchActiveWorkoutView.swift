import MapKit
import SwiftUI

struct ActiveWorkoutView: View {
    var body: some View {
        NavigationStack {
            TabView {
                WatchPrimaryMetricsPage()
                WatchEffortMetricsPage()
                WatchRouteTerrainPage()
                WatchControlsPage()
            }
            .tabViewStyle(.page)
        }
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
                .font(.system(size: 34, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.76)

            HStack(spacing: 8) {
                NavigationLink {
                    WatchMovementDepthView()
                } label: {
                    WatchMetricCard(
                        title: "DISTANCE",
                        value: model.elapsedSeconds > 4 ? formatDistance(model.distanceMeters) : "—",
                        unit: model.distanceMeters >= 1000 ? "km" : "m",
                        symbol: model.displayActivity.symbol,
                        accent: .mint,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    WatchHeartDepthView()
                } label: {
                    WatchMetricCard(
                        title: "CŒUR",
                        value: model.heartRate > 0 ? String(format: "%.0f", model.heartRate) : "—",
                        unit: "bpm",
                        symbol: "heart.fill",
                        accent: .red,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Label(speedLabel, systemImage: "speedometer")
                Spacer()
                Label(model.elapsedSeconds > 4 ? "+\(Int(model.elevationGainMeters)) m" : "D+ —", systemImage: "arrow.up.right")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text("←/→ vues · touche une carte pour le détail")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text("EFFORT")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.orange)
                    Text("Cardio & énergie")
                        .font(.caption.weight(.bold))
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 8) {
                NavigationLink { WatchHeartDepthView() } label: {
                    WatchMetricCard(
                        title: "FC MOY.",
                        value: model.averageHeartRate > 0 ? String(format: "%.0f", model.averageHeartRate) : "—",
                        unit: "bpm",
                        symbol: "heart.text.square.fill",
                        accent: .red,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)

                NavigationLink { WatchEnergyDepthView() } label: {
                    WatchMetricCard(
                        title: "CALORIES",
                        value: model.activeEnergyKcal > 0 ? String(format: "%.0f", model.activeEnergyKcal) : "—",
                        unit: "kcal",
                        symbol: "flame.fill",
                        accent: .orange,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                WatchMetricCard(
                    title: "CADENCE",
                    value: model.cadenceSPM > 0 ? String(format: "%.0f", model.cadenceSPM) : "—",
                    unit: cadenceUnit,
                    symbol: "metronome.fill",
                    accent: .cyan
                )
                WatchMetricCard(
                    title: "PAS",
                    value: model.steps > 0 ? "\(model.steps)" : "—",
                    unit: "pas",
                    symbol: "shoeprints.fill",
                    accent: .mint
                )
            }

            Text("L’effort 1–10 final sera calculé après la séance avec le ressenti séparé.")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 2)
    }

    private var cadenceUnit: String {
        switch model.displayActivity {
        case .cycling, .handCycling: return "cadence"
        default: return "pas/min"
        }
    }
}

private struct WatchRouteTerrainPage: View {
    @EnvironmentObject private var model: SensorModel
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("ROUTE / TERRAIN")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.mint)
                Spacer()
                NavigationLink {
                    WatchTerrainDepthView()
                } label: {
                    Image(systemName: "mountain.2.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.mint)
                        .frame(width: 28, height: 28)
                        .background(.mint.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }

            if shouldShowMap {
                Map(position: $position, interactionModes: []) {
                    UserAnnotation()
                    if model.route.count > 1 {
                        MapPolyline(coordinates: model.route)
                            .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "map.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Carte masquée pour ce sport")
                        .font(.caption.weight(.bold))
                    Text("Le terrain reste accessible si des données d’altitude existent.")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            HStack(spacing: 8) {
                CompactTerrainValue(title: "ALT", value: model.elapsedSeconds > 4 ? "\(Int(model.altitudeMeters)) m" : "—")
                CompactTerrainValue(title: "D+", value: model.elapsedSeconds > 4 ? "+\(Int(model.elevationGainMeters)) m" : "—")
                CompactTerrainValue(title: "GPS", value: model.horizontalAccuracy >= 0 ? "±\(Int(model.horizontalAccuracy)) m" : "—")
            }
        }
        .onAppear { recenter() }
        .onChange(of: model.route.count) { _, _ in recenter() }
        .padding(.horizontal, 2)
    }

    private var shouldShowMap: Bool {
        switch model.displayActivity {
        case .walking, .running, .hiking, .cycling, .handCycling, .swimBikeRun,
             .crossCountrySkiing, .downhillSkiing, .snowSports, .snowboarding,
             .skatingSports, .wheelchairWalkPace, .wheelchairRunPace:
            return true
        default:
            return model.route.count > 2
        }
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
            HStack {
                Text("CONTRÔLES")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatDuration(model.elapsedSeconds))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
            }

            Spacer(minLength: 0)

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }
}

private struct WatchMovementDepthView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        TabView {
            depthPage(
                title: "Distance",
                value: formatDistanceWithUnit(model.distanceMeters),
                symbol: model.displayActivity.symbol,
                accent: .mint,
                lines: [
                    ("Temps", formatDuration(model.elapsedSeconds)),
                    ("Vitesse", model.horizontalAccuracy >= 0 ? String(format: "%.1f km/h", model.currentSpeedMps * 3.6) : "—"),
                ]
            )
            depthPage(
                title: "Relief",
                value: "+\(Int(model.elevationGainMeters)) m",
                symbol: "mountain.2.fill",
                accent: .green,
                lines: [
                    ("Altitude", model.elapsedSeconds > 4 ? "\(Int(model.altitudeMeters)) m" : "—"),
                    ("Descente", model.elapsedSeconds > 4 ? "-\(Int(model.elevationLossMeters)) m" : "—"),
                ]
            )
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle("Mouvement")
    }
}

private struct WatchHeartDepthView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        TabView {
            depthPage(
                title: "Fréquence cardiaque",
                value: model.heartRate > 0 ? "\(Int(model.heartRate.rounded())) bpm" : "—",
                symbol: "heart.fill",
                accent: .red,
                lines: [
                    ("Moyenne", model.averageHeartRate > 0 ? "\(Int(model.averageHeartRate.rounded())) bpm" : "—"),
                    ("État", model.isPaused ? "En pause" : "Mesure en cours"),
                ]
            )
            VStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.pink)
                Text("Zones détaillées")
                    .font(.headline.weight(.black))
                Text("Les zones complètes sont consolidées après la séance à partir des échantillons enregistrés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle("Cardio")
    }
}

private struct WatchEnergyDepthView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        depthPage(
            title: "Énergie",
            value: model.activeEnergyKcal > 0 ? "\(Int(model.activeEnergyKcal.rounded())) kcal" : "—",
            symbol: "flame.fill",
            accent: .orange,
            lines: [
                ("Temps actif", formatDuration(model.elapsedSeconds)),
                ("FC moyenne", model.averageHeartRate > 0 ? "\(Int(model.averageHeartRate.rounded())) bpm" : "—"),
            ]
        )
        .navigationTitle("Énergie")
    }
}

private struct WatchTerrainDepthView: View {
    @EnvironmentObject private var model: SensorModel

    var body: some View {
        TabView {
            depthPage(
                title: "Altitude",
                value: model.elapsedSeconds > 4 ? "\(Int(model.altitudeMeters)) m" : "—",
                symbol: "mountain.2.fill",
                accent: .mint,
                lines: [
                    ("Montée", "+\(Int(model.elevationGainMeters)) m"),
                    ("Descente", "-\(Int(model.elevationLossMeters)) m"),
                ]
            )
            depthPage(
                title: "GPS",
                value: model.horizontalAccuracy >= 0 ? "±\(Int(model.horizontalAccuracy)) m" : "—",
                symbol: "location.fill",
                accent: gpsAccent(model.horizontalAccuracy),
                lines: [
                    ("Points route", "\(model.route.count)"),
                    ("Vitesse", model.horizontalAccuracy >= 0 ? String(format: "%.1f km/h", model.currentSpeedMps * 3.6) : "—"),
                ]
            )
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle("Terrain")
    }
}

private struct WatchMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var accent: Color = .green
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title)
                Spacer(minLength: 0)
                if showsDisclosure {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.64)
                .lineLimit(1)

            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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

private func depthPage(title: String, value: String, symbol: String, accent: Color, lines: [(String, String)]) -> some View {
    VStack(spacing: 9) {
        HStack {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(accent)
            Spacer()
        }
        Text(value)
            .font(.system(size: 30, weight: .black, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.65)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
        Text(title)
            .font(.caption.weight(.black))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        ForEach(Array(lines.enumerated()), id: \.offset) { _, item in
            HStack {
                Text(item.0).foregroundStyle(.secondary)
                Spacer()
                Text(item.1).fontWeight(.bold).monospacedDigit()
            }
            .font(.caption)
        }
    }
    .padding(.horizontal, 6)
}

private func gpsAccent(_ accuracy: Double) -> Color {
    guard accuracy >= 0 else { return .orange }
    if accuracy < 8 { return .mint }
    if accuracy < 20 { return .yellow }
    return .orange
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

private func formatDistanceWithUnit(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}
