import MapKit
import SwiftUI

struct ActivityHistoryView: View {
    @State private var summaries: [TrackerSummary] = []
    @State private var effectiveActivities: [String: String] = [:]
    @State private var period: HistoryPeriod = .month
    @State private var activityFilter: HistoryActivityFilter = .all
    @State private var searchText = ""

    private let store = NativeSessionStore()
    private let reviewStore = ActivityReviewStore()

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

                            HStack {
                                Label(activityFilter.label, systemImage: activityFilter.symbol)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(filteredSummaries.count) séance\(filteredSummaries.count > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            if filteredSummaries.isEmpty {
                                ContentUnavailableView(
                                    "Aucun résultat",
                                    systemImage: "magnifyingglass",
                                    description: Text("Modifie la période, le sport ou la recherche.")
                                )
                                .padding(.top, 24)
                            } else {
                                ForEach(filteredSummaries) { summary in
                                    NavigationLink {
                                        ActivityDetailView(summary: summary)
                                    } label: {
                                        ActivityHistoryRow(summary: summary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Historique")
            .searchable(text: $searchText, prompt: "Rechercher une activité")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sport", selection: $activityFilter) {
                            ForEach(HistoryActivityFilter.allCases) { filter in
                                Label(filter.label, systemImage: filter.symbol).tag(filter)
                            }
                        }
                    } label: {
                        Image(systemName: activityFilter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filtrer l’historique")
                }
            }
            .onAppear { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var filteredSummaries: [TrackerSummary] {
        let periodFiltered: [TrackerSummary]
        if let threshold = period.threshold {
            periodFiltered = summaries.filter { $0.startedAt >= threshold }
        } else {
            periodFiltered = summaries
        }

        return periodFiltered.filter { summary in
            let rawActivity = effectiveActivities[summary.sessionID] ?? summary.activity
            guard activityFilter.matches(rawActivity) else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let dateText = summary.startedAt.formatted(date: .abbreviated, time: .shortened)
            return activityLabel(rawActivity).localizedCaseInsensitiveContains(query)
                || dateText.localizedCaseInsensitiveContains(query)
                || summary.sessionID.localizedCaseInsensitiveContains(query)
        }
    }

    private func refresh() {
        let loaded = store.listSummaries()
        summaries = loaded
        effectiveActivities = Dictionary(uniqueKeysWithValues: loaded.map { summary in
            (summary.sessionID, reviewStore.effectiveActivity(for: summary))
        })
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

private enum HistoryActivityFilter: String, CaseIterable, Identifiable {
    case all
    case walking
    case running
    case cycling
    case hiking
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tous les sports"
        case .walking: return "Marche"
        case .running: return "Course"
        case .cycling: return "Vélo"
        case .hiking: return "Randonnée"
        case .other: return "Autres"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "figure.mixed.cardio"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .hiking: return "figure.hiking"
        case .other: return "ellipsis.circle"
        }
    }

    func matches(_ rawActivity: String) -> Bool {
        guard self != .all else { return true }
        guard let activity = ActivityKind(rawValue: rawActivity) else { return self == .other }
        switch self {
        case .all: return true
        case .walking: return activity == .walking
        case .running: return activity == .running || activity == .trackAndField
        case .cycling: return activity == .cycling || activity == .handCycling
        case .hiking: return activity == .hiking
        case .other:
            return ![.walking, .running, .trackAndField, .cycling, .handCycling, .hiking].contains(activity)
        }
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
    @State private var comparableSummaries: [TrackerSummary] = []
    @State private var technicalTraceExpanded = false

    private let store = NativeSessionStore()
    private let timelineLoader = SessionTimelineLoader()
    private let reviewStore = ActivityReviewStore()

    private var displayedActivity: String { review?.confirmedActivity ?? summary.activity }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                detailHeader
                heroMetrics
                PersonalComparisonCard(summary: summary, peers: comparableSummaries)

                if route.count > 1 {
                    routeCard
                }

                ActivityReviewCard(summary: summary) { saved in
                    review = saved
                    loadComparisons()
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
        review = reviewStore.load(sessionID: sessionID)
        loadComparisons()
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

    private func loadComparisons() {
        let activity = reviewStore.effectiveActivity(for: summary)
        let all = store.listSummaries()
        let peers = all.filter { candidate in
            guard candidate.sessionID != summary.sessionID else { return false }
            guard reviewStore.effectiveActivity(for: candidate) == activity else { return false }
            guard summary.distanceMeters > 100 else { return true }
            let ratio = candidate.distanceMeters / summary.distanceMeters
            return ratio >= 0.60 && ratio <= 1.40
        }
        comparableSummaries = Array(peers.prefix(8))
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

private struct PersonalComparisonCard: View {
    let summary: TrackerSummary
    let peers: [TrackerSummary]

    var body: some View {
        if !peers.isEmpty {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("COMPARAISON PERSONNELLE", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(peers.count) sortie\(peers.count > 1 ? "s" : "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let pace = paceComparison {
                    ComparisonRow(title: "Allure", current: pace.current, reference: pace.reference, insight: pace.insight)
                }
                if let heart = heartComparison {
                    ComparisonRow(title: "FC moyenne", current: heart.current, reference: heart.reference, insight: heart.insight)
                }
                if let cadence = cadenceComparison {
                    ComparisonRow(title: "Cadence", current: cadence.current, reference: cadence.reference, insight: cadence.insight)
                }

                Text("Repère = jusqu’aux 8 sorties les plus récentes du même sport, avec une distance comprise entre 60 % et 140 % de cette séance.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var paceComparison: (current: String, reference: String, insight: String)? {
        guard let current = paceSeconds(summary) else { return nil }
        let values = peers.compactMap(paceSeconds)
        guard !values.isEmpty else { return nil }
        let reference = values.reduce(0, +) / Double(values.count)
        let delta = (current - reference) / reference
        let insight: String
        if abs(delta) < 0.03 {
            insight = "proche de ton repère"
        } else if delta < 0 {
            insight = String(format: "%.0f %% plus rapide", abs(delta) * 100)
        } else {
            insight = String(format: "%.0f %% plus lente", delta * 100)
        }
        return (paceText(current), paceText(reference), insight)
    }

    private var heartComparison: (current: String, reference: String, insight: String)? {
        guard summary.averageHeartRate > 0 else { return nil }
        let values = peers.map(\.averageHeartRate).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let reference = values.reduce(0, +) / Double(values.count)
        let difference = summary.averageHeartRate - reference
        let insight = abs(difference) < 2
            ? "proche de ton repère"
            : String(format: "%@%.0f bpm vs repère", difference > 0 ? "+" : "", difference)
        return (
            String(format: "%.0f bpm", summary.averageHeartRate),
            String(format: "%.0f bpm", reference),
            insight
        )
    }

    private var cadenceComparison: (current: String, reference: String, insight: String)? {
        guard let current = summary.averageCadenceSPM, current > 0 else { return nil }
        let values = peers.compactMap(\.averageCadenceSPM).filter { $0 > 0 }
        guard !values.isEmpty else { return nil }
        let reference = values.reduce(0, +) / Double(values.count)
        let difference = current - reference
        let insight = abs(difference) < 2
            ? "proche de ton repère"
            : String(format: "%@%.0f pas/min", difference > 0 ? "+" : "", difference)
        return (
            String(format: "%.0f", current),
            String(format: "%.0f", reference),
            insight
        )
    }

    private func paceSeconds(_ value: TrackerSummary) -> Double? {
        guard value.distanceMeters > 100, value.duration > 0 else { return nil }
        return value.duration / (value.distanceMeters / 1000)
    }

    private func paceText(_ seconds: Double) -> String {
        let rounded = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d/km", rounded / 60, rounded % 60)
    }
}

private struct ComparisonRow: View {
    let title: String
    let current: String
    let reference: String
    let insight: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(current).font(.subheadline.weight(.bold)).monospacedDigit()
            }
            Text("Repère \(reference) · \(insight)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
