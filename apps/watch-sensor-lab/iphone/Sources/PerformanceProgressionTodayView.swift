import Charts
import Foundation
import SwiftUI

private enum PerformanceWindowV2: String, CaseIterable, Identifiable {
    case today, week, month, sixMonths, year, all
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

    var comparisonTitle: String {
        switch self {
        case .today: return "Aujourd’hui vs hier"
        case .week: return "Cette semaine vs précédente"
        case .month: return "Ce mois vs précédent"
        case .sixMonths: return "6 mois vs 6 mois précédents"
        case .year: return "Cette année vs précédente"
        case .all: return "Historique total"
        }
    }
}

private enum PerformanceMetricV2: String, CaseIterable, Identifiable {
    case duration, distance, sessions
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

private enum BucketUnitV2 { case hour, day, month }

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
}

private struct ComparisonSeriesPointV2: Identifiable {
    let index: Int
    let current: Double?
    let previous: Double?
    var id: Int { index }
}

private struct AllHistoryPointV2: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

private struct SportSliceV2: Identifiable {
    let activity: ActivityKind
    let duration: TimeInterval
    var id: String { activity.rawValue }
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
                    if range == .today { todayActivities }
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { sportMenu } }
            .refreshable { refresh() }
            .onAppear { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var todayHero: some View {
        let day = bounds(for: .today)
        let today = aggregate(records(in: day.currentStart...day.currentEnd))

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
                Image(systemName: today.sessions > 0 ? "bolt.heart.fill" : "sun.max.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 48, height: 48)
                    .background(.cyan.opacity(0.14), in: Circle())
            }

            HStack(spacing: 18) {
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
        let day = bounds(for: .today)
        let todayRecords = records(in: day.currentStart...day.currentEnd)
        let today = aggregate(todayRecords)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                PerformanceMetricDetailV2(title: "Activités aujourd’hui", symbol: "figure.run", accent: .orange, records: todayRecords, metric: .sessions)
            } label: {
                ProgressionDrillCardV2(value: "\(today.sessions)", label: "SÉANCES", symbol: "figure.run", accent: .orange)
            }

            NavigationLink {
                PerformanceMetricDetailV2(title: "Temps actif aujourd’hui", symbol: "clock.fill", accent: .cyan, records: todayRecords, metric: .duration)
            } label: {
                ProgressionDrillCardV2(value: progressionDurationV2(today.duration), label: "TEMPS ACTIF", symbol: "clock.fill", accent: .cyan)
            }

            NavigationLink {
                PerformanceMetricDetailV2(title: "Distance aujourd’hui", symbol: "location.fill", accent: .mint, records: todayRecords, metric: .distance)
            } label: {
                ProgressionDrillCardV2(value: progressionDistanceV2(today.distance), label: "DISTANCE", symbol: "location.fill", accent: .mint)
            }

            NavigationLink {
                HealthSignalDetailV2(
                    title: "Pas aujourd’hui",
                    value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                    subtitle: "Total Apple Health du jour",
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
        .buttonStyle(TrackerDepthButtonStyle())
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
                        .buttonStyle(TrackerDepthButtonStyle())
                    }
                }
            }
        }
    }

    private var comparisonSection: some View {
        let b = bounds(for: range)
        let current = aggregate(records(in: b.currentStart...b.currentEnd))
        let previous = aggregate(previousRecords(bounds: b))

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÉVOLUTION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(range.comparisonTitle)
                        .font(.headline.weight(.bold))
                }

                Spacer()

                Label("glisse", systemImage: "arrow.left.and.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 7) {
                ForEach(PerformanceMetricV2.allCases) { candidate in
                    Button {
                        withAnimation(.snappy) {
                            metric = candidate
                        }
                    } label: {
                        Label(candidate.label, systemImage: candidate.symbol)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.70)
                            .foregroundStyle(
                                metric == candidate
                                    ? Color.black
                                    : Color.primary
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                metric == candidate
                                    ? Color.cyan
                                    : Color.white.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(TrackerDepthButtonStyle())
                }
            }

            if range == .all {
                HStack {
                    legendDot(.cyan, "Historique")
                    Spacer()
                    Text(metric.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 14) {
                    legendDot(.cyan, "Actuel")
                    legendDot(.secondary, "Avant")
                    Spacer()
                    comparisonBadge(
                        current: current,
                        previous: previous,
                        metric: metric
                    )
                }
            }

            TabView(selection: $metric) {
                ForEach(PerformanceMetricV2.allCases) { candidate in
                    VStack(spacing: 0) {
                        if range == .all {
                            InteractiveAllHistoryChartV3(
                                points: allHistoryPoints(metric: candidate),
                                metric: candidate
                            )
                        } else {
                            InteractiveComparisonChartV3(
                                points: comparisonPoints(
                                    bounds: b,
                                    metric: candidate
                                ),
                                bounds: b,
                                metric: candidate
                            )
                        }
                    }
                    .tag(candidate)
                }
            }
            .frame(height: 205)
            .tabViewStyle(.page(indexDisplayMode: .never))

            Text(
                range == .all
                    ? "Historique mensuel complet. Pose ou glisse le doigt sur la courbe pour lire un point."
                    : "Valeurs réelles par intervalle, sans cumul et sans lissage. Pose ou glisse le doigt sur le graphe pour comparer Actuel et Avant."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .performanceCardV2()
    }

    @ViewBuilder
    private var todayActivities: some View {
        let day = bounds(for: .today)
        let todayRecords = records(in: day.currentStart...day.currentEnd)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITÉS DU JOUR")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(todayRecords.count)").font(.caption.weight(.bold)).foregroundStyle(.cyan)
            }

            if todayRecords.isEmpty {
                Text("Aucun entraînement Santé lisible aujourd’hui pour le filtre actuel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(todayRecords.prefix(8))) { record in
                    NavigationLink {
                        PerformanceWorkoutDetailV2(record: record, trackerSummary: trackerSummary(for: record))
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: record.activity.symbol)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(sportAccentV2(record.activity))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.activity.label).font(.subheadline.weight(.bold))
                                Text(record.startedAt, format: .dateTime.hour().minute()).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(progressionDurationV2(record.duration)).font(.subheadline.weight(.bold))
                                if record.distanceMeters > 0 {
                                    Text(progressionDistanceV2(record.distanceMeters)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(TrackerDepthButtonStyle())
                }
            }
        }
        .performanceCardV2()
    }

    @ViewBuilder
    private var sportComposition: some View {
        let slices = sportSlices
        let totalDuration = slices.reduce(0) { $0 + $1.duration }

        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("RÉPARTITION DES SPORTS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(slices.count) sport\(slices.count > 1 ? "s" : "")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                ForEach(slices) { slice in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            Image(systemName: slice.activity.symbol)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(sportAccentV2(slice.activity))
                                .frame(width: 24)

                            Text(slice.activity.label)
                                .font(.subheadline.weight(.bold))

                            Spacer()

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(progressionDurationV2(slice.duration))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()

                                if totalDuration > 0 {
                                    Text(String(
                                        format: "%.0f%%",
                                        (slice.duration / totalDuration) * 100
                                    ))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }

                        ProgressView(
                            value: max(0, slice.duration),
                            total: max(1, totalDuration)
                        )
                        .tint(sportAccentV2(slice.activity))
                    }
                    .padding(.vertical, 4)

                    if slice.id != slices.last?.id {
                        Divider().opacity(0.18)
                    }
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
                    Text("Appuie sur une carte pour le détail")
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
                    healthLink(
                        title: "Fréquence au repos",
                        value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                        shortValue: health.restingHeartRate.map { String(format: "%.0f", $0.value) } ?? "—",
                        unit: "bpm",
                        subtitle: health.restingHeartRate.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                        symbol: "heart.fill",
                        accent: .red,
                        points: health.restingHeartRateTrend
                    )
                    healthLink(
                        title: "Variabilité cardiaque",
                        value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                        shortValue: health.hrvSDNN.map { String(format: "%.0f", $0.value) } ?? "—",
                        unit: "ms",
                        subtitle: health.hrvSDNN.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                        symbol: "waveform.path.ecg",
                        accent: .purple,
                        points: health.hrvTrend
                    )
                    healthLink(
                        title: "Sommeil récent",
                        value: health.sleepHours.map { String(format: "%.1f h", $0) } ?? "—",
                        shortValue: health.sleepHours.map { String(format: "%.1f", $0) } ?? "—",
                        unit: "h",
                        subtitle: health.sleepSource ?? "Donnée non disponible",
                        symbol: "moon.stars.fill",
                        accent: .indigo,
                        points: []
                    )
                    healthLink(
                        title: "VO₂ max",
                        value: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—",
                        shortValue: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—",
                        unit: "",
                        subtitle: health.vo2Max.map { "Source : \($0.source)" } ?? "Donnée non disponible",
                        symbol: "lungs.fill",
                        accent: .mint,
                        points: []
                    )
                }
                .buttonStyle(TrackerDepthButtonStyle())
            }
        }
        .performanceCardV2()
    }

    private var sourceNote: some View {
        Text("Activités : Apple Health. Les séances Watch Tracker ajoutent, quand disponibles, effort estimé, ressenti, pauses, météo et détails locaux. Une donnée Santé absente n’est jamais transformée en zéro.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sportMenu: some View {
        Menu {
            Button { selectedSportRaw = "all" } label: { Label("Tous les sports", systemImage: "figure.mixed.cardio") }
            ForEach(availableSports) { sport in
                Button { selectedSportRaw = sport.rawValue } label: { Label(sport.label, systemImage: sport.symbol) }
            }
        } label: {
            Image(systemName: selectedSportRaw == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
    }

    @ViewBuilder
    private func healthLink(
        title: String,
        value: String,
        shortValue: String,
        unit: String,
        subtitle: String,
        symbol: String,
        accent: Color,
        points: [HealthTrendPoint]
    ) -> some View {
        NavigationLink {
            HealthSignalDetailV2(title: title, value: value, subtitle: subtitle, symbol: symbol, accent: accent, points: points)
        } label: {
            HealthDrillTileV2(label: title, value: shortValue, unit: unit, symbol: symbol, accent: accent)
        }
    }

    private var availableSports: [ActivityKind] {
        let raws = Set(workouts.map { $0.activity.rawValue })
        return raws.compactMap { ActivityKind(rawValue: $0) }.sorted { $0.label < $1.label }
    }

    private var filteredWorkouts: [HealthWorkoutRecord] {
        selectedSportRaw == "all" ? workouts : workouts.filter { $0.activity.rawValue == selectedSportRaw }
    }

    private var sportSlices: [SportSliceV2] {
        let b = bounds(for: range)
        let grouped = Dictionary(grouping: records(in: b.currentStart...b.currentEnd), by: { $0.activity.rawValue })
        return grouped.compactMap { raw, values in
            guard let activity = ActivityKind(rawValue: raw) else { return nil }
            return SportSliceV2(activity: activity, duration: values.reduce(0) { $0 + $1.duration })
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

    private func aggregate(_ records: [HealthWorkoutRecord]) -> PerformanceAggregateV2 {
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
        let today = calendar.startOfDay(for: now)

        func aligned(_ currentStart: Date, _ previousStart: Date, _ unit: BucketUnitV2) -> WindowBoundsV2 {
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
            return aligned(today, calendar.date(byAdding: .day, value: -1, to: today) ?? .distantPast, .hour)
        case .week:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            return aligned(start, calendar.date(byAdding: .weekOfYear, value: -1, to: start) ?? .distantPast, .day)
        case .month:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? today
            return aligned(start, calendar.date(byAdding: .month, value: -1, to: start) ?? .distantPast, .day)
        case .sixMonths:
            let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? today
            let start = calendar.date(byAdding: .month, value: -5, to: monthStart) ?? .distantPast
            return aligned(start, calendar.date(byAdding: .month, value: -6, to: start) ?? .distantPast, .month)
        case .year:
            let start = calendar.dateInterval(of: .year, for: now)?.start ?? today
            return aligned(start, calendar.date(byAdding: .year, value: -1, to: start) ?? .distantPast, .month)
        case .all:
            let start = filteredWorkouts.map(\.startedAt).min() ?? today
            return WindowBoundsV2(currentStart: start, currentEnd: now, previousStart: nil, previousEnd: nil, bucketUnit: .month)
        }
    }

    private func comparisonPoints(
        bounds: WindowBoundsV2,
        metric: PerformanceMetricV2
    ) -> [ComparisonSeriesPointV2] {
        guard
            let previousStart = bounds.previousStart,
            let previousEnd = bounds.previousEnd
        else {
            return []
        }

        let currentBuckets = bucketValues(
            records: records(
                in: bounds.currentStart...bounds.currentEnd
            ),
            start: bounds.currentStart,
            end: bounds.currentEnd,
            unit: bounds.bucketUnit,
            metric: metric
        )

        let previousBuckets = bucketValues(
            records: records(
                in: previousStart...previousEnd
            ),
            start: previousStart,
            end: previousEnd,
            unit: bounds.bucketUnit,
            metric: metric
        )

        let count = max(
            currentBuckets.count,
            previousBuckets.count
        )

        guard count > 0 else { return [] }

        return (0..<count).map { index in
            ComparisonSeriesPointV2(
                index: index + 1,
                current: index < currentBuckets.count
                    ? currentBuckets[index]
                    : nil,
                previous: index < previousBuckets.count
                    ? previousBuckets[index]
                    : nil
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
        var output: [Double] = []
        while cursor <= end {
            let next: Date
            switch unit {
            case .hour: next = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            case .day: next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            case .month: next = calendar.date(byAdding: .month, value: 1, to: cursor) ?? end.addingTimeInterval(1)
            }
            let chunk = records.filter { $0.startedAt >= cursor && $0.startedAt < min(next, end.addingTimeInterval(0.001)) }
            switch metric {
            case .duration: output.append(chunk.reduce(0) { $0 + $1.duration } / 60)
            case .distance: output.append(chunk.reduce(0) { $0 + $1.distanceMeters } / 1000)
            case .sessions: output.append(Double(chunk.count))
            }
            cursor = next
            if output.count > 400 { break }
        }
        return output
    }

    private func allHistoryPoints(metric: PerformanceMetricV2) -> [AllHistoryPointV2] {
        let records = filteredWorkouts.sorted { $0.startedAt < $1.startedAt }
        guard let firstDate = records.first?.startedAt else { return [] }

        let calendar = Calendar.autoupdatingCurrent
        var cursor = calendar.dateInterval(of: .month, for: firstDate)?.start ?? firstDate
        let end = Date()
        var output: [AllHistoryPointV2] = []

        while cursor <= end {
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else {
                break
            }

            let chunk = records.filter {
                $0.startedAt >= cursor && $0.startedAt < next
            }

            let value: Double
            switch metric {
            case .duration:
                value = chunk.reduce(0) { $0 + $1.duration } / 60
            case .distance:
                value = chunk.reduce(0) { $0 + $1.distanceMeters } / 1000
            case .sessions:
                value = Double(chunk.count)
            }

            output.append(AllHistoryPointV2(date: cursor, value: max(0, value)))
            cursor = next

            if output.count >= 240 { break }
        }

        return output
    }

    private func comparisonUpperBound(_ points: [ComparisonSeriesPointV2]) -> Double {
        let current = points.compactMap(\.current).max() ?? 0
        let previous = points.compactMap(\.previous).max() ?? 0
        return max(1, max(current, previous) * 1.12)
    }

    private func allHistoryUpperBound(_ points: [AllHistoryPointV2]) -> Double {
        max(1, (points.map(\.value).max() ?? 0) * 1.15)
    }

    private func comparisonBadge(current: PerformanceAggregateV2, previous: PerformanceAggregateV2, metric: PerformanceMetricV2) -> some View {
        let pair: (Double, Double)
        switch metric {
        case .duration: pair = (current.duration, previous.duration)
        case .distance: pair = (current.distance, previous.distance)
        case .sessions: pair = (Double(current.sessions), Double(previous.sessions))
        }

        let text: String
        let ahead: Bool
        if pair.1 <= 0 {
            text = "Nouveau repère"
            ahead = true
        } else {
            let delta = (pair.0 - pair.1) / pair.1
            ahead = delta >= 0
            if abs(delta) < 0.03 { text = "≈ même niveau" }
            else { text = String(format: "%@ %.0f%%", ahead ? "▲" : "▼", abs(delta) * 100) }
        }

        return Text(text)
            .font(.caption2.weight(.black))
            .foregroundStyle(ahead ? Color.mint : Color.orange)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background((ahead ? Color.mint : Color.orange).opacity(0.12), in: Capsule())
    }

    private func trackerSummary(for record: HealthWorkoutRecord) -> TrackerSummary? {
        guard let id = record.trackerSessionID else { return nil }
        return localSummaries.first { $0.sessionID == id }
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

    private func refresh() {
        loading = true
        localSummaries = localStore.listSummaries()
        let group = DispatchGroup()
        group.enter()
        historyReader.loadAll { values in workouts = values; group.leave() }
        group.enter()
        healthReader.load { value in health = value; group.leave() }
        group.notify(queue: .main) { loading = false }
    }
}


private struct InteractiveComparisonChartV3: View {
    let points: [ComparisonSeriesPointV2]
    let bounds: WindowBoundsV2
    let metric: PerformanceMetricV2

    @State private var selectedIndex: Int?

    private var selectedPoint: ComparisonSeriesPointV2? {
        guard let selectedIndex else { return nil }

        return points.min {
            abs($0.index - selectedIndex)
                < abs($1.index - selectedIndex)
        }
    }

    var body: some View {
        if points.isEmpty {
            ContentUnavailableView(
                "Pas encore de courbe",
                systemImage: "chart.xyaxis.line"
            )
            .frame(height: 185)
        } else {
            Chart(points) { point in
                if let old = point.previous {
                    LineMark(
                        x: .value("Étape", point.index),
                        y: .value("Avant", old)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.75))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2,
                            dash: [5, 4]
                        )
                    )

                    PointMark(
                        x: .value("Étape", point.index),
                        y: .value("Avant", old)
                    )
                    .foregroundStyle(Color.secondary.opacity(0.72))
                    .symbolSize(
                        point.index == selectedPoint?.index
                            ? 60
                            : 15
                    )
                }

                if let now = point.current {
                    LineMark(
                        x: .value("Étape", point.index),
                        y: .value("Actuel", now)
                    )
                    .foregroundStyle(.cyan)
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.6,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    PointMark(
                        x: .value("Étape", point.index),
                        y: .value("Actuel", now)
                    )
                    .foregroundStyle(.cyan)
                    .symbolSize(
                        point.index == selectedPoint?.index
                            ? 75
                            : 18
                    )
                }

                if point.index == selectedPoint?.index {
                    RuleMark(
                        x: .value("Sélection", point.index)
                    )
                    .foregroundStyle(.white.opacity(0.42))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 1,
                            dash: [3, 3]
                        )
                    )
                    .annotation(
                        position: .top,
                        spacing: 5
                    ) {
                        selectionBadge(point)
                    }
                }
            }
            .chartYScale(
                domain: 0...upperBound
            )
            .chartXAxis {
                AxisMarks(
                    values: .automatic(desiredCount: 5)
                ) { value in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.05))
                    AxisTick()
                        .foregroundStyle(.secondary)

                    AxisValueLabel {
                        if let index = value.as(Int.self) {
                            Text(axisLabel(index))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedIndex)
            .frame(height: 185)
        }
    }

    private var upperBound: Double {
        let current = points.compactMap(\.current).max() ?? 0
        let previous = points.compactMap(\.previous).max() ?? 0
        return max(
            1,
            max(current, previous) * 1.15
        )
    }

    private func selectionBadge(
        _ point: ComparisonSeriesPointV2
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(selectionLabel(point.index))
                .font(.caption2.weight(.black))

            HStack(spacing: 8) {
                Label {
                    Text(valueText(point.current))
                } icon: {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 6, height: 6)
                }

                Label {
                    Text(valueText(point.previous))
                } icon: {
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                }
            }
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 10,
                style: .continuous
            )
        )
        .allowsHitTesting(false)
    }

    private func valueText(_ value: Double?) -> String {
        guard let value else { return "—" }

        switch metric {
        case .duration:
            let minutes = max(0, Int(value.rounded()))
            if minutes >= 60 {
                return String(
                    format: "%dh%02d",
                    minutes / 60,
                    minutes % 60
                )
            }
            return "\(minutes) min"

        case .distance:
            return String(format: "%.1f km", value)

        case .sessions:
            return "\(Int(value.rounded()))"
        }
    }

    private func bucketDate(_ index: Int) -> Date {
        let calendar = Calendar.autoupdatingCurrent
        let offset = max(0, index - 1)

        switch bounds.bucketUnit {
        case .hour:
            return calendar.date(
                byAdding: .hour,
                value: offset,
                to: bounds.currentStart
            ) ?? bounds.currentStart

        case .day:
            return calendar.date(
                byAdding: .day,
                value: offset,
                to: bounds.currentStart
            ) ?? bounds.currentStart

        case .month:
            return calendar.date(
                byAdding: .month,
                value: offset,
                to: bounds.currentStart
            ) ?? bounds.currentStart
        }
    }

    private func axisLabel(_ index: Int) -> String {
        let date = bucketDate(index)

        switch bounds.bucketUnit {
        case .hour:
            return date.formatted(
                .dateTime.hour()
            )

        case .day:
            return date.formatted(
                .dateTime.day().month(.abbreviated)
            )

        case .month:
            return date.formatted(
                .dateTime.month(.abbreviated)
            )
        }
    }

    private func selectionLabel(_ index: Int) -> String {
        let date = bucketDate(index)

        switch bounds.bucketUnit {
        case .hour:
            return date.formatted(
                .dateTime.weekday(.abbreviated).hour()
            )

        case .day:
            return date.formatted(
                .dateTime.weekday(.abbreviated)
                    .day()
                    .month(.abbreviated)
            )

        case .month:
            return date.formatted(
                .dateTime.month(.wide).year()
            )
        }
    }
}

private struct InteractiveAllHistoryChartV3: View {
    let points: [AllHistoryPointV2]
    let metric: PerformanceMetricV2

    @State private var selectedDate: Date?

    private var selectedPoint: AllHistoryPointV2? {
        guard let selectedDate else { return nil }

        return points.min {
            abs(
                $0.date.timeIntervalSince(selectedDate)
            )
            <
            abs(
                $1.date.timeIntervalSince(selectedDate)
            )
        }
    }

    var body: some View {
        if points.isEmpty {
            ContentUnavailableView(
                "Pas encore de courbe",
                systemImage: "chart.xyaxis.line"
            )
            .frame(height: 185)
        } else {
            Chart(points) { point in
                LineMark(
                    x: .value("Mois", point.date),
                    y: .value("Valeur", point.value)
                )
                .foregroundStyle(.cyan)
                .lineStyle(
                    StrokeStyle(
                        lineWidth: 2.6,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                PointMark(
                    x: .value("Mois", point.date),
                    y: .value("Valeur", point.value)
                )
                .foregroundStyle(.cyan)
                .symbolSize(
                    point.id == selectedPoint?.id
                        ? 75
                        : 18
                )

                if point.id == selectedPoint?.id {
                    RuleMark(
                        x: .value("Sélection", point.date)
                    )
                    .foregroundStyle(.white.opacity(0.42))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 1,
                            dash: [3, 3]
                        )
                    )
                    .annotation(
                        position: .top,
                        spacing: 5
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                point.date.formatted(
                                    .dateTime
                                        .month(.wide)
                                        .year()
                                )
                            )
                            .font(.caption2.weight(.black))

                            Text(valueText(point.value))
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.cyan)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            .ultraThinMaterial,
                            in: RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                        .allowsHitTesting(false)
                    }
                }
            }
            .chartYScale(
                domain: 0...upperBound
            )
            .chartXAxis {
                AxisMarks(
                    values: .automatic(desiredCount: 4)
                ) { _ in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.05))
                    AxisTick()
                        .foregroundStyle(.secondary)
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel()
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 185)
        }
    }

    private var upperBound: Double {
        max(
            1,
            (points.map(\.value).max() ?? 0) * 1.15
        )
    }

    private func valueText(_ value: Double) -> String {
        switch metric {
        case .duration:
            let minutes = max(0, Int(value.rounded()))
            if minutes >= 60 {
                return String(
                    format: "%dh%02d",
                    minutes / 60,
                    minutes % 60
                )
            }
            return "\(minutes) min"

        case .distance:
            return String(format: "%.1f km", value)

        case .sessions:
            return "\(Int(value.rounded()))"
        }
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
                Image(systemName: "arrow.up.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text(value).font(.title3.weight(.black)).monospacedDigit().minimumScaleFactor(0.65).lineLimit(1)
            Text(label).font(.caption2.weight(.black)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, x: 0, y: 4)
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
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accent.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.26), radius: 7, x: 0, y: 4)
    }
}

private struct PerformanceMetricDetailV2: View {
    let title: String
    let symbol: String
    let accent: Color
    let records: [HealthWorkoutRecord]
    let metric: PerformanceMetricV2

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(title, systemImage: symbol).font(.title2.weight(.black)).foregroundStyle(accent)
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
        case .sessions, .duration: return progressionDurationV2(record.duration)
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
                    Image(systemName: symbol).font(.title.weight(.bold)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title3.weight(.black))
                        Text(value).font(.title2.weight(.black)).monospacedDigit()
                    }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)

                if points.isEmpty {
                    Text("Pas encore assez de points historiques lisibles pour tracer une courbe détaillée.")
                        .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
                } else {
                    Chart(points) { point in
                        AreaMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.value))
                            .foregroundStyle(accent)
                    }
                    .frame(height: 240)
                }

                Text("Source : Apple Health. Une donnée absente peut signifier qu’elle n’est pas produite ou qu’elle n’est pas partagée avec Watch Tracker.")
                    .font(.caption2).foregroundStyle(.tertiary)
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
                        Text(record.startedAt, format: .dateTime.day().month().hour().minute()).font(.caption).foregroundStyle(.secondary)
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
                    Text("Effort détaillé, pauses et météo sont disponibles pour les séances Watch Tracker dont les données locales existent encore.")
                        .font(.caption).foregroundStyle(.secondary)
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
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.075), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.30), radius: 10, x: 0, y: 5)
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
    return minutes >= 60 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes) min"
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
