import Charts
import Foundation
import SwiftUI

enum ProgressionRange: String, CaseIterable, Identifiable {
    case week
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "7 j"
        case .month: return "1 mois"
        case .sixMonths: return "6 mois"
        case .year: return "1 an"
        case .all: return "Tout"
        }
    }

    func startDate(now: Date, records: [HealthWorkoutRecord]) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        case .month:
            return calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast
        case .year:
            return calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        case .all:
            return records.map(\.startedAt).min() ?? now
        }
    }

    func previousStart(now: Date, records: [HealthWorkoutRecord]) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        switch self {
        case .week:
            return calendar.date(byAdding: .day, value: -14, to: now)
        case .month:
            return calendar.date(byAdding: .month, value: -2, to: now)
        case .sixMonths:
            return calendar.date(byAdding: .year, value: -1, to: now)
        case .year:
            return calendar.date(byAdding: .year, value: -2, to: now)
        case .all:
            return nil
        }
    }

    var bucketStyle: ProgressionBucketStyle {
        switch self {
        case .week, .month: return .day
        case .sixMonths, .year: return .week
        case .all: return .month
        }
    }
}

private enum ProgressionBucketStyle {
    case day
    case week
    case month
}

private enum ProgressionMetric: String, CaseIterable, Identifiable {
    case duration
    case distance
    case sessions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duration: return "Temps"
        case .distance: return "Distance"
        case .sessions: return "Séances"
        }
    }

    var symbol: String {
        switch self {
        case .duration: return "clock.fill"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .sessions: return "figure.run"
        }
    }
}

private struct ProgressionAggregate {
    let count: Int
    let duration: TimeInterval
    let distanceMeters: Double
    let energyKcal: Double

    static let empty = ProgressionAggregate(count: 0, duration: 0, distanceMeters: 0, energyKcal: 0)
}

private struct ProgressionBucket: Identifiable {
    let start: Date
    let count: Int
    let duration: TimeInterval
    let distanceMeters: Double

    var id: Date { start }
}

private struct SportSlice: Identifiable {
    let rawActivity: String
    let label: String
    let symbol: String
    let duration: TimeInterval

    var id: String { rawActivity }
}

struct PerformanceProgressionView: View {
    @State private var workouts: [HealthWorkoutRecord] = []
    @State private var health = HealthProgressionData.empty
    @State private var range: ProgressionRange = .month
    @State private var metric: ProgressionMetric = .duration
    @State private var selectedSportRaw = "all"
    @State private var loading = true

    private let historyReader = HealthWorkoutHistoryReader()
    private let healthReader = HealthProgressionReader()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero
                    periodSelector
                    activitySummary
                    trendChart
                    sportComposition
                    healthSignals
                    sourceNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [Color.indigo.opacity(0.16), Color.black, Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Progression")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sportMenu
                }
            }
            .refreshable { refresh() }
            .onAppear { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VUE PERFORMANCE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                    Text(heroTitle)
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Image(systemName: "chart.xyaxis.line")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .padding(10)
                    .background(.cyan.opacity(0.14), in: Circle())
            }

            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.38), Color.cyan.opacity(0.12), Color.white.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var periodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgressionRange.allCases) { item in
                    Button {
                        withAnimation(.snappy) { range = item }
                    } label: {
                        Text(item.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(range == item ? Color.black : Color.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(
                                range == item ? Color.cyan : Color.white.opacity(0.08),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activitySummary: some View {
        let current = aggregate(currentRecords)
        let previous = aggregate(previousRecords)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(rangeSummaryTitle, systemImage: "bolt.heart.fill")
                    .font(.headline.weight(.bold))
                Spacer()
                if selectedSportRaw != "all" {
                    Text(activityLabel(selectedSportRaw))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.cyan)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ProgressionMetricCard(
                    title: "TEMPS ACTIF",
                    value: progressionDuration(current.duration),
                    delta: deltaText(current.duration, previous.duration),
                    symbol: "clock.fill",
                    accent: .cyan
                )
                ProgressionMetricCard(
                    title: "DISTANCE",
                    value: progressionDistance(current.distanceMeters),
                    delta: deltaText(current.distanceMeters, previous.distanceMeters),
                    symbol: "location.fill",
                    accent: .mint
                )
                ProgressionMetricCard(
                    title: "SÉANCES",
                    value: "\(current.count)",
                    delta: deltaText(Double(current.count), Double(previous.count)),
                    symbol: "figure.run",
                    accent: .orange
                )
                ProgressionMetricCard(
                    title: "ÉNERGIE",
                    value: current.energyKcal > 0 ? "\(Int(current.energyKcal.rounded())) kcal" : "—",
                    delta: current.energyKcal > 0 ? deltaText(current.energyKcal, previous.energyKcal) : nil,
                    symbol: "flame.fill",
                    accent: .pink
                )
            }

            if let comparison = comparisonSentence(current: current, previous: previous) {
                Label(comparison, systemImage: comparisonSymbol(current: current, previous: previous))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .progressionCard()
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TENDANCE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(metric.label)
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Menu {
                    ForEach(ProgressionMetric.allCases) { option in
                        Button {
                            metric = option
                        } label: {
                            Label(option.label, systemImage: option.symbol)
                        }
                    }
                } label: {
                    Label(metric.label, systemImage: metric.symbol)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if buckets.isEmpty {
                ContentUnavailableView(
                    "Pas encore de tendance",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Aucune séance Santé lisible sur cette période.")
                )
                .frame(height: 180)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Période", bucket.start, unit: chartCalendarUnit),
                        y: .value(metric.label, chartValue(bucket))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .indigo],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .cornerRadius(4)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.05))
                        AxisTick().foregroundStyle(.secondary)
                        AxisValueLabel(format: chartDateFormat)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel()
                    }
                }
            }
        }
        .progressionCard()
    }

    @ViewBuilder
    private var sportComposition: some View {
        let slices = sportSlices
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RÉPARTITION DES SPORTS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Temps", max(1, slice.duration)),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Sport", slice.label))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 128, height: 128)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(slices.prefix(4))) { slice in
                            HStack(spacing: 7) {
                                Image(systemName: slice.symbol)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(slice.label)
                                        .font(.caption.weight(.bold))
                                        .lineLimit(1)
                                    Text(progressionDuration(slice.duration))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .progressionCard()
        }
    }

    private var healthSignals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORME & RÉCUPÉRATION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("Repères personnels Santé")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.pink)
            }

            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lecture de Santé…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    HealthSignalTile(
                        label: "FC repos",
                        value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                        detail: baselineDetail(latest: health.restingHeartRate?.value, baseline: health.restingHeartRateBaseline),
                        symbol: "heart.fill",
                        accent: .red
                    )
                    HealthSignalTile(
                        label: "VFC",
                        value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                        detail: baselineDetail(latest: health.hrvSDNN?.value, baseline: health.hrvBaseline),
                        symbol: "waveform.path.ecg",
                        accent: .purple
                    )
                    HealthSignalTile(
                        label: "Sommeil",
                        value: health.sleepHours.map { String(format: "%.1f h", $0) } ?? "—",
                        detail: health.sleepSource ?? "non disponible",
                        symbol: "moon.stars.fill",
                        accent: .indigo
                    )
                    HealthSignalTile(
                        label: "VO₂ max",
                        value: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—",
                        detail: health.vo2Max.map { $0.source } ?? "non disponible",
                        symbol: "lungs.fill",
                        accent: .mint
                    )
                }
            }
        }
        .progressionCard()
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Source : Apple Health", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text("Les graphiques d’activité utilisent tous les entraînements que Santé autorise Watch Tracker à lire, quelle que soit l’app qui les a enregistrés. Les comparaisons sont personnelles et ne constituent pas un diagnostic médical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sportMenu: some View {
        Menu {
            Button {
                selectedSportRaw = "all"
            } label: {
                Label("Tous les sports", systemImage: "figure.mixed.cardio")
            }

            ForEach(availableSportRaws, id: \.self) { raw in
                Button {
                    selectedSportRaw = raw
                } label: {
                    Label(activityLabel(raw), systemImage: activitySymbol(raw))
                }
            }
        } label: {
            Image(systemName: selectedSportRaw == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filtrer le sport")
    }

    private var filteredWorkouts: [HealthWorkoutRecord] {
        guard selectedSportRaw != "all" else { return workouts }
        return workouts.filter { $0.activity.rawValue == selectedSportRaw }
    }

    private var currentRecords: [HealthWorkoutRecord] {
        let start = range.startDate(now: Date(), records: filteredWorkouts)
        return filteredWorkouts.filter { $0.startedAt >= start }
    }

    private var previousRecords: [HealthWorkoutRecord] {
        guard let previousStart = range.previousStart(now: Date(), records: filteredWorkouts) else { return [] }
        let currentStart = range.startDate(now: Date(), records: filteredWorkouts)
        return filteredWorkouts.filter { $0.startedAt >= previousStart && $0.startedAt < currentStart }
    }

    private var availableSportRaws: [String] {
        Array(Set(workouts.map { $0.activity.rawValue }))
            .sorted { activityLabel($0) < activityLabel($1) }
    }

    private var buckets: [ProgressionBucket] {
        makeBuckets(records: currentRecords, style: range.bucketStyle)
    }

    private var sportSlices: [SportSlice] {
        let grouped = Dictionary(grouping: currentRecords, by: { $0.activity.rawValue })
        return grouped.map { raw, values in
            SportSlice(
                rawActivity: raw,
                label: activityLabel(raw),
                symbol: activitySymbol(raw),
                duration: values.reduce(0) { $0 + $1.duration }
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    private var heroTitle: String {
        let current = aggregate(currentRecords)
        if loading { return "Analyse de ton historique" }
        if current.count == 0 { return "Aucune séance sur cette période" }
        return "\(current.count) séance\(current.count > 1 ? "s" : "") · \(progressionDuration(current.duration))"
    }

    private var heroSubtitle: String {
        if selectedSportRaw == "all" {
            return "Toutes tes activités Santé accessibles, sur \(range.label)."
        }
        return "\(activityLabel(selectedSportRaw)) · vue \(range.label)."
    }

    private var rangeSummaryTitle: String {
        range == .all ? "DEPUIS LE DÉBUT" : "PÉRIODE · \(range.label.uppercased())"
    }

    private var chartCalendarUnit: Calendar.Component {
        switch range.bucketStyle {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private var chartDateFormat: Date.FormatStyle {
        switch range.bucketStyle {
        case .day: return .dateTime.day().month(.abbreviated)
        case .week: return .dateTime.day().month(.abbreviated)
        case .month: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private func chartValue(_ bucket: ProgressionBucket) -> Double {
        switch metric {
        case .duration: return bucket.duration / 3600
        case .distance: return bucket.distanceMeters / 1000
        case .sessions: return Double(bucket.count)
        }
    }

    private func aggregate(_ records: [HealthWorkoutRecord]) -> ProgressionAggregate {
        ProgressionAggregate(
            count: records.count,
            duration: records.reduce(0) { $0 + $1.duration },
            distanceMeters: records.reduce(0) { $0 + $1.distanceMeters },
            energyKcal: records.compactMap(\.activeEnergyKcal).reduce(0, +)
        )
    }

    private func makeBuckets(records: [HealthWorkoutRecord], style: ProgressionBucketStyle) -> [ProgressionBucket] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: records) { record -> Date in
            switch style {
            case .day:
                return calendar.startOfDay(for: record.startedAt)
            case .week:
                return calendar.dateInterval(of: .weekOfYear, for: record.startedAt)?.start ?? calendar.startOfDay(for: record.startedAt)
            case .month:
                return calendar.dateInterval(of: .month, for: record.startedAt)?.start ?? calendar.startOfDay(for: record.startedAt)
            }
        }

        return grouped.map { start, values in
            ProgressionBucket(
                start: start,
                count: values.count,
                duration: values.reduce(0) { $0 + $1.duration },
                distanceMeters: values.reduce(0) { $0 + $1.distanceMeters }
            )
        }
        .sorted { $0.start < $1.start }
    }

    private func deltaText(_ current: Double, _ previous: Double) -> String? {
        guard range != .all, previous > 0 else { return nil }
        let delta = (current - previous) / previous
        if abs(delta) < 0.005 { return "≈ période précédente" }
        return String(format: "%+.0f%% vs avant", delta * 100)
    }

    private func comparisonSentence(current: ProgressionAggregate, previous: ProgressionAggregate) -> String? {
        guard range != .all, previous.duration > 0 else { return nil }
        let delta = (current.duration - previous.duration) / previous.duration
        if abs(delta) < 0.05 { return "Volume d’activité proche de la période précédente." }
        if delta > 0 { return String(format: "Volume d’activité en hausse de %.0f%% par rapport à la période précédente.", delta * 100) }
        return String(format: "Volume d’activité en baisse de %.0f%% par rapport à la période précédente.", abs(delta) * 100)
    }

    private func comparisonSymbol(current: ProgressionAggregate, previous: ProgressionAggregate) -> String {
        guard previous.duration > 0 else { return "equal.circle.fill" }
        let delta = current.duration - previous.duration
        if abs(delta) < previous.duration * 0.05 { return "equal.circle.fill" }
        return delta > 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
    }

    private func baselineDetail(latest: Double?, baseline: Double?) -> String {
        guard let latest, let baseline, baseline > 0 else { return "repère indisponible" }
        let delta = (latest - baseline) / baseline
        if abs(delta) < 0.03 { return "proche du repère 28 j" }
        return String(format: "%+.0f%% vs repère 28 j", delta * 100)
    }

    private func refresh() {
        loading = true
        let group = DispatchGroup()
        var loadedWorkouts: [HealthWorkoutRecord] = []
        var loadedHealth = HealthProgressionData.empty

        group.enter()
        historyReader.loadAll { values in
            loadedWorkouts = values
            group.leave()
        }

        group.enter()
        healthReader.load { value in
            loadedHealth = value
            group.leave()
        }

        group.notify(queue: .main) {
            workouts = loadedWorkouts
            health = loadedHealth
            if selectedSportRaw != "all" && !availableSportRaws.contains(selectedSportRaw) {
                selectedSportRaw = "all"
            }
            loading = false
        }
    }
}

private struct ProgressionMetricCard: View {
    let title: String
    let value: String
    let delta: String?
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(delta ?? " ")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delta == nil ? Color.clear : accent)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.18), Color.white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct HealthSignalTile: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension View {
    func progressionCard() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.06), lineWidth: 1)
            )
    }
}

private func progressionDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(0, Int(seconds / 60))
    if totalMinutes >= 60 {
        return String(format: "%dh%02d", totalMinutes / 60, totalMinutes % 60)
    }
    return "\(totalMinutes) min"
}

private func progressionDistance(_ meters: Double) -> String {
    if meters >= 100_000 { return String(format: "%.0f km", meters / 1000) }
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    return String(format: "%.0f m", meters)
}
