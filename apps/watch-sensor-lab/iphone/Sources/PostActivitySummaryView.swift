import MapKit
import SwiftUI

struct PostActivitySummaryView: View {
    let summary: TrackerSummary

    @Environment(\.dismiss) private var dismiss
    @State private var route: [CLLocationCoordinate2D] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var healthContext = HealthContextReport.empty
    @State private var effort = SessionEffortReport.empty
    @State private var contextLoading = true
    @State private var review: ActivityReviewRecord?
    @State private var timeline: [SessionTimelinePoint] = []

    private let store = NativeSessionStore()
    private let healthReader = HealthContextReader()
    private let effortAnalyzer = SessionEffortAnalyzer()
    private let timelineLoader = SessionTimelineLoader()

    private var displayedActivity: String { review?.confirmedActivity ?? summary.activity }
    private var activityConfirmed: Bool { review != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    completionHeader

                    ActivityReviewCard(summary: summary, requiresConfirmation: true) { saved in
                        review = saved
                    }

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
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    metricsGrid
                    segmentsSection
                    SessionTimelineView(points: timeline)
                    environmentSection
                    healthContextSection
                    technicalTrace
                }
                .padding()
            }
            .navigationTitle("Résumé")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Terminé") { dismiss() }
                        .disabled(!activityConfirmed)
                }
            }
            .task { loadContext() }
        }
        .interactiveDismissDisabled(!activityConfirmed)
        .preferredColorScheme(.dark)
    }

    private var completionHeader: some View {
        VStack(spacing: 7) {
            Image(systemName: activitySymbol(displayedActivity))
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(.mint)
            Text(activityLabel(displayedActivity))
                .font(.title2.weight(.black))
            Text(summary.startedAt, format: .dateTime.day().month().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if !activityConfirmed {
                Label("Confirme le type d’activité avant de fermer", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if review?.changedByUser == true {
                Text("Détection corrigée par l’utilisateur")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            SummaryMetric(title: "DISTANCE", value: distanceText(summary.distanceMeters), symbol: "point.topleft.down.to.point.bottomright.curvepath")
            SummaryMetric(title: "TEMPS ACTIF", value: durationText(summary.duration), symbol: "timer")
            SummaryMetric(title: "ALLURE MOY.", value: averagePaceText(summary), symbol: "figure.walk")
            SummaryMetric(title: "FC MOY.", value: summary.averageHeartRate > 0 ? String(format: "%.0f bpm", summary.averageHeartRate) : "—", symbol: "heart.fill")
            SummaryMetric(title: "FC MAX", value: summary.maxHeartRate.map { String(format: "%.0f bpm", $0) } ?? "—", symbol: "heart.circle.fill")
            SummaryMetric(title: "CALORIES", value: summary.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", symbol: "flame.fill")
            SummaryMetric(title: "DÉNIVELÉ", value: String(format: "+%.0f / -%.0f m", summary.elevationGainMeters, summary.elevationLossMeters), symbol: "mountain.2.fill")
            SummaryMetric(title: "VITESSE MAX", value: summary.maxSpeedMps > 0 ? String(format: "%.1f km/h", summary.maxSpeedMps * 3.6) : "—", symbol: "speedometer")
            SummaryMetric(title: "CADENCE", value: summary.averageCadenceSPM.map { String(format: "%.0f pas/min", $0) } ?? "—", symbol: "metronome.fill")
        }
    }

    @ViewBuilder
    private var segmentsSection: some View {
        if let segments = summary.segments, !segments.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Text("SEGMENTS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                ForEach(segments) { segment in
                    HStack(spacing: 10) {
                        Image(systemName: segmentSymbol(segment.activity))
                            .frame(width: 24)
                            .foregroundStyle(segment.activity == "transition" ? Color.blue : Color.mint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(segmentLabel(segment.activity)).font(.subheadline.weight(.bold))
                            if let ended = segment.endedAt {
                                Text(durationText(ended.timeIntervalSince(segment.startedAt)))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let distance = segment.distanceMeters {
                            Text(distanceText(distance))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        if effort.averageTemperatureC != nil || effort.averageWindSpeedKPH != nil || effort.note != nil {
            VStack(alignment: .leading, spacing: 9) {
                Text("ENVIRONNEMENT / EFFORT")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    if let temperature = effort.averageTemperatureC {
                        ContextValue(label: "Température", value: String(format: "%.1f °C", temperature))
                    }
                    if let apparent = effort.averageApparentTemperatureC {
                        ContextValue(label: "Ressenti", value: String(format: "%.1f °C", apparent))
                    }
                    if let humidity = effort.averageHumidityPercent {
                        ContextValue(label: "Humidité", value: String(format: "%.0f %%", humidity))
                    }
                }

                HStack(spacing: 14) {
                    if let wind = effort.averageWindSpeedKPH {
                        ContextValue(label: "Vent", value: String(format: "%.0f km/h", wind))
                    }
                    if let gust = effort.peakWindGustKPH {
                        ContextValue(label: "Rafales", value: String(format: "%.0f km/h", gust))
                    }
                    if let headwind = effort.averageHeadwindComponentKPH {
                        ContextValue(
                            label: headwind >= 0 ? "Face" : "Arrière",
                            value: String(format: "%.0f km/h", abs(headwind))
                        )
                    }
                }

                if let pressure = summary.weatherSnapshots?.compactMap(\.pressureHPA).average {
                    ContextValue(label: "Pression moy.", value: String(format: "%.0f hPa", pressure))
                }

                if let note = effort.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }

                Text("Contexte descriptif calculé à partir des snapshots météo et du cap du parcours ; ce n’est pas un score médical.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var healthContextSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CONTEXTE SANTÉ")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            if contextLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Recherche des métriques disponibles…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if healthContext.metrics.isEmpty {
                Text(healthContext.note ?? "Aucune donnée contextuelle disponible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(healthContext.metrics) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(metric.label).font(.caption.weight(.semibold))
                            Spacer()
                            Text(metric.value).font(.caption.weight(.bold)).monospacedDigit()
                        }
                        Text(metric.detail).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                if let note = healthContext.note {
                    Text(note).font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var technicalTrace: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TRACE TECHNIQUE").font(.caption2.weight(.black)).foregroundStyle(.secondary)
            Text("Session \(summary.sessionID)").font(.caption.monospaced())
            if let review {
                Text("Détecté \(review.detectedActivity) · confirmé \(review.confirmedActivity)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text("Santé: \(review.healthKitSyncState)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(review.changedByUser ? .orange : .secondary)
            }
            if let build = summary.buildSHA { Text("Build \(build)").font(.caption2.monospaced()).foregroundStyle(.secondary) }
            if let algorithm = summary.algorithmVersion { Text(algorithm).font(.caption2.monospaced()).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadContext() {
        let sessionID = summary.sessionID
        review = ActivityReviewStore().load(sessionID: sessionID)
        DispatchQueue.global(qos: .userInitiated).async {
            let loadedRoute = store.loadRoute(sessionID: sessionID)
            let effortReport = effortAnalyzer.analyze(summary: summary)
            let loadedTimeline = timelineLoader.load(sessionID: sessionID)
            DispatchQueue.main.async {
                route = loadedRoute
                effort = effortReport
                timeline = loadedTimeline
                if !loadedRoute.isEmpty {
                    cameraPosition = .region(region(for: loadedRoute))
                }
            }
        }

        healthReader.load(for: summary) { report in
            healthContext = report
            contextLoading = false
        }
    }

    private func region(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        guard let minLat = latitudes.min(), let maxLat = latitudes.max(),
              let minLon = longitudes.min(), let maxLon = longitudes.max() else {
            return MKCoordinateRegion()
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.006, (maxLat - minLat) * 1.25),
                longitudeDelta: max(0.006, (maxLon - minLon) * 1.25)
            )
        )
    }
}

private struct SummaryMetric: View {
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

private struct ContextValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

private func activityLabel(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.label ?? (raw == "transition" ? "Transition" : raw)
}

private func activitySymbol(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.symbol ?? (raw == "transition" ? "arrow.triangle.2.circlepath" : "figure.mixed.cardio")
}

private func segmentLabel(_ raw: String) -> String { activityLabel(raw) }
private func segmentSymbol(_ raw: String) -> String { activitySymbol(raw) }

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
