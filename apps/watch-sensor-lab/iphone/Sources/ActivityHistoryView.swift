import MapKit
import SwiftUI

struct ActivityHistoryView: View {
    @State private var summaries: [TrackerSummary] = []
    @State private var period: HistoryPeriod = .month

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
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            HistoryOverviewCard(summaries: filteredSummaries)

                            Picker("Période", selection: $period) {
                                ForEach(HistoryPeriod.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            ForEach(filteredSummaries) { summary in
                                NavigationLink {
                                    ActivityDetailView(summary: summary)
                                } label: {
                                    ActivityHistoryRow(summary: summary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Historique")
            .onAppear { summaries = store.listSummaries() }
        }
        .preferredColorScheme(.dark)
    }

    private var filteredSummaries: [TrackerSummary] {
        guard let threshold = period.threshold else { return summaries }
        return summaries.filter { $0.startedAt >= threshold }
    }
}

private enum HistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: return "7 j"
        case .month: return "30 j"
        case .all: return "Tout"
        }
    }

    var threshold: Date? {
        let days: Int
        switch self {
        case .week: days = 7
        case .month: days = 30
        case .all: return nil
        }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }
}

private struct HistoryOverviewCard: View {
    let summaries: [TrackerSummary]

    private var distance: Double { summaries.reduce(0) { $0 + $1.distanceMeters } }
    private var duration: TimeInterval { summaries.reduce(0) { $0 + $1.duration } }
    private var energy: Double { summaries.compactMap(\.activeEnergyKcal).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("VUE D’ENSEMBLE")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                HistoryOverviewMetric(value: "\(summaries.count)", label: "séances")
                HistoryOverviewMetric(value: historyDistance(distance), label: "distance")
                HistoryOverviewMetric(value: historyDuration(duration), label: "temps")
            }

            if energy > 0 {
                Label("\(Int(energy.rounded())) kcal actives", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct HistoryOverviewMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActivityHistoryRow: View {
    let summary: TrackerSummary
    @State private var review: ActivityReviewRecord?

    private var displayedActivity: String { review?.confirmedActivity ?? summary.activity }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                Image(systemName: activitySymbol(displayedActivity))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 32, height: 32)
                    .background(.mint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(activityLabel(displayedActivity))
                            .font(.headline.weight(.bold))
                        if review?.changedByUser == true {
                            Text("CORRIGÉ")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(summary.startedAt, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 18) {
                HistoryValue(value: distanceText(summary.distanceMeters), label: "Distance")
                HistoryValue(value: durationText(summary.duration), label: "Temps")
                HistoryValue(value: summary.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", label: "Énergie")
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onAppear { review = ActivityReviewStore().load(sessionID: summary.sessionID) }
    }
}

private struct ActivityDetailView: View {
    let summary: TrackerSummary

    @State private var route: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var timeline: [SessionTimelinePoint] = []
    @State private var review: ActivityReviewRecord?
    @State private var technicalTraceExpanded = false

    private let store = NativeSessionStore()
    private let timelineLoader = SessionTimelineLoader()

    private var displayedActivity: String { review?.confirmedActivity ?? summary.activity }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                detailHeader
                heroMetrics

                if route.count > 1 {
                    routeCard
                }

                ActivityReviewCard(summary: summary) { saved in
                    review = saved
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    DetailMetric(title: "CALORIES", value: summary.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", symbol: "flame.fill")
                    DetailMetric(title: "DÉNIVELÉ", value: String(format: "+%.0f / -%.0f m", summary.elevationGainMeters, summary.elevationLossMeters), symbol: "mountain.2.fill")
                    DetailMetric(title: "VITESSE MAX", value: summary.maxSpeedMps > 0 ? String(format: "%.1f km/h", summary.maxSpeedMps * 3.6) : "—", symbol: "speedometer")
                    DetailMetric(title: "CADENCE", value: summary.averageCadenceSPM.map { String(format: "%.0f pas/min", $0) } ?? "—", symbol: "metronome.fill")
                }

                SessionPauseSummaryView(summary: summary)
                SessionTimelineView(points: timeline)
                weatherSection
                technicalTrace
            }
            .padding()
        }
        .navigationTitle(activityLabel(displayedActivity))
        .navigationBarTitleDisplayMode(.inline)
        .task { loadSessionData() }
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: activitySymbol(displayedActivity))
                .font(.title2.weight(.semibold))
                .foregroundStyle(.mint)
                .frame(width: 46, height: 46)
                .background(.mint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(activityLabel(displayedActivity))
                    .font(.title2.weight(.bold))
                Text(summary.startedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroMetrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            DetailMetric(title: "DISTANCE", value: distanceText(summary.distanceMeters), symbol: "point.topleft.down.to.point.bottomright.curvepath", prominent: true)
            DetailMetric(title: "TEMPS ACTIF", value: durationText(summary.duration), symbol: "timer", prominent: true)
            DetailMetric(title: "ALLURE MOY.", value: averagePaceText(summary), symbol: "figure.walk", prominent: true)
            DetailMetric(title: "FC MOY.", value: summary.averageHeartRate > 0 ? String(format: "%.0f bpm", summary.averageHeartRate) : "—", symbol: "heart.fill", prominent: true)
        }
    }

    private var routeCard: some View {
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
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var weatherSection: some View {
        if let weather = summary.weatherSnapshots, !weather.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("ENVIRONNEMENT")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                ForEach(weather) { snapshot in
                    WeatherHistoryRow(snapshot: snapshot)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var technicalTrace: some View {
        DisclosureGroup("Qualité et trace technique", isExpanded: $technicalTraceExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session \(summary.sessionID)").font(.caption.monospaced())
                if let review {
                    Text("Activité détectée \(review.detectedActivity) · confirmée \(review.confirmedActivity)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    Text("Santé: \(review.healthKitSyncState)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                if let build = summary.buildSHA {
                    Text("Build \(build)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                if let algorithm = summary.algorithmVersion {
                    Text(algorithm).font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.semibold))
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func loadSessionData() {
        let sessionID = summary.sessionID
        review = ActivityReviewStore().load(sessionID: sessionID)
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedRoute = store.loadRoute(sessionID: sessionID)
            let loadedTimeline = timelineLoader.load(sessionID: sessionID)
            DispatchQueue.main.async {
                route = loadedRoute
                timeline = loadedTimeline
                guard !loadedRoute.isEmpty else { return }
                cameraPosition = .region(region(for: loadedRoute))
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
            Image(systemName: "cloud.sun.fill")
                .frame(width: 24)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(snapshot.temperatureC.map { String(format: "%.1f °C", $0) } ?? "—")
                        .font(.headline.monospacedDigit())
                    if let apparent = snapshot.apparentTemperatureC {
                        Text("ressenti \(String(format: "%.1f°", apparent))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if let humidity = snapshot.relativeHumidityPercent { Text("\(Int(humidity)) % hum.") }
                    if let pressure = snapshot.pressureHPA { Text("\(Int(pressure)) hPa") }
                    if let wind = snapshot.windSpeedKPH { Text("vent \(String(format: "%.0f", wind)) km/h") }
                    if let gust = snapshot.windGustKPH { Text("raf. \(String(format: "%.0f", gust))") }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(snapshot.timestamp, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)
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
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(prominent ? .title3.weight(.bold) : .headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: prominent ? 82 : 70, alignment: .leading)
        .padding(11)
        .background(.white.opacity(prominent ? 0.08 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

private func historyDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func durationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}

private func historyDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : "\(minutes) min"
}

private func averagePaceText(_ summary: TrackerSummary) -> String {
    guard summary.distanceMeters > 10, summary.duration > 0 else { return "—" }
    let secondsPerKm = Int(summary.duration / (summary.distanceMeters / 1000))
    return String(format: "%d:%02d /km", secondsPerKm / 60, secondsPerKm % 60)
}
