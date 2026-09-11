import Charts
import SwiftUI

struct TodayCommandCenterView: View {
    @EnvironmentObject private var tracker: TrackerModel
    let openActivity: () -> Void
    let openProgression: () -> Void
    let openHistory: () -> Void

    @State private var workouts: [HealthWorkoutRecord] = []
    @State private var health = HealthProgressionData.empty
    @State private var loading = true
    @State private var showSettings = false

    private let workoutReader = HealthWorkoutHistoryReader()
    private let healthReader = HealthProgressionReader()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    commandHero
                    TrackerDailyBriefCard()
                    TrackerRecoveryIntelligenceCard()
                    todayMetrics
                    weeklyTrajectory
                    TrackerCardioFitnessCard()
                    recentWorkouts
                    healthPulse
                    footerActions
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(commandBackground)
            .navigationTitle("Aujourd’hui")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title3)
                    }
                    .accessibilityLabel("Profil et réglages")
                }
            }
            .sheet(isPresented: $showSettings) {
                TrackerSettingsView().environmentObject(tracker)
            }
            .refreshable { refresh() }
            .task { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var commandBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LinearGradient(
                colors: [.cyan.opacity(0.10), .indigo.opacity(0.08), .black.opacity(0)],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    private var todayRecords: [HealthWorkoutRecord] {
        let start = Calendar.autoupdatingCurrent.startOfDay(for: Date())
        return workouts.filter { $0.startedAt >= start }
    }

    private var todayDuration: TimeInterval {
        todayRecords.reduce(0) { $0 + $1.duration }
    }

    private var todayDistance: Double {
        todayRecords.reduce(0) { $0 + $1.distanceMeters }
    }

    private var todayEnergy: Double {
        todayRecords.compactMap(\.activeEnergyKcal).reduce(0, +)
    }

    private var commandHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(tracker.isActive ? Color.mint : Color.cyan)
                            .frame(width: 7, height: 7)
                        Text(tracker.isActive ? "SESSION ACTIVE" : "TON JOUR")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(tracker.isActive ? .mint : .cyan)
                    }
                    Text(heroTitle)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .minimumScaleFactor(0.75)
                        .lineLimit(2)
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().fill(.white.opacity(0.055))
                    Image(systemName: tracker.isActive ? "waveform.path.ecg" : heroSymbol)
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundStyle(tracker.isActive ? .mint : .cyan)
                }
                .frame(width: 56, height: 56)
            }

            HStack(spacing: 0) {
                heroMetric(commandDuration(todayDuration), label: "actif")
                heroDivider
                heroMetric(commandDistance(todayDistance), label: "distance")
                heroDivider
                heroMetric(todayEnergy > 0 ? "\(Int(todayEnergy.rounded()))" : "—", label: "kcal")
            }

            Button(action: openActivity) {
                HStack {
                    Image(systemName: tracker.isActive ? "waveform.path.ecg" : "play.fill")
                    Text(tracker.isActive ? "Revenir à la séance" : "Démarrer une activité")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.headline.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(tracker.isActive ? Color.mint : Color.cyan, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    (tracker.isActive ? Color.mint : Color.cyan).opacity(0.22),
                    Color.indigo.opacity(0.13),
                    Color.white.opacity(0.035),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Aujourd’hui, \(todayRecords.count) activités, \(commandDuration(todayDuration)) actives, \(commandDistance(todayDistance))")
    }

    private var heroTitle: String {
        if tracker.isActive { return tracker.displayActivity.label }
        if todayRecords.isEmpty { return "Prêt pour aujourd’hui" }
        if todayRecords.count == 1 { return todayRecords[0].activity.label }
        return "\(todayRecords.count) activités aujourd’hui"
    }

    private var heroSymbol: String {
        if let first = todayRecords.first { return first.activity.symbol }
        return "sparkles"
    }

    private var heroDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.08))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 11)
    }

    private func heroMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var todayMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("MOUVEMENT AUJOURD’HUI", symbol: "figure.walk.motion", accent: .mint)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                commandMetricLink(
                    title: "Pas",
                    value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                    subtitle: "Apple Health aujourd’hui",
                    symbol: "shoeprints.fill",
                    accent: .mint
                )
                commandMetricLink(
                    title: "Exercice",
                    value: health.exerciseMinutesToday.map { "\(Int($0.rounded())) min" } ?? "—",
                    subtitle: "Minutes exercice Apple",
                    symbol: "timer",
                    accent: .cyan
                )
                commandMetricLink(
                    title: "Énergie active",
                    value: health.activeEnergyToday.map { "\(Int($0.rounded())) kcal" } ?? "—",
                    subtitle: "Total Santé aujourd’hui",
                    symbol: "flame.fill",
                    accent: .orange
                )
                NavigationLink {
                    TodayCommandWorkoutList(records: todayRecords)
                } label: {
                    TodayCommandMetricCard(
                        value: "\(todayRecords.count)",
                        label: "SÉANCES",
                        symbol: "figure.run",
                        accent: .pink
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .commandPanel()
    }

    private var weeklyTrajectory: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                sectionHeader("TRAJECTOIRE 7 JOURS", symbol: "chart.xyaxis.line", accent: .cyan)
                Spacer()
                Button("Détails", action: openProgression)
                    .font(.caption.weight(.semibold))
            }

            Text(weeklyComparisonHeadline)
                .font(.title3.weight(.black))

            Chart(weeklyComparisonPoints) { point in
                LineMark(
                    x: .value("Jour de période", point.index),
                    y: .value("Minutes cumulées", point.minutes)
                )
                .foregroundStyle(by: .value("Période", point.period))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: point.period == "Cette semaine" ? 3 : 2))

                if point.period == "Cette semaine" {
                    AreaMark(
                        x: .value("Jour de période", point.index),
                        y: .value("Minutes cumulées", point.minutes)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan.opacity(0.16), .cyan.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .chartForegroundStyleScale([
                "Cette semaine": Color.cyan,
                "Précédente": Color.white.opacity(0.32),
            ])
            .chartXAxis {
                AxisMarks(values: [1, 3, 5, 7]) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.04))
                    AxisValueLabel {
                        if let index = value.as(Int.self) { Text("J\(index)") }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.05))
                    AxisValueLabel()
                }
            }
            .frame(height: 155)
            .accessibilityLabel("Comparaison cumulative du temps d’entraînement des sept derniers jours avec les sept jours précédents")

            HStack(spacing: 14) {
                commandLegend("Cette semaine", .cyan)
                commandLegend("Précédente", .white.opacity(0.45))
            }
        }
        .commandPanel()
    }

    private struct WeeklyPoint: Identifiable {
        let period: String
        let index: Int
        let minutes: Double
        var id: String { "\(period)-\(index)" }
    }

    private var weeklyComparisonPoints: [WeeklyPoint] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        var values: [WeeklyPoint] = []
        var currentCumulative = 0.0
        var previousCumulative = 0.0

        for index in 1...7 {
            let currentOffset = -(7 - index)
            let previousOffset = -(14 - index)
            if let currentDay = calendar.date(byAdding: .day, value: currentOffset, to: today),
               let currentEnd = calendar.date(byAdding: .day, value: 1, to: currentDay) {
                currentCumulative += workouts
                    .filter { $0.startedAt >= currentDay && $0.startedAt < currentEnd }
                    .reduce(0) { $0 + $1.duration } / 60
            }
            if let previousDay = calendar.date(byAdding: .day, value: previousOffset, to: today),
               let previousEnd = calendar.date(byAdding: .day, value: 1, to: previousDay) {
                previousCumulative += workouts
                    .filter { $0.startedAt >= previousDay && $0.startedAt < previousEnd }
                    .reduce(0) { $0 + $1.duration } / 60
            }
            values.append(WeeklyPoint(period: "Cette semaine", index: index, minutes: currentCumulative))
            values.append(WeeklyPoint(period: "Précédente", index: index, minutes: previousCumulative))
        }
        return values
    }

    private var weeklyComparisonHeadline: String {
        let points = weeklyComparisonPoints
        let current = points.last(where: { $0.period == "Cette semaine" })?.minutes ?? 0
        let previous = points.last(where: { $0.period == "Précédente" })?.minutes ?? 0
        guard previous > 0 else {
            return current > 0 ? "\(Int(current.rounded())) min ces 7 derniers jours" : "Construis ta première référence"
        }
        let delta = (current - previous) / previous * 100
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(Int(delta.rounded()))% de temps actif"
    }

    @ViewBuilder
    private var recentWorkouts: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("AUJOURD’HUI · SÉANCES", symbol: "clock.fill", accent: .orange)
                Spacer()
                Button("Historique", action: openHistory)
                    .font(.caption.weight(.semibold))
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 10)
            } else if todayRecords.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aucune séance aujourd’hui")
                            .font(.subheadline.weight(.semibold))
                        Text("Le mouvement quotidien reste visible au-dessus.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            } else {
                ForEach(todayRecords.prefix(4)) { record in
                    NavigationLink {
                        TodayCommandWorkoutDetail(record: record)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: record.activity.symbol)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(commandSportAccent(record.activity))
                                .frame(width: 38, height: 38)
                                .background(commandSportAccent(record.activity).opacity(0.10), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.activity.label)
                                    .font(.subheadline.weight(.bold))
                                Text("\(record.startedAt.formatted(date: .omitted, time: .shortened)) · \(record.sourceName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(commandDuration(record.duration))
                                .font(.subheadline.weight(.black))
                                .monospacedDigit()
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
        .commandPanel()
    }

    private var healthPulse: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("SIGNAUX SANTÉ", symbol: "waveform.path.ecg", accent: .purple)
                Spacer()
                Button("Analyser", action: openProgression)
                    .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                commandHealthLink(
                    title: "FC repos",
                    value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                    symbol: "heart.fill",
                    accent: .pink,
                    points: health.restingHeartRateTrend
                )
                commandHealthLink(
                    title: "VFC",
                    value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                    symbol: "waveform.path.ecg",
                    accent: .purple,
                    points: health.hrvTrend
                )
                commandHealthLink(
                    title: "Sommeil",
                    value: health.sleepHours.map(commandHours) ?? "—",
                    symbol: "bed.double.fill",
                    accent: .indigo,
                    points: []
                )
                commandHealthLink(
                    title: "VO₂ max",
                    value: health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—",
                    symbol: "lungs.fill",
                    accent: .orange,
                    points: []
                )
            }
        }
        .commandPanel()
    }

    private var footerActions: some View {
        HStack(spacing: 10) {
            Button(action: openProgression) {
                Label("Progression", systemImage: "chart.xyaxis.line")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button(action: openHistory) {
                Label("Historique", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func sectionHeader(_ title: String, symbol: String, accent: Color) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.black))
            .foregroundStyle(accent)
    }

    private func commandMetricLink(
        title: String,
        value: String,
        subtitle: String,
        symbol: String,
        accent: Color
    ) -> some View {
        NavigationLink {
            TodayCommandMetricDetail(title: title, value: value, subtitle: subtitle, symbol: symbol, accent: accent)
        } label: {
            TodayCommandMetricCard(value: value, label: title.uppercased(), symbol: symbol, accent: accent)
        }
        .buttonStyle(.plain)
    }

    private func commandHealthLink(
        title: String,
        value: String,
        symbol: String,
        accent: Color,
        points: [HealthTrendPoint]
    ) -> some View {
        NavigationLink {
            TodayCommandHealthDetail(title: title, value: value, symbol: symbol, accent: accent, points: points)
        } label: {
            TodayCommandMetricCard(value: value, label: title.uppercased(), symbol: symbol, accent: accent)
        }
        .buttonStyle(.plain)
    }

    private func commandLegend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 14, height: 3)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        loading = true
        workoutReader.loadAll { records in
            workouts = records
            loading = false
        }
        healthReader.load { health = $0 }
    }
}

private struct TodayCommandMetricCard: View {
    let value: String
    let label: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.title3.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(label)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(accent.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct TodayCommandMetricDetail: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title.weight(.bold))
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
            Text(title).font(.title3.weight(.bold))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayCommandHealthDetail: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color
    let points: [HealthTrendPoint]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: symbol).font(.title2.weight(.bold)).foregroundStyle(accent)
                    Text(value).font(.system(size: 40, weight: .black, design: .rounded)).monospacedDigit()
                    Text(title).font(.headline.weight(.bold))
                    Text("Apple Health · provenance conservée")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if points.count >= 2 {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .foregroundStyle(accent)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .foregroundStyle(accent)
                    }
                    .frame(height: 230)
                    .padding(14)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel("Évolution de \(title) sur les données Apple Health lisibles")
                } else {
                    ContentUnavailableView(
                        "Tendance en construction",
                        systemImage: symbol,
                        description: Text("La valeur reste visible. La courbe apparaîtra lorsque plusieurs échantillons seront disponibles.")
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayCommandWorkoutList: View {
    let records: [HealthWorkoutRecord]

    var body: some View {
        List(records) { record in
            NavigationLink {
                TodayCommandWorkoutDetail(record: record)
            } label: {
                HStack {
                    Image(systemName: record.activity.symbol).foregroundStyle(commandSportAccent(record.activity))
                    VStack(alignment: .leading) {
                        Text(record.activity.label).font(.headline)
                        Text(record.startedAt, format: .dateTime.hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(commandDuration(record.duration)).monospacedDigit()
                }
            }
        }
        .navigationTitle("Séances du jour")
    }
}

private struct TodayCommandWorkoutDetail: View {
    let record: HealthWorkoutRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: record.activity.symbol)
                        .font(.title.weight(.bold))
                        .foregroundStyle(commandSportAccent(record.activity))
                    Spacer()
                    Text(record.sourceName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(record.activity.label)
                    .font(.largeTitle.weight(.black))
                HStack(spacing: 9) {
                    TodayCommandMetricCard(value: commandDuration(record.duration), label: "DURÉE", symbol: "timer", accent: .cyan)
                    TodayCommandMetricCard(value: commandDistance(record.distanceMeters), label: "DISTANCE", symbol: "location.fill", accent: .mint)
                }
                .allowsHitTesting(false)
                if let energy = record.activeEnergyKcal {
                    TodayCommandMetricCard(value: "\(Int(energy.rounded())) kcal", label: "ÉNERGIE", symbol: "flame.fill", accent: .orange)
                        .allowsHitTesting(false)
                }
                Text(record.startedAt, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle("Séance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func commandPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.048), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.045), lineWidth: 1)
            }
    }
}

private func commandDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : "\(minutes) min"
}

private func commandDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func commandHours(_ hours: Double) -> String {
    commandDuration(hours * 3600)
}

private func commandSportAccent(_ activity: ActivityKind) -> Color {
    switch activity {
    case .walking, .hiking: return .mint
    case .running, .trackAndField: return .orange
    case .cycling, .handCycling: return .yellow
    case .swimming, .rowing, .paddleSports, .waterSports, .waterFitness, .waterPolo, .underwaterDiving, .sailing, .surfingSports: return .blue
    case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining, .highIntensityIntervalTraining, .crossTraining: return .red
    case .yoga, .mindAndBody, .pilates, .taiChi, .flexibility: return .purple
    default: return .pink
    }
}
