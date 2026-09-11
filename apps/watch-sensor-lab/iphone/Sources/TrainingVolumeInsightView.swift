import Charts
import SwiftUI

struct TrainingVolumeInsightView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workouts: [HealthWorkoutRecord] = []
    @State private var selectedSportRaw = "all"
    @State private var loading = true
    @State private var selectedWeekID: Int?

    private let reader = HealthWorkoutHistoryReader()
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero
                    volumeChart
                    sportBreakdown
                    recentSessions
                    provenanceNote
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.10), .indigo.opacity(0.08), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Volume récent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
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
        let recent = aggregate(recentRecords)
        let reference = referenceWeeklyAverage
        let delta = reference > 0 ? (recent.duration - reference) / reference : nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VOLUME · 7 JOURS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                    Text(volumeHeadline(delta: delta, hasRecent: recent.sessions > 0))
                        .font(.title2.weight(.black))
                    Text("Comparé à la moyenne hebdomadaire des 28 jours précédents")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 48, height: 48)
                    .background(.orange.opacity(0.13), in: Circle())
            }

            HStack(spacing: 18) {
                volumeHeroValue(volumeDuration(recent.duration), "7 jours")
                volumeHeroValue(reference > 0 ? volumeDuration(reference) : "—", "repère / sem.")
                volumeHeroValue(delta.map(volumeDeltaText) ?? "—", "écart")
            }

            if reference > 0 {
                GeometryReader { proxy in
                    let ratio = min(2.0, max(0, recent.duration / reference))
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan, .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * min(1, ratio / 1.5))
                        Rectangle()
                            .fill(.white.opacity(0.85))
                            .frame(width: 2)
                            .offset(x: proxy.size.width * (1.0 / 1.5))
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("moins")
                    Spacer()
                    Text("repère")
                    Spacer()
                    Text("plus")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .volumePanel()
    }

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÉVOLUTION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("4 semaines de référence + 7 jours actuels")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                if !loading {
                    Text("minutes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
            } else if weeklyBars.allSatisfy({ $0.minutes <= 0 }) {
                ContentUnavailableView(
                    "Pas assez d’historique",
                    systemImage: "chart.bar",
                    description: Text("Le graphique apparaîtra quand Apple Health fournira des entraînements sur cette période.")
                )
                .frame(height: 190)
            } else {
                Chart {
                    ForEach(weeklyBars) { bar in
                        BarMark(
                            x: .value(
                                "Semaine",
                                bar.id
                            ),
                            y: .value(
                                "Minutes",
                                bar.minutes
                            )
                        )
                        .foregroundStyle(
                            bar.isCurrent
                                ? Color.orange
                                : Color.indigo.opacity(0.72)
                        )
                        .cornerRadius(5)

                        if bar.id == selectedWeekBar?.id {
                            RuleMark(
                                x: .value(
                                    "Sélection",
                                    bar.id
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(0.45)
                            )
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
                                    Text(bar.label)
                                        .font(
                                            .caption2.weight(.black)
                                        )

                                    Text(
                                        volumeDuration(
                                            bar.minutes * 60
                                        )
                                    )
                                    .font(
                                        .caption.weight(.black)
                                    )
                                    .foregroundStyle(
                                        bar.isCurrent
                                            ? Color.orange
                                            : Color.cyan
                                    )
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
                        }
                    }

                    if referenceWeeklyAverage > 0 {
                        RuleMark(
                            y: .value(
                                "Repère",
                                referenceWeeklyAverage / 60
                            )
                        )
                        .foregroundStyle(
                            Color.cyan.opacity(0.9)
                        )
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2,
                                dash: [5, 4]
                            )
                        )
                    }
                }
                .chartXSelection(
                    value: $selectedWeekID
                )
                .chartXAxis {
                    AxisMarks(
                        values: [0, 1, 2, 3, 4]
                    ) { value in
                        AxisGridLine()
                            .foregroundStyle(
                                .white.opacity(0.05)
                            )

                        AxisValueLabel {
                            if
                                let id = value.as(Int.self),
                                let bar = weeklyBars.first(
                                    where: { $0.id == id }
                                )
                            {
                                Text(bar.label)
                            }
                        }
                    }
                }
                .frame(height: 210)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(
                                .white.opacity(0.07)
                            )
                        AxisValueLabel()
                    }
                }
            }
        }
        .volumePanel()
    }

    @ViewBuilder
    private var sportBreakdown: some View {
        let slices = sportSlices
        if !slices.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("SPORTS · 7 JOURS")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 10) {
                        Image(systemName: slice.activity.symbol)
                            .foregroundStyle(volumeSportAccent(slice.activity))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slice.activity.label)
                                .font(.subheadline.weight(.bold))
                            Text("\(slice.sessions) séance\(slice.sessions > 1 ? "s" : "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(volumeDuration(slice.duration))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
            .volumePanel()
        }
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SÉANCES CONCERNÉES")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(recentRecords.count)")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.orange)
            }

            if recentRecords.isEmpty {
                Text("Aucune séance lisible sur les 7 derniers jours pour ce filtre.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(Array(recentRecords.prefix(12))) { workout in
                    HStack(spacing: 10) {
                        Image(systemName: workout.activity.symbol)
                            .foregroundStyle(volumeSportAccent(workout.activity))
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.activity.label)
                                .font(.subheadline.weight(.bold))
                            Text(workout.startedAt, format: .dateTime.weekday(.abbreviated).day().month().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(volumeDuration(workout.duration))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .volumePanel()
    }

    private var provenanceNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Contexte de volume, pas diagnostic", systemImage: "info.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.cyan)
            Text("Cette vue compare uniquement la durée des entraînements Apple Health accessibles à l’app. Elle n’est pas présentée comme une charge physiologique. L’intensité, l’effort personnel et la récupération restent des signaux distincts.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var sportMenu: some View {
        Menu {
            Button { selectedSportRaw = "all" } label: {
                Label("Tous les sports", systemImage: "figure.mixed.cardio")
            }
            ForEach(availableSports) { sport in
                Button { selectedSportRaw = sport.rawValue } label: {
                    Label(sport.label, systemImage: sport.symbol)
                }
            }
        } label: {
            Image(systemName: selectedSportRaw == "all" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filtrer le volume par sport")
    }

    private var filteredWorkouts: [HealthWorkoutRecord] {
        selectedSportRaw == "all" ? workouts : workouts.filter { $0.activity.rawValue == selectedSportRaw }
    }

    private var recentStart: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today.addingTimeInterval(-6 * 86_400)
    }

    private var referenceStart: Date {
        calendar.date(byAdding: .day, value: -28, to: recentStart) ?? recentStart.addingTimeInterval(-28 * 86_400)
    }

    private var recentRecords: [HealthWorkoutRecord] {
        let now = Date()
        return filteredWorkouts
            .filter { $0.startedAt >= recentStart && $0.startedAt <= now }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var referenceRecords: [HealthWorkoutRecord] {
        filteredWorkouts.filter { $0.startedAt >= referenceStart && $0.startedAt < recentStart }
    }

    private var referenceWeeklyAverage: TimeInterval {
        referenceRecords.reduce(0) { $0 + $1.duration } / 4
    }

    private var weeklyBars: [VolumeWeekBar] {
        var result: [VolumeWeekBar] = []
        for index in 0..<4 {
            guard let start = calendar.date(byAdding: .day, value: index * 7, to: referenceStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start) else { continue }
            let duration = filteredWorkouts
                .filter { $0.startedAt >= start && $0.startedAt < end }
                .reduce(0) { $0 + $1.duration }
            result.append(
                VolumeWeekBar(
                    id: index,
                    label: "S-\(4 - index)",
                    minutes: duration / 60,
                    isCurrent: false
                )
            )
        }
        result.append(
            VolumeWeekBar(
                id: 4,
                label: "7 j",
                minutes: recentRecords.reduce(0) { $0 + $1.duration } / 60,
                isCurrent: true
            )
        )
        return result
    }

    private var selectedWeekBar: VolumeWeekBar? {
        guard let selectedWeekID else {
            return nil
        }

        return weeklyBars.first {
            $0.id == selectedWeekID
        }
    }

    private var sportSlices: [VolumeSportSlice] {
        let grouped = Dictionary(grouping: recentRecords, by: { $0.activity.rawValue })
        return grouped.compactMap { raw, records in
            guard let activity = ActivityKind(rawValue: raw) else { return nil }
            return VolumeSportSlice(
                activity: activity,
                duration: records.reduce(0) { $0 + $1.duration },
                sessions: records.count
            )
        }
        .sorted { $0.duration > $1.duration }
    }

    private var availableSports: [ActivityKind] {
        let raw = Set(workouts.map { $0.activity.rawValue })
        return raw.compactMap(ActivityKind.init(rawValue:)).sorted { $0.label < $1.label }
    }

    private func aggregate(_ records: [HealthWorkoutRecord]) -> VolumeAggregate {
        VolumeAggregate(
            sessions: records.count,
            duration: records.reduce(0) { $0 + $1.duration },
            distance: records.reduce(0) { $0 + $1.distanceMeters }
        )
    }

    private func refresh() {
        loading = true
        reader.loadAll { records in
            workouts = records
            loading = false
        }
    }

    private func volumeHeadline(delta: Double?, hasRecent: Bool) -> String {
        guard hasRecent else { return "Aucune séance récente" }
        guard let delta else { return "Nouveau repère" }
        if abs(delta) < 0.08 { return "Proche de ton repère" }
        return delta > 0 ? "Plus de volume récemment" : "Moins de volume récemment"
    }

    private func volumeDeltaText(_ delta: Double) -> String {
        String(format: "%+.0f%%", delta * 100)
    }

    private func volumeHeroValue(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.68)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct VolumeWeekBar: Identifiable {
    let id: Int
    let label: String
    let minutes: Double
    let isCurrent: Bool
}

private struct VolumeAggregate {
    let sessions: Int
    let duration: TimeInterval
    let distance: Double
}

private struct VolumeSportSlice: Identifiable {
    let activity: ActivityKind
    let duration: TimeInterval
    let sessions: Int
    var id: String { activity.rawValue }
}

private extension View {
    func volumePanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func volumeDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes) min"
}

private func volumeSportAccent(_ activity: ActivityKind) -> Color {
    switch activity {
    case .walking, .hiking: return .mint
    case .running, .trackAndField: return .orange
    case .cycling, .handCycling: return .yellow
    case .swimming, .rowing, .paddleSports, .waterFitness, .waterPolo, .waterSports, .sailing, .surfingSports, .underwaterDiving: return .blue
    case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining, .crossTraining, .highIntensityIntervalTraining: return .red
    case .yoga, .mindAndBody, .pilates, .taiChi, .flexibility: return .purple
    default: return .pink
    }
}
