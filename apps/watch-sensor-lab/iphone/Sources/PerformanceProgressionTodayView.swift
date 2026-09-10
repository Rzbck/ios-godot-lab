import Charts
import Foundation
import SwiftUI

private enum PerformanceWindowV2: String, CaseIterable, Identifiable {
    case today
    case week
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Aujourd’hui"
        case .week: return "7 j"
        case .month: return "1 mois"
        case .sixMonths: return "6 mois"
        case .year: return "1 an"
        case .all: return "Tout"
        }
    }

    var shortLabel: String {
        switch self {
        case .today: return "Aujourd’hui"
        case .week: return "Semaine"
        case .month: return "Mois"
        case .sixMonths: return "6 mois"
        case .year: return "Année"
        case .all: return "Total"
        }
    }
}

private enum PerformanceMetricV2: String, CaseIterable, Identifiable {
    case duration
    case distance
    case sessions

    var id: String { rawValue }

    var label: String {
        switch self {
        case .duration: return "Temps actif"
        case .distance: return "Distance"
        case .sessions: return "Séances"
        }
    }

    var symbol: String {
        switch self {
        case .duration: return "clock.fill"
        case .distance: return "location.fill"
        case .sessions: return "figure.run"
        }
    }
}

private enum BucketUnitV2 {
    case hour
    case day
    case month
}

private struct WindowBoundsV2 {
    let currentStart: Date
    let currentEnd: Date
    let previousStart: Date?
    let previousEnd: Date?
    let bucketUnit: BucketUnitV2
}

private struct PerformanceAggregateV2 {
    let sessions: Int
    let duration: TimeInterval
    let distance: Double
    let energy: Double

    static let zero = PerformanceAggregateV2(sessions: 0, duration: 0, distance: 0, energy: 0)
}

private struct ComparisonSeriesPointV2: Identifiable {
    let index: Int
    let current: Double?
    let previous: Double?
    let label: String

    var id: Int { index }
}

struct PerformanceProgressionTodayView: View {
    @State private var workouts: [HealthWorkoutRecord] = []
    @State private var localSummaries: [TrackerSummary] = []
    @State private var health = HealthProgressionData.empty
    @State private var range: PerformanceWindowV2 = .today
    @State private var metric: PerformanceMetricV2 = .duration
    @State private var selectedSportRaw = "all"
    @State private var loading = true

    private let historyReader = HealthWorkoutHistoryReader()
    private let healthReader = HealthProgressionReader()
    private let localStore = NativeSessionStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    todayHero
                    todayQuickGrid
                    periodSelector
                    comparisonSection
                    if range == .today {
                        todayActivities
                    }
                    sportComposition
                    healthSignals
                    sourceNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(
                LinearGradient(
                    colors: [Color.cyan.opacity(0.11), Color.indigo.opacity(0.08), Color.black],
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

    private var todayHero: some View {
        let today = aggregate(records: records(in: bounds(for: .today).currentStart...Date()))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUJOURD’HUI")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                    Text(today.sessions == 0 ? "Ta journée sportive" : "\(today.sessions) activité\(today.sessions > 1 ? "s" : "") aujourd’hui")
                        .font(.title2.weight(.black))
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ZStack {
                    Circle().fill(.cyan.opacity(0.14))
                    Image(systemName: today.sessions > 0 ? "bolt.heart.fill" : "sun.max.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.cyan)
                }
                .frame(width: 48, height: 48)
            }

            HStack(spacing: 16) {
                heroValue(progressionDurationV2(today.duration), "actif")
                heroValue(progressionDistanceV2(today.distance), "distance")
                heroValue(today.energy > 0 ? "\(Int(today.energy.rounded()))" : "—", "kcal")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.24), .indigo.opacity(0.17), .white.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var todayQuickGrid: some View {
        let todayBounds = bounds(for: .today)
        let todayRecords = records(in: todayBounds.currentStart...todayBounds.currentEnd)
        let today = aggregate(records: todayRecords)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                PerformanceMetricDetailV2(
                    title: "Activités aujourd’hui",
                    subtitle: "Toutes les séances Santé lisibles aujourd’hui",
                    symbol: "figure.run",
                    accent: .orange,
                    records: todayRecords,
                    metric: .sessions
                )
            } label: {
                ProgressionDrillCardV2(value: "\(today.sessions)", label: "SÉANCES", symbol: "figure.run", accent: .orange)
            }

            NavigationLink {
                PerformanceMetricDetailV2(
                    title: "Temps actif aujourd’hui",
                    subtitle: "Cumul des entraînements Santé",
                    symbol: "clock.fill",
                    accent: .cyan,
                    records: todayRecords,
                    metric: .duration
                )
            } label: {
                ProgressionDrillCardV2(value: progressionDurationV2(today.duration), label: "TEMPS ACTIF", symbol: "clock.fill", accent: .cyan)
            }

            NavigationLink {
                PerformanceMetricDetailV2(
                    title: "Distance aujourd’hui",
                    subtitle: "Distance issue des séances Santé",
                    symbol: "location.fill",
                    accent: .mint,
                    records: todayRecords,
                    metric: .distance
                )
            } label: {
                ProgressionDrillCardV2(value: progressionDistanceV2(today.distance), label: "DISTANCE", symbol: "location.fill", accent: .mint)
            }

            NavigationLink {
                HealthSignalDetailV2(
                    title: "Pas aujourd’hui",
                    value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                    subtitle: "Total Santé du jour",
                    symbol: "shoeprints.fill",
                    accent: .green,
                    points: []
                )
            } label: {
                ProgressionDrillCardV2(
                    value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                    label: "PAS",
                    symbol: "shoeprints.fill",
                    accent: .green
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var periodSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PÉRIODE")
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PerformanceWindowV2.allCases) { item in
                        Button {
                            withAnimation(.snappy) { range = item }
                        } label: {
                            Text(item.label)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(range == item ? Color.black : Color.primary)
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .background(range == item ? Color.cyan : Color.white.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var comparisonSection: some View {
        let bounds = bounds(for: range)
        let current = aggregate(records: records(in: bounds.currentStart...bounds.currentEnd))
        let previous = aggregate(records: previousRecords(bounds: bounds))
        let points = comparisonPoints(bounds: bounds, metric: metric)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(range == .today ? "RYTHME DU JOUR" : "ÉVOLUTION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("\(range.shortLabel) vs avant")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Menu {
                    ForEach(PerformanceMetricV2.allCases) { option in
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

            if range == .all || points.isEmpty {
                if range == .all {
                    Text("La vue Total montre l’historique cumulé. Choisis une période bornée pour la comparaison avant/après.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    ContentUnavailableView("Pas encore de courbe", systemImage: "chart.xyaxis.line")
                        .frame(height: 190)
                }
            } else {
                HStack(spacing: 14) {
                    legendDot(.cyan, "Actuel")
                    legendDot(.secondary, "Avant")
                    Spacer()
                    comparisonBadge(current: current, previous: previous, metric: metric)
                }

                Chart(points) { point in
                    if let value = point.previous {
                        LineMark(
                            x: .value("Progression", point.index),
                            y: .value("Avant", value)
                        )
                        .foregroundStyle(Color.secondary.opacity(0.72))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                    if let value = point.current {
                        AreaMark(
                            x: .value("Progression", point.index),
                            y: .value("Actuel", value)
                        )
                        .foregroundStyle(
                            LinearGradient(colors: [.cyan.opacity(0.25), .cyan.opacity(0.01)], startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.catmullRom)
                        LineMark(
                            x: .value("Progression", point.index),
                            y: .value("Actuel", value)
                        )
                        .foregroundStyle(Color.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 230)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.04))
                        AxisTick().foregroundStyle(.secondary)
                        AxisValueLabel()
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.08))
                        AxisValueLabel()
                    }
                }

                Text("Les deux courbes sont cumulées au même point de la période : tu vois immédiatement si ton volume actuel est en avance ou en retard sur la période précédente.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .performanceCardV2()
    }

    @ViewBuilder
    private var todayActivities: some View {
        let day = bounds(for: .today)
        let records = records(in: day.currentStart...day.currentEnd)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITÉS DU JOUR")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(records.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.cyan)
            }

            if records.isEmpty {
                Text("Aucun entraînement Santé lisible aujourd’hui pour le filtre actuel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(records.prefix(8)) { record in
                    NavigationLink {
                        PerformanceWorkoutDetailV2(record: record, trackerSummary: trackerSummary(for: record))
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: record.activity.symbol)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(sportAccentV2(record.activity))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.activity.label)
                                    .font(.subheadline.weight(.bold))
                                Text(record.startedAt, format: .dateTime.hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(progressionDurationV2(record.duration))
                                    .font(.subheadline.weight(.bold))
                                if record.distanceMeters > 0 {
                                    Text(progressionDistanceV2(record.distanceMeters))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .performanceCardV2()
    }

    @ViewBuilder
    private var sportComposition: some View {
        let slices = sportSlices
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("RÉPARTITION")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                HStack(spacing: 16) {
                    Chart(slices, id: \.activity.rawValue) { item in
                        SectorMark(
                            angle: .value("Temps", max(1, item.duration)),
                            innerRadius: .ratio(0.64),
                            angularInset: 2
                        )
                        .foregroundStyle(sportAccentV2(item.activity))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 126, height: 126)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(slices.prefix(4), id: \.activity.rawValue) { item in
                            HStack(spacing: 7) {
                                Image(systemName: item.activity.symbol)
                                    .foregroundStyle(sportAccentV2(item.activity))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.activity.label).font(.caption.weight(.bold)).lineLimit(1)
                                    Text(progressionDurationV2(item.duration)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .performanceCardV2()
        }
    }

    private var healthSignals: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("FORME & RÉCUPÉRATION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("Appuie pour voir le détail")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "heart.text.square.fill").foregroundStyle(.pink)
            }

            if loading {
                HStack(spacing: 8) { ProgressView(); Text("Lecture de Santé…").font(.caption).foregroundStyle(.secondary) }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    NavigationLink {
                        HealthSignalDetailV2(
                            title: "Fréquence au repos",
                            value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                            subtitle: health.restingHeartRate.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                            symbol: "heart.fill",
                            accent: .red,
                            points: health.restingHeartRateTrend
                        )
                    } label: {
                        HealthDrillTileV2(label: "FC repos", value: health.restingHeartRate.map { String(format: "%.0f", $0.value) } ?? "—", unit: "bpm", symbol: "heart.fill", accent: .red)
                    }

                    NavigationLink {
                        HealthSignalDetailV2(
                            title: "Variabilité cardiaque",
                            value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                            subtitle: health.hrvSDNN.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                            symbol: "waveform.path.ecg",
                            accent: .purple,
                            points: health.hrvTrend
                        )
                    } label: {
                        HealthDrillTileV2(label: "VFC", value: health.hrvSDNN.map { String(format: "%.0f", $0.value) } ?? "—", unit: "ms", symbol: "waveform.path.ecg", accent: .purple)
                    }

                    NavigationLink {
                        HealthSignalDetailV2(
                            title: "Sommeil récent",
                            value: health.sleepHours.map { String(format: "%.1f h", $0) } ?? "—",
                            subtitle: health.sleepSource ?? "Donnée non disponible",
                            symbol: "moon.stars.fill",
                            accent: .indigo,
                            points: []
                        )
                    } label: {
                        HealthDrillTileV2(label: "Sommeil", value: health.sleepHours.map { String(format: "%.1f", $0) } ?? "—", unit: "h", symbol: "moon.stars.fill", accent: .indigo)
                    }

                    NavigationLink {
                        HealthSignalDetailV2(
                            title: "VO₂ max",
                            value: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—",
                            subtitle: health.vo2Max.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                            symbol: "lungs.fill",
                            accent: .mint,
                            points: []
                        )
                    } label: {
                        HealthDrillTileV2(label: "VO₂ max", value: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—", unit: "", symbol: "lungs.fill", accent: .mint)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .performanceCardV2()
    }

    private var sourceNote: some View {
        Text("Activités : Apple Health. Les détails Tracker enrichissent les séances enregistrées par Watch Tracker avec effort, pauses, météo et autres mesures disponibles. Les tendances Santé ne constituent pas un diagnostic médical.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sportMenu: some View {
        Menu {
            Button { selectedSportRaw = "all" } label: {
                Label("Tous les sports", systemImage: "figure.mixed.cardio")
            }
            ForEach(availableSports, id: \.rawValue) { sport in
                Button { selectedSportRaw = sport.rawValue } label: {
                    Label(sport.label, systemImage: sport.symbol)
                }
            }
        } label: {
            Image(systemName: selectedSportRaw == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private var availableSports: [ActivityKind] {
        Array(Set(workouts.map { $0.activity })).sorted { $0.label < $1.label }
    }

    private var filteredWorkouts: [HealthWorkoutRecord] {
        guard selectedSportRaw != "all" else { return workouts }
        return workouts.filter { $0.activity.rawValue == selectedSportRaw }
    }

    private var sportSlices: [(activity: ActivityKind, duration: TimeInterval)] {
        let b = bounds(for: range)
        let relevant = records(in: b.currentStart...b.currentEnd)
        let grouped = Dictionary(grouping: relevant, by: \.activity)
        return grouped.map { key, values in
            (key, values.reduce(0) { $0 + $1.duration })
        }
        .sorted { $0.duration > $1.duration }
    }

    private func records(in interval: ClosedRange<Date>) -> [HealthWorkoutRecord] {
        filteredWorkouts.filter { $0.startedAt >= interval.lowerBound && $0.startedAt <= interval.upperBound }
    }

    private func previousRecords(bounds: WindowBoundsV2) -> [HealthWorkoutRecord] {
        guard let start = bounds.previousStart, let end = bounds.previousEnd else { return [] }
        return records(in: start...end)
    }

    private func aggregate(records: [HealthWorkoutRecord]) -> PerformanceAggregateV2 {
        PerformanceAggregateV2(
            sessions: records.count,
            duration: records.reduce(0) { $0 + $1.duration },
            distance: records.reduce(0) { $0 + $1.distanceMeters },
            energy: records.compactMap(\.activeEnergyKcal).reduce(0, +)
        )
    }

    private func bounds(for window: PerformanceWindowV2) -> WindowBoundsV2 {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        func alignedPrevious(currentStart: Date, previousStart: Date, unit: BucketUnitV2) -> WindowBoundsV2 {
            let elapsed = now.timeIntervalSince(currentStart)
            return WindowBoundsV2(
                currentStart: currentStart,
                currentEnd: now,
                previousStart: previousStart,
                previousEnd: previousStart.addingTimeInterval(elapsed),
                bucketUnit: unit
            )
        }

        switch window {
        case .today:
            let previous = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? .distantPast
            return alignedPrevious(currentStart: startOfToday, previousStart: previous, unit: .hour)

        case .week:
            let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.date(byAdding: .day, value: -6, to: startOfToday)!
            let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: current) ?? .distantPast
            return alignedPrevious(currentStart: current, previousStart: previous, unit: .day)

        case .month:
            let current = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            let previous = calendar.date(byAdding: .month, value: -1, to: current) ?? .distantPast
            return alignedPrevious(currentStart: current, previousStart: previous, unit: .day)

        case .sixMonths:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
            let current = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? .distantPast
            let previous = calendar.date(byAdding: .month, value: -6, to: current) ?? .distantPast
            return alignedPrevious(currentStart: current, previousStart: previous, unit: .month)

        case .year:
            let current = calendar.dateInterval(of: .year, for: now)?.start ?? startOfToday
            let previous = calendar.date(byAdding: .year, value: -1, to: current) ?? .distantPast
            return alignedPrevious(currentStart: current, previousStart: previous, unit: .month)

        case .all:
            let start = filteredWorkouts.map(\.startedAt).min() ?? startOfToday
            return WindowBoundsV2(currentStart: start, currentEnd: now, previousStart: nil, previousEnd: nil, bucketUnit: .month)
        }
    }

    private func comparisonPoints(bounds: WindowBoundsV2, metric: PerformanceMetricV2) -> [ComparisonSeriesPointV2] {
        guard let previousStart = bounds.previousStart, let previousEnd = bounds.previousEnd else { return [] }
        let currentBuckets = bucketValues(records: records(in: bounds.currentStart...bounds.currentEnd), start: bounds.currentStart, end: bounds.currentEnd, unit: bounds.bucketUnit, metric: metric)
        let previousBuckets = bucketValues(records: records(in: previousStart...previousEnd), start: previousStart, end: previousEnd, unit: bounds.bucketUnit, metric: metric)
        let count = max(currentBuckets.count, previousBuckets.count)
        guard count > 0 else { return [] }

        var currentRunning = 0.0
        var previousRunning = 0.0
        return (0..<count).map { index in
            let currentValue = index < currentBuckets.count ? currentBuckets[index] : nil
            let previousValue = index < previousBuckets.count ? previousBuckets[index] : nil
            if let currentValue { currentRunning += currentValue }
            if let previousValue { previousRunning += previousValue }
            return ComparisonSeriesPointV2(
                index: index + 1,
                current: currentValue == nil && index >= currentBuckets.count ? nil : currentRunning,
                previous: previousValue == nil && index >= previousBuckets.count ? nil : previousRunning,
                label: "\(index + 1)"
            )
        }
    }

    private func bucketValues(
        records: [HealthWorkoutRecord],
        start: Date,
        end: Date,
        unit: BucketUnitV2,
        metric: PerformanceMetricV2
    ) -> [Double] {
        let calendar = Calendar.autoupdatingCurrent
        var cursor = start
        var result: [Double] = []
        while cursor <= end {
            let next: Date
            switch unit {
            case .hour:
                next = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            case .day:
                next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            case .month:
                next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            }
            let bucketEnd = min(end.addingTimeInterval(0.001), next)
            let bucketRecords = records.filter { $0.startedAt >= cursor && $0.startedAt < bucketEnd }
            let value: Double
            switch metric {
            case .duration: value = bucketRecords.reduce(0) { $0 + $1.duration } / 60
            case .distance: value = bucketRecords.reduce(0) { $0 + $1.distanceMeters } / 1000
            case .sessions: value = Double(bucketRecords.count)
            }
            result.append(value)
            cursor = next
            if result.count > 400 { break }
        }
        return result
    }

    private func comparisonBadge(current: PerformanceAggregateV2, previous: PerformanceAggregateV2, metric: PerformanceMetricV2) -> some View {
        let pair: (Double, Double)
        switch metric {
        case .duration: pair = (current.duration, previous.duration)
        case .distance: pair = (current.distance, previous.distance)
        case .sessions: pair = (Double(current.sessions), Double(previous.sessions))
        }
        let text: String
        let positive: Bool
        if pair.1 <= 0 {
            text = "Nouveau repère"
            positive = true
        } else {
            let delta = (pair.0 - pair.1) / pair.1
            positive = delta >= 0
            if abs(delta) < 0.03 { text = "≈ au même niveau" }
            else { text = String(format: "%@ %.0f%%", positive ? "▲" : "▼", abs(delta) * 100) }
        }
        return Text(text)
            .font(.caption2.weight(.black))
            .foregroundStyle(positive ? Color.mint : Color.orange)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background((positive ? Color.mint : Color.orange).opacity(0.12), in: Capsule())
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    private func heroValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline.weight(.black)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func trackerSummary(for record: HealthWorkoutRecord) -> TrackerSummary? {
        guard let sessionID = record.trackerSessionID else { return nil }
        return localSummaries.first { $0.sessionID == sessionID }
    }

    private func refresh() {
        loading = true
        localSummaries = localStore.listSummaries()
        let group = DispatchGroup()
        group.enter()
        historyReader.loadAll { values in
            workouts = values
            group.leave()
        }
        group.enter()
        healthReader.load { value in
            health = value
            group.leave()
        }
        group.notify(queue: .main) { loading = false }
    }
}

private struct ProgressionDrillCardV2: View {
    let value: String
    let label: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.title3.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct HealthDrillTileV2: View {
    let label: String
    let value: String
    let unit: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.weight(.black)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct PerformanceMetricDetailV2: View {
    let title: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let records: [HealthWorkoutRecord]
    let metric: PerformanceMetricV2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbol)
                    .font(.title2.weight(.black))
                    .foregroundStyle(accent)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)

                ForEach(records) { record in
                    HStack(spacing: 10) {
                        Image(systemName: record.activity.symbol).foregroundStyle(sportAccentV2(record.activity)).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.activity.label).font(.subheadline.weight(.bold))
                            Text(record.startedAt, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(detailValue(record)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    .padding(12)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .navigationTitle("Détail")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private func detailValue(_ record: HealthWorkoutRecord) -> String {
        switch metric {
        case .sessions: return progressionDurationV2(record.duration)
        case .duration: return progressionDurationV2(record.duration)
        case .distance: return progressionDistanceV2(record.distanceMeters)
        }
    }
}

private struct HealthSignalDetailV2: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let points: [HealthTrendPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title.weight(.bold))
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.weight(.black))
                        Text(value).font(.title2.weight(.black)).monospacedDigit()
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                if !points.isEmpty {
                    Chart(points) { point in
                        AreaMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                            .foregroundStyle(accent)
                            .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 240)
                } else {
                    Text("Pas encore assez de points historiques lisibles pour tracer une courbe détaillée.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }

                Text("Source : Apple Health. Une donnée absente peut signifier qu’elle n’est pas produite ou qu’elle n’est pas partagée avec Watch Tracker.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding()
        }
        .navigationTitle("Forme")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

private struct PerformanceWorkoutDetailV2: View {
    let record: HealthWorkoutRecord
    let trackerSummary: TrackerSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: record.activity.symbol)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(sportAccentV2(record.activity))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.activity.label).font(.title2.weight(.black))
                        Text(record.startedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    detailMetricV2("Temps", progressionDurationV2(record.duration), "clock.fill", .cyan)
                    detailMetricV2("Distance", progressionDistanceV2(record.distanceMeters), "location.fill", .mint)
                    detailMetricV2("Énergie", record.activeEnergyKcal.map { "\(Int($0.rounded())) kcal" } ?? "—", "flame.fill", .orange)
                    detailMetricV2("Source", record.sourceName, "app.badge.fill", .pink)
                }

                if let trackerSummary {
                    TrackerEffortInsightView(summary: trackerSummary)
                } else {
                    Text("Les détails avancés d’effort, pauses et météo sont disponibles quand la séance provient de Watch Tracker et que ses données locales existent encore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding()
        }
        .navigationTitle("Activité")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

private extension View {
    func performanceCardV2() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func detailMetricV2(_ title: String, _ value: String, _ symbol: String, _ accent: Color) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Label(title, systemImage: symbol).font(.caption2.weight(.bold)).foregroundStyle(accent)
        Text(value).font(.headline.weight(.bold)).minimumScaleFactor(0.6).lineLimit(2)
    }
    .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
    .padding(11)
    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
}

private func progressionDurationV2(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes) min"
}

private func progressionDistanceV2(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func sportAccentV2(_ activity: ActivityKind) -> Color {
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
