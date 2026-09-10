import MapKit
import SwiftUI

struct ActivityHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summaries: [TrackerSummary] = []

    private let store = NativeSessionStore()

    var body: some View {
        NavigationStack {
            Group {
                if summaries.isEmpty {
                    ContentUnavailableView(
                        "Aucune activité",
                        systemImage: "figure.walk",
                        description: Text("Les activités terminées apparaîtront ici et resteront disponibles après les mises à jour de l’app.")
                    )
                } else {
                    List(summaries) { summary in
                        NavigationLink {
                            ActivityDetailView(summary: summary)
                        } label: {
                            ActivityHistoryRow(summary: summary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Activités")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                }
            }
            .onAppear { summaries = store.listSummaries() }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ActivityHistoryRow: View {
    let summary: TrackerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(activityLabel(summary.activity), systemImage: activitySymbol(summary.activity))
                    .font(.headline.weight(.bold))
                Spacer()
                Text(summary.startedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                HistoryValue(value: distanceText(summary.distanceMeters), label: "Distance")
                HistoryValue(value: durationText(summary.duration), label: "Temps")
                HistoryValue(value: summary.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", label: "Énergie")
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ActivityDetailView: View {
    let summary: TrackerSummary

    @State private var route: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic

    private let store = NativeSessionStore()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if route.count > 1 {
                    Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                        MapPolyline(coordinates: route)
                            .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        if let first = route.first {
                            Annotation("Départ", coordinate: first) {
                                Image(systemName: "flag.fill")
                                    .padding(8)
                                    .background(.black.opacity(0.75), in: Circle())
                                    .foregroundStyle(.mint)
                            }
                        }
                    }
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DetailMetric(title: "DISTANCE", value: distanceText(summary.distanceMeters), symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    DetailMetric(title: "TEMPS ACTIF", value: durationText(summary.duration), symbol: "timer")
                    DetailMetric(title: "ALLURE MOY.", value: averagePaceText(summary), symbol: "figure.walk")
                    DetailMetric(title: "FC MOY.", value: summary.averageHeartRate > 0 ? String(format: "%.0f bpm", summary.averageHeartRate) : "—", symbol: "heart.fill")
                    DetailMetric(title: "CALORIES", value: summary.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", symbol: "flame.fill")
                    DetailMetric(title: "DÉNIVELÉ", value: String(format: "+%.0f / -%.0f m", summary.elevationGainMeters, summary.elevationLossMeters), symbol: "mountain.2.fill")
                    DetailMetric(title: "VITESSE MAX", value: summary.maxSpeedMps > 0 ? String(format: "%.1f km/h", summary.maxSpeedMps * 3.6) : "—", symbol: "speedometer")
                    DetailMetric(title: "CADENCE", value: summary.averageCadenceSPM.map { String(format: "%.0f pas/min", $0) } ?? "—", symbol: "metronome.fill")
                }

                if let weather = summary.weatherSnapshots, !weather.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("MÉTÉO").font(.caption.weight(.black)).foregroundStyle(.secondary)
                        ForEach(weather) { snapshot in
                            WeatherHistoryRow(snapshot: snapshot)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("TRACE TECHNIQUE").font(.caption2.weight(.black)).foregroundStyle(.secondary)
                    Text("Session \(summary.sessionID)").font(.caption.monospaced())
                    if let build = summary.buildSHA { Text("Build \(build)").font(.caption2.monospaced()).foregroundStyle(.secondary) }
                    if let algorithm = summary.algorithmVersion { Text(algorithm).font(.caption2.monospaced()).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(activityLabel(summary.activity))
        .navigationBarTitleDisplayMode(.inline)
        .task { loadRoute() }
    }

    private func loadRoute() {
        let sessionID = summary.sessionID
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = store.loadRoute(sessionID: sessionID)
            DispatchQueue.main.async {
                route = loaded
                guard !loaded.isEmpty else { return }
                cameraPosition = .region(region(for: loaded))
            }
        }
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return MKCoordinateRegion()
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.006, (maxLat - minLat) * 1.25),
                longitudeDelta: max(0.006, (maxLon - minLon) * 1.25)
            )
        )
    }
}

private struct WeatherHistoryRow: View {
    let snapshot: SessionWeatherSnapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "cloud.sun.fill").frame(width: 24).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(snapshot.temperatureC.map { String(format: "%.1f °C", $0) } ?? "—")
                        .font(.headline.monospacedDigit())
                    if let apparent = snapshot.apparentTemperatureC {
                        Text("ressenti \(String(format: "%.1f°", apparent))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if let humidity = snapshot.relativeHumidityPercent { Text("\(Int(humidity)) % hum.") }
                    if let wind = snapshot.windSpeedKPH { Text("vent \(String(format: "%.0f", wind)) km/h") }
                    if let gust = snapshot.windGustKPH { Text("raf. \(String(format: "%.0f", gust))") }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(snapshot.timestamp, format: .dateTime.hour().minute())
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct HistoryValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.headline.weight(.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func activityLabel(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.label ?? raw
}

private func activitySymbol(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.symbol ?? "figure.mixed.cardio"
}

private func distanceText(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func durationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}

private func averagePaceText(_ summary: TrackerSummary) -> String {
    guard summary.distanceMeters > 10, summary.duration > 0 else { return "—" }
    let secondsPerKm = Int(summary.duration / (summary.distanceMeters / 1000))
    return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
}
