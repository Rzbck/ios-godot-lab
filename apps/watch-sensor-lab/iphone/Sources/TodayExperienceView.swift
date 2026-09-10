import Charts
import SwiftUI

struct TodayExperienceView: View {
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
                    hero
                    quickGrid
                    todayWorkouts
                    movementTrend
                    healthGrid
                    actionRow
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [.cyan.opacity(0.10), .indigo.opacity(0.08), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
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
            .onAppear { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var todayRecords: [HealthWorkoutRecord] {
        let start = Calendar.current.startOfDay(for: Date())
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

    private var hero: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AUJOURD’HUI")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                    Text(todayRecords.isEmpty ? "Ta journée" : "\(todayRecords.count) activité\(todayRecords.count > 1 ? "s" : "")")
                        .font(.title2.weight(.black))
                    Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: tracker.isActive ? "waveform.path.ecg" : (todayRecords.isEmpty ? "sun.max.fill" : "bolt.heart.fill"))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(tracker.isActive ? .mint : .cyan)
                    .frame(width: 52, height: 52)
                    .background((tracker.isActive ? Color.mint : Color.cyan).opacity(0.12), in: Circle())
            }

            HStack(spacing: 18) {
                heroValue(todayDurationText(todayDuration), "actif")
                heroValue(todayDistanceText(todayDistance), "distance")
                heroValue(todayEnergy > 0 ? "\(Int(todayEnergy.rounded()))" : "—", "kcal")
            }

            Button(action: openActivity) {
                Label(tracker.isActive ? "Voir l’activité en cours" : "Démarrer", systemImage: tracker.isActive ? "waveform.path.ecg" : "play.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isActive ? .mint : .cyan)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.22), .indigo.opacity(0.14), .white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private var quickGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                TodayMetricDetailView(
                    title: "Activités aujourd’hui",
                    value: "\(todayRecords.count)",
                    subtitle: "Séances lisibles depuis Apple Health",
                    symbol: "figure.run",
                    accent: .orange,
                    records: todayRecords
                )
            } label: {
                TodayDrillCard(value: "\(todayRecords.count)", label: "SÉANCES", symbol: "figure.run", accent: .orange)
            }

            NavigationLink {
                TodayMetricDetailView(
                    title: "Temps actif",
                    value: todayDurationText(todayDuration),
                    subtitle: "Cumul des entraînements du jour",
                    symbol: "clock.fill",
                    accent: .cyan,
                    records: todayRecords
                )
            } label: {
                TodayDrillCard(value: todayDurationText(todayDuration), label: "TEMPS", symbol: "clock.fill", accent: .cyan)
            }

            NavigationLink {
                TodayMetricDetailView(
                    title: "Distance",
                    value: todayDistanceText(todayDistance),
                    subtitle: "Distance cumulée des séances du jour",
                    symbol: "location.fill",
                    accent: .mint,
                    records: todayRecords
                )
            } label: {
                TodayDrillCard(value: todayDistanceText(todayDistance), label: "DISTANCE", symbol: "location.fill", accent: .mint)
            }

            NavigationLink {
                TodayHealthDetailView(
                    title: "Pas",
                    value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                    subtitle: "Total Apple Health aujourd’hui",
                    symbol: "shoeprints.fill",
                    accent: .green,
                    points: []
                )
            } label: {
                TodayDrillCard(value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—", label: "PAS", symbol: "shoeprints.fill", accent: .green)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var todayWorkouts: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ACTIVITÉS DU JOUR")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Historique", action: openHistory)
                    .font(.caption.weight(.semibold))
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if todayRecords.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Aucune séance Apple Health lisible aujourd’hui.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                ForEach(todayRecords.prefix(6)) { record in
                    NavigationLink {
                        TodayWorkoutDetailView(record: record)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: record.activity.symbol)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(todaySportAccent(record.activity))
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.activity.label)
                                    .font(.subheadline.weight(.bold))
                                Text("\(record.startedAt.formatted(date: .omitted, time: .shortened)) · \(record.sourceName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(todayDurationText(record.duration))
                                    .font(.subheadline.weight(.bold))
                                if record.distanceMeters > 0 {
                                    Text(todayDistanceText(record.distanceMeters))
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
        .todayPanel()
    }

    private var movementTrend: some View {
        let points = lastSevenDays
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RYTHME RÉCENT")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("7 derniers jours")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Button("Progression", action: openProgression)
                    .font(.caption.weight(.semibold))
            }

            Chart(points, id: \.date) { point in
                BarMark(
                    x: .value("Jour", point.date, unit: .day),
                    y: .value("Minutes", point.minutes)
                )
                .foregroundStyle(point.isToday ? Color.cyan : Color.indigo.opacity(0.65))
                .cornerRadius(4)
            }
            .frame(height: 130)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel()
                }
            }
        }
        .todayPanel()
    }

    private var healthGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FORME / RÉCUPÉRATION")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Tout analyser", action: openProgression)
                    .font(.caption.weight(.semibold))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                healthLink("FC repos", health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—", "heart.fill", .pink, health.restingHeartRateTrend)
                healthLink("VFC", health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—", "waveform.path.ecg", .purple, health.hrvTrend)
                healthLink("Sommeil", health.sleepHours.map(todayHours) ?? "—", "bed.double.fill", .indigo, [])
                healthLink("VO₂ max", health.vo2Max.map { String(format: "%.1f", $0.value) } ?? "—", "lungs.fill", .cyan, [])
            }
        }
        .todayPanel()
    }

    private var actionRow: some View {
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

    private var lastSevenDays: [(date: Date, minutes: Double, isToday: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today),
                  let end = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
            let minutes = workouts
                .filter { $0.startedAt >= date && $0.startedAt < end }
                .reduce(0) { $0 + $1.duration } / 60
            return (date, minutes, calendar.isDateInToday(date))
        }
    }

    private func healthLink(_ title: String, _ value: String, _ symbol: String, _ accent: Color, _ points: [HealthTrendPoint]) -> some View {
        NavigationLink {
            TodayHealthDetailView(title: title, value: value, subtitle: "Données Apple Health lisibles", symbol: symbol, accent: accent, points: points)
        } label: {
            TodayDrillCard(value: value, label: title.uppercased(), symbol: symbol, accent: accent)
        }
        .buttonStyle(.plain)
    }

    private func heroValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() {
        loading = true
        workoutReader.loadAll { records in
            workouts = records
            loading = false
        }
        healthReader.load { result in health = result }
    }
}

private struct TodayDrillCard: View {
    let value: String
    let label: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .font(.caption.weight(.bold))
            Text(value)
                .font(.title3.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.68)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TodayMetricDetailView: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let records: [HealthWorkoutRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TodayDetailHero(title: title, value: value, subtitle: subtitle, symbol: symbol, accent: accent)
                ForEach(records) { record in
                    HStack(spacing: 10) {
                        Image(systemName: record.activity.symbol).foregroundStyle(todaySportAccent(record.activity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.activity.label).font(.subheadline.weight(.bold))
                            Text(record.startedAt, format: .dateTime.hour().minute())
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(todayDurationText(record.duration)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    .padding(12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayHealthDetailView: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let accent: Color
    let points: [HealthTrendPoint]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TodayDetailHero(title: title, value: value, subtitle: subtitle, symbol: symbol, accent: accent)
                if !points.isEmpty {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .foregroundStyle(accent)
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("Date", point.date), y: .value(title, point.value))
                            .foregroundStyle(accent)
                    }
                    .frame(height: 240)
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    ContentUnavailableView("Pas encore de série détaillée", systemImage: symbol, description: Text("La valeur reste affichée, et la courbe apparaîtra lorsque suffisamment d’échantillons lisibles seront disponibles."))
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayWorkoutDetailView: View {
    let record: HealthWorkoutRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                TodayDetailHero(title: record.activity.label, value: todayDurationText(record.duration), subtitle: record.sourceName, symbol: record.activity.symbol, accent: todaySportAccent(record.activity))
                HStack(spacing: 10) {
                    TodayDrillCard(value: todayDistanceText(record.distanceMeters), label: "DISTANCE", symbol: "location.fill", accent: .mint)
                    TodayDrillCard(value: record.activeEnergyKcal.map { "\(Int($0.rounded()))" } ?? "—", label: "KCAL", symbol: "flame.fill", accent: .orange)
                }
                .allowsHitTesting(false)
                Text(record.startedAt, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .navigationTitle("Séance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct TodayDetailHero: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: symbol).font(.title2.weight(.bold)).foregroundStyle(accent)
                Spacer()
            }
            Text(value).font(.system(size: 38, weight: .black, design: .rounded)).monospacedDigit()
            Text(title).font(.headline.weight(.bold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private extension View {
    func todayPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func todayDurationText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : "\(minutes) min"
}

private func todayDistanceText(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func todayHours(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}

private func todaySportAccent(_ activity: ActivityKind) -> Color {
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
