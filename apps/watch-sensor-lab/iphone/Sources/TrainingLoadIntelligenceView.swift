import Charts
import SwiftUI

private enum TrainingLoadPage: String, CaseIterable, Identifiable {
    case volume
    case srpe
    case tracker
    case recovery

    var id: String { rawValue }

    var label: String {
        switch self {
        case .volume: return "Volume"
        case .srpe: return "sRPE"
        case .tracker: return "Tracker"
        case .recovery: return "Récup."
        }
    }

    var symbol: String {
        switch self {
        case .volume: return "clock.fill"
        case .srpe: return "person.fill.checkmark"
        case .tracker: return "scope"
        case .recovery: return "sparkles"
        }
    }

    var accent: Color {
        switch self {
        case .volume: return .cyan
        case .srpe: return .purple
        case .tracker: return .orange
        case .recovery: return .mint
        }
    }
}

struct TrainingLoadIntelligenceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var healthWorkouts: [HealthWorkoutRecord] = []
    @State private var summaries: [TrackerSummary] = []
    @State private var recovery: TrackerRecoverySnapshot?
    @State private var selectedSportRaw = "all"
    @State private var loading = true
    @State private var page: TrainingLoadPage = .volume
    @State private var selectedVolumeDate: Date?
    @State private var selectedSrpeDate: Date?
    @State private var selectedEffortDate: Date?

    private let healthReader = HealthWorkoutHistoryReader()
    private let recoveryReader = TrackerRecoveryIntelligenceReader()
    private let reviewStore = ActivityReviewStore()
    private let store = NativeSessionStore()
    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    hero
                    loadStack
                    recentSessions
                    methodology
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [.purple.opacity(0.12), .cyan.opacity(0.07), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Charge · Multi-source")
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
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CHARGE · 4 AXES")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.purple)
                    Text("Pas de score magique")
                        .font(.title2.weight(.black))
                    Text("Volume, ressenti, intensité Tracker et récupération restent visibles séparément.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.grid.2x2.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.purple)
                    .frame(width: 48, height: 48)
                    .background(.purple.opacity(0.13), in: Circle())
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ],
                spacing: 8
            ) {
                Button {
                    withAnimation(.snappy) {
                        page = .volume
                    }
                } label: {
                    axisCell(
                        "VOLUME",
                        ratioText(volumeRatio),
                        loadStatus(volumeRatio),
                        "clock.fill",
                        .cyan
                    )
                }

                Button {
                    withAnimation(.snappy) {
                        page = .srpe
                    }
                } label: {
                    axisCell(
                        "sRPE",
                        ratioText(srpeRatio),
                        srpeCoverageText,
                        "person.fill.checkmark",
                        .purple
                    )
                }

                Button {
                    withAnimation(.snappy) {
                        page = .tracker
                    }
                } label: {
                    axisCell(
                        "TRACKER",
                        trackerEffortText,
                        trackerEffortDeltaText,
                        "scope",
                        .orange
                    )
                }

                Button {
                    withAnimation(.snappy) {
                        page = .recovery
                    }
                } label: {
                    axisCell(
                        "RÉCUP",
                        recovery?.score.map {
                            "\(Int($0.rounded())) / 100"
                        } ?? "—",
                        recovery?.label
                            ?? "Repères en construction",
                        "sparkles",
                        recoveryAccentColor
                    )
                }
            }
            .buttonStyle(TrackerDepthButtonStyle())
        }
        .loadPanel()
    }

    private var loadStack: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AXES")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                Spacer()

                Label(
                    "glisse",
                    systemImage: "arrow.left.and.right"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            }

            HStack(spacing: 6) {
                ForEach(TrainingLoadPage.allCases) { candidate in
                    Button {
                        withAnimation(.snappy) {
                            page = candidate
                        }
                    } label: {
                        Label(
                            candidate.label,
                            systemImage: candidate.symbol
                        )
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(
                            page == candidate
                                ? Color.black
                                : Color.primary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            page == candidate
                                ? candidate.accent
                                : Color.white.opacity(0.07),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(TrackerDepthButtonStyle())
                }
            }

            TabView(selection: $page) {
                volumePanel
                    .tag(TrainingLoadPage.volume)

                srpePanel
                    .tag(TrainingLoadPage.srpe)

                trackerIntensityPanel
                    .tag(TrainingLoadPage.tracker)

                recoveryPanel
                    .tag(TrainingLoadPage.recovery)
            }
            .frame(height: 320)
            .tabViewStyle(
                .page(indexDisplayMode: .never)
            )
        }
    }

    private var volumePanel: some View {        let recentMinutes = recentHealth.reduce(0) { $0 + $1.duration } / 60
        let referenceMinutes = referenceHealth.reduce(0) { $0 + $1.duration } / 60 / 4

        return VStack(alignment: .leading, spacing: 11) {
            panelHeader("VOLUME · APPLE HEALTH", "Toutes les séances accessibles", "heart.text.square.fill", .cyan)

            HStack(spacing: 12) {
                loadMetric(loadDuration(recentMinutes * 60), "7 jours")
                loadMetric(referenceMinutes > 0 ? loadDuration(referenceMinutes * 60) : "—", "repère / sem.")
                loadMetric(ratioText(volumeRatio), "ratio")
            }

            Chart {
                ForEach(volumeDays) { point in
                    BarMark(
                        x: .value(
                            "Jour",
                            point.date,
                            unit: .day
                        ),
                        y: .value(
                            "Minutes",
                            point.volumeMinutes
                        )
                    )
                    .foregroundStyle(Color.cyan.gradient)
                    .cornerRadius(4)

                    if point.id == selectedVolumePoint?.id {
                        RuleMark(
                            x: .value(
                                "Sélection",
                                point.date
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.45)
                        )
                        .annotation(
                            position: .top,
                            spacing: 4
                        ) {
                            loadSelectionBadge(
                                date: point.date,
                                value: point.volumeMinutes,
                                suffix: "min",
                                accent: .cyan
                            )
                        }
                    }
                }

                if referenceDailyVolumeMinutes > 0 {
                    RuleMark(
                        y: .value(
                            "Repère",
                            referenceDailyVolumeMinutes
                        )
                    )
                    .foregroundStyle(.white.opacity(0.35))
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 1,
                            dash: [4, 4]
                        )
                    )
                }
            }
            .chartXSelection(
                value: $selectedVolumeDate
            )
            .frame(height: 160)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(
                            .white.opacity(0.06)
                        )
                    AxisValueLabel()
                }
            }

            Text("Comparaison descriptive des 7 derniers jours à la moyenne hebdomadaire des 28 jours précédents, comme contexte de volume.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .loadPanel()
    }

    private var srpePanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader("CHARGE INTERNE · sRPE", "Durée × ton ressenti 1–10", "person.fill.checkmark", .purple)

            HStack(spacing: 12) {
                loadMetric(srpeRecentTotal.map { String(format: "%.0f UA", $0) } ?? "—", "7 jours")
                loadMetric(srpeReferenceWeekly.map { String(format: "%.0f UA", $0) } ?? "—", "repère / sem.")
                loadMetric(srpeCoverageText, "couverture")
            }

            if srpeRecentCoverage > 0 {
                Chart {
                    ForEach(loadDays) { point in
                        BarMark(
                            x: .value(
                                "Jour",
                                point.date,
                                unit: .day
                            ),
                            y: .value(
                                "sRPE",
                                point.srpeLoad
                            )
                        )
                        .foregroundStyle(
                            Color.purple.gradient
                        )
                        .cornerRadius(4)

                        if point.id == selectedSrpePoint?.id {
                            RuleMark(
                                x: .value(
                                    "Sélection",
                                    point.date
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(0.45)
                            )
                            .annotation(
                                position: .top,
                                spacing: 4
                            ) {
                                loadSelectionBadge(
                                    date: point.date,
                                    value: point.srpeLoad,
                                    suffix: "UA",
                                    accent: .purple
                                )
                            }
                        }
                    }

                    if
                        let reference = srpeReferenceDaily,
                        reference > 0
                    {
                        RuleMark(
                            y: .value(
                                "Repère",
                                reference
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.35)
                        )
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 1,
                                dash: [4, 4]
                            )
                        )
                    }
                }
                .chartXSelection(
                    value: $selectedSrpeDate
                )
                .frame(height: 160)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(
                                .white.opacity(0.06)
                            )
                        AxisValueLabel()
                    }
                }
            } else {
                ContentUnavailableView(
                    "Ressenti à renseigner",
                    systemImage: "person.fill.questionmark",
                    description: Text("Note quelques séances de 1 à 10 après l’effort pour construire une vraie charge interne session-RPE.")
                )
                .frame(minHeight: 145)
            }

            Text("UA = unités arbitraires session-RPE. Elles ne sont calculées que lorsque TU as renseigné ton ressenti ; une valeur manquante n’est pas remplacée par l’estimation Tracker.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .loadPanel()
    }

    private var trackerIntensityPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader("INTENSITÉ · TRACKER", "Estimation locale, gardée séparée", "scope", .orange)

            HStack(spacing: 12) {
                loadMetric(trackerEffortText, "moy. 7 jours")
                loadMetric(referenceTrackerEffortText, "moy. 28 jours")
                loadMetric("\(recentLocal.count)", "séances Tracker")
            }

            if !recentLocal.isEmpty {
                Chart(recentLocalEffortPoints) { point in
                    LineMark(
                        x: .value(
                            "Séance",
                            point.date
                        ),
                        y: .value(
                            "Effort",
                            point.effort
                        )
                    )
                    .foregroundStyle(
                        .orange.opacity(0.72)
                    )
                    .lineStyle(
                        StrokeStyle(
                            lineWidth: 2.4,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    PointMark(
                        x: .value(
                            "Séance",
                            point.date
                        ),
                        y: .value(
                            "Effort",
                            point.effort
                        )
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(
                        point.id == selectedEffortPoint?.id
                            ? 80
                            : 42
                    )

                    if point.id == selectedEffortPoint?.id {
                        RuleMark(
                            x: .value(
                                "Sélection",
                                point.date
                            )
                        )
                        .foregroundStyle(
                            .white.opacity(0.45)
                        )
                        .annotation(
                            position: .top,
                            spacing: 4
                        ) {
                            loadSelectionBadge(
                                date: point.date,
                                value: point.effort,
                                suffix: "/10",
                                accent: .orange
                            )
                        }
                    }
                }
                .chartXSelection(
                    value: $selectedEffortDate
                )
                .chartYScale(domain: 1...10)
                .frame(height: 150)
            }

            Text("Cette estimation utilise notamment zones cardio, durée, continuité, relief et contexte météo disponibles. Elle n’est jamais utilisée pour fabriquer ton ressenti personnel.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .loadPanel()
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            panelHeader("RÉCUPÉRATION · CONTEXTE", "À lire à côté de la charge, pas à fusionner", "sparkles", recoveryAccentColor)

            if let recovery {
                HStack(spacing: 12) {
                    loadMetric(recovery.score.map { "\(Int($0.rounded()))" } ?? "—", "indice / 100")
                    loadMetric("\(Int(recovery.confidence.rounded()))%", "confiance")
                    loadMetric(recovery.workloadRatio.map { String(format: "%.2fx", $0) } ?? "—", "volume 7j/28j")
                }
                Text(recovery.label)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(recoveryAccentColor)
                Text(recovery.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Construction des repères de récupération…")
                    .font(.caption)
            }
        }
        .loadPanel()
    }

    private var recentSessions: some View {
        VStack(alignment: .leading, spacing: 9) {
            panelHeader("SÉANCES TRACKER · 7 JOURS", "Provenance visible séance par séance", "list.bullet.rectangle", .mint)

            if recentLocal.isEmpty {
                Text("Aucune séance Tracker locale sur cette période pour ce filtre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentLocal.prefix(12), id: \.sessionID) { summary in
                    let rpe = perceivedEffort(summary)
                    let estimate = TrackerEffortEstimator().estimate(summary: summary)
                    HStack(spacing: 10) {
                        Image(systemName: activityKind(summary)?.symbol ?? "figure.mixed.cardio")
                            .foregroundStyle(.mint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activityKind(summary)?.label ?? summary.activity)
                                .font(.subheadline.weight(.bold))
                            Text(summary.startedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(rpe.map { "RPE \($0)" } ?? String(format: "T %.1f", estimate.score))
                                .font(.caption.weight(.black))
                                .foregroundStyle(rpe == nil ? .orange : .purple)
                            Text(loadDuration(summary.duration))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .loadPanel()
    }

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Lecture transparente", systemImage: "checkmark.shield.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            Text("Le volume inclut tous les workouts Apple Health lisibles. Le sRPE utilise uniquement les séances Tracker pour lesquelles tu as saisi un ressenti. L’intensité Tracker reste une estimation locale. L’indice de récupération reste indépendant. Aucun ratio n’est présenté comme prédicteur de blessure ou diagnostic médical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
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
        .accessibilityLabel("Filtrer la charge par sport")
    }

    private var filteredHealth: [HealthWorkoutRecord] {
        selectedSportRaw == "all" ? healthWorkouts : healthWorkouts.filter { $0.activity.rawValue == selectedSportRaw }
    }

    private var filteredLocal: [TrackerSummary] {
        selectedSportRaw == "all" ? summaries : summaries.filter { activityKind($0)?.rawValue == selectedSportRaw }
    }

    private var recentStart: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: -6, to: today) ?? today.addingTimeInterval(-6 * 86_400)
    }

    private var referenceStart: Date {
        calendar.date(byAdding: .day, value: -28, to: recentStart) ?? recentStart.addingTimeInterval(-28 * 86_400)
    }

    private var recentHealth: [HealthWorkoutRecord] {
        filteredHealth.filter { $0.startedAt >= recentStart && $0.startedAt <= Date() }
    }

    private var referenceHealth: [HealthWorkoutRecord] {
        filteredHealth.filter { $0.startedAt >= referenceStart && $0.startedAt < recentStart }
    }

    private var recentLocal: [TrackerSummary] {
        filteredLocal
            .filter { $0.startedAt >= recentStart && $0.startedAt <= Date() }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var referenceLocal: [TrackerSummary] {
        filteredLocal.filter { $0.startedAt >= referenceStart && $0.startedAt < recentStart }
    }

    private var volumeRatio: Double? {
        let recent = recentHealth.reduce(0.0) { $0 + $1.duration }
        let reference = referenceHealth.reduce(0.0) { $0 + $1.duration } / 4
        guard reference > 0 else { return nil }
        return recent / reference
    }

    private var referenceDailyVolumeMinutes: Double {
        referenceHealth.reduce(0.0) { $0 + $1.duration } / 60 / 28
    }

    private var volumeDays: [LoadDayPoint] {
        dayPoints.map { day in
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let volume = recentHealth
                .filter { $0.startedAt >= day && $0.startedAt < end }
                .reduce(0.0) { $0 + $1.duration } / 60
            return LoadDayPoint(date: day, volumeMinutes: volume, srpeLoad: 0)
        }
    }

    private var loadDays: [LoadDayPoint] {
        dayPoints.map { day in
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let sessions = recentLocal.filter { $0.startedAt >= day && $0.startedAt < end }
            let load = sessions.reduce(0.0) { partial, summary in
                guard let rpe = perceivedEffort(summary) else { return partial }
                return partial + summary.duration / 60 * Double(rpe)
            }
            return LoadDayPoint(date: day, volumeMinutes: 0, srpeLoad: load)
        }
    }

    private var dayPoints: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: recentStart) }
    }

    private var srpeRecentTotal: Double? {
        let values = recentLocal.compactMap { summary -> Double? in
            guard let rpe = perceivedEffort(summary) else { return nil }
            return summary.duration / 60 * Double(rpe)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private var srpeReferenceWeekly: Double? {
        let values = referenceLocal.compactMap { summary -> Double? in
            guard let rpe = perceivedEffort(summary) else { return nil }
            return summary.duration / 60 * Double(rpe)
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / 4
    }

    private var srpeReferenceDaily: Double? {
        srpeReferenceWeekly.map { $0 / 7 }
    }

    private var srpeRatio: Double? {
        guard let recent = srpeRecentTotal,
              let reference = srpeReferenceWeekly,
              reference > 0 else { return nil }
        return recent / reference
    }

    private var srpeRecentCoverage: Double {
        guard !recentLocal.isEmpty else { return 0 }
        let rated = recentLocal.filter { perceivedEffort($0) != nil }.count
        return Double(rated) / Double(recentLocal.count)
    }

    private var srpeCoverageText: String {
        guard !recentLocal.isEmpty else { return "—" }
        return "\(Int((srpeRecentCoverage * 100).rounded()))%"
    }

    private var recentTrackerEffort: Double? {
        averageEffort(recentLocal)
    }

    private var referenceTrackerEffort: Double? {
        averageEffort(referenceLocal)
    }

    private var trackerEffortText: String {
        recentTrackerEffort.map { String(format: "%.1f / 10", $0) } ?? "—"
    }

    private var referenceTrackerEffortText: String {
        referenceTrackerEffort.map { String(format: "%.1f / 10", $0) } ?? "—"
    }

    private var trackerEffortDeltaText: String {
        guard let recent = recentTrackerEffort, let reference = referenceTrackerEffort else { return "repère incomplet" }
        return String(format: "%+.1f vs 28j", recent - reference)
    }

    private var recentLocalEffortPoints: [LoadEffortPoint] {
        recentLocal
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                LoadEffortPoint(
                    id: $0.sessionID,
                    date: $0.startedAt,
                    effort: TrackerEffortEstimator().estimate(summary: $0).score
                )
            }
    }

    private var selectedVolumePoint: LoadDayPoint? {
        nearest(
            volumeDays,
            to: selectedVolumeDate
        )
    }

    private var selectedSrpePoint: LoadDayPoint? {
        nearest(
            loadDays,
            to: selectedSrpeDate
        )
    }

    private var selectedEffortPoint: LoadEffortPoint? {
        guard let selectedEffortDate else {
            return nil
        }

        return recentLocalEffortPoints.min {
            abs(
                $0.date.timeIntervalSince(selectedEffortDate)
            )
            <
            abs(
                $1.date.timeIntervalSince(selectedEffortDate)
            )
        }
    }

    private func nearest(
        _ points: [LoadDayPoint],
        to selected: Date?
    ) -> LoadDayPoint? {
        guard let selected else {
            return nil
        }

        return points.min {
            abs(
                $0.date.timeIntervalSince(selected)
            )
            <
            abs(
                $1.date.timeIntervalSince(selected)
            )
        }
    }

    private func loadSelectionBadge(
        date: Date,
        value: Double,
        suffix: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(
                date.formatted(
                    .dateTime
                        .weekday(.abbreviated)
                        .day()
                        .month(.abbreviated)
                )
            )
            .font(.caption2.weight(.black))

            Text(
                String(
                    format: "%.1f %@",
                    value,
                    suffix
                )
            )
            .font(.caption.weight(.black))
            .foregroundStyle(accent)
            .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: 9,
                style: .continuous
            )
        )
        .allowsHitTesting(false)
    }

    private var availableSports: [ActivityKind] {        var raw = Set(healthWorkouts.map { $0.activity.rawValue })
        for summary in summaries {
            if let kind = activityKind(summary) { raw.insert(kind.rawValue) }
        }
        return raw.compactMap(ActivityKind.init(rawValue:)).sorted { $0.label < $1.label }
    }

    private var recoveryAccentColor: Color {
        guard let score = recovery?.score else { return .secondary }
        switch score {
        case 85...: return .mint
        case 70...: return .cyan
        case 55...: return .orange
        default: return .pink
        }
    }

    private func refresh() {
        loading = true
        summaries = store.listSummaries()

        let group = DispatchGroup()
        group.enter()
        healthReader.loadAll { values in
            healthWorkouts = values
            group.leave()
        }
        group.enter()
        recoveryReader.load { value in
            recovery = value
            group.leave()
        }
        group.notify(queue: .main) {
            loading = false
        }
    }

    private func activityKind(_ summary: TrackerSummary) -> ActivityKind? {
        ActivityKind(rawValue: reviewStore.effectiveActivity(for: summary))
    }

    private func perceivedEffort(_ summary: TrackerSummary) -> Int? {
        let value = UserDefaults.standard.integer(forKey: "tracker.perceivedEffort.\(summary.sessionID)")
        return (1...10).contains(value) ? value : nil
    }

    private func averageEffort(_ values: [TrackerSummary]) -> Double? {
        guard !values.isEmpty else { return nil }
        let scores = values.map { TrackerEffortEstimator().estimate(summary: $0).score }
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }

    private func ratioText(_ ratio: Double?) -> String {
        ratio.map { String(format: "%.2fx", $0) } ?? "—"
    }

    private func loadStatus(_ ratio: Double?) -> String {
        guard let ratio else { return "repère insuffisant" }
        switch ratio {
        case ..<0.65: return "bien en dessous"
        case ..<0.90: return "un peu en dessous"
        case ..<1.15: return "proche du repère"
        case ..<1.45: return "au-dessus"
        default: return "nettement au-dessus"
        }
    }

    private func axisCell(_ title: String, _ value: String, _ detail: String, _ symbol: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Spacer()
            }
            Text(title)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(11)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func panelHeader(_ eyebrow: String, _ title: String, _ symbol: String, _ accent: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.caption.weight(.black))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.headline.weight(.bold))
            }
            Spacer()
            Image(systemName: symbol)
                .foregroundStyle(accent)
        }
    }

    private func loadMetric(_ value: String, _ label: String) -> some View {
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
}

private struct LoadDayPoint: Identifiable {
    let date: Date
    let volumeMinutes: Double
    let srpeLoad: Double
    var id: Date { date }
}

private struct LoadEffortPoint: Identifiable {
    let id: String
    let date: Date
    let effort: Double
}

private extension View {
    func loadPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func loadDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes) min"
}
