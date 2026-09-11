import Charts
import SwiftUI

struct MatchedActivityComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var summaries: [TrackerSummary] = []
    @State private var selectedSessionID: String?
    @State private var selectedChartDate: Date?

    private let store = NativeSessionStore()
    private let reviewStore = ActivityReviewStore()
    private let effortEstimator = TrackerEffortEstimator()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if let anchor {
                        anchorCard(anchor)
                        matchQualityCard(anchor)

                        if matches.isEmpty {
                            ContentUnavailableView(
                                "Pas encore de séance comparable",
                                systemImage: "square.stack.3d.up.slash",
                                description: Text("Tracker attend une autre séance du même sport avec une distance ou une durée suffisamment proche.")
                            )
                            .frame(minHeight: 260)
                        } else {
                            comparisonChart(anchor)
                            matchStack(anchor)
                            methodology
                        }
                    } else {
                        ContentUnavailableView(
                            "Aucune séance Tracker locale",
                            systemImage: "figure.run",
                            description: Text("Enregistre d’abord une séance avec Watch Tracker.")
                        )
                        .frame(minHeight: 300)
                    }
                }
                .padding(16)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [.mint.opacity(0.10), .cyan.opacity(0.06), .black],
                    startPoint: .topLeading,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Séances similaires")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    anchorMenu
                }
            }
            .onAppear { refresh() }
        }
        .preferredColorScheme(.dark)
    }

    private var anchor: TrackerSummary? {
        guard let selectedSessionID else { return summaries.first }
        return summaries.first(where: { $0.sessionID == selectedSessionID }) ?? summaries.first
    }

    private var matches: [MatchedActivityCandidate] {
        guard let anchor else { return [] }
        let activity = effectiveActivity(anchor)
        return summaries
            .filter { $0.sessionID != anchor.sessionID && effectiveActivity($0) == activity }
            .compactMap { candidate -> MatchedActivityCandidate? in
                let score = similarity(anchor: anchor, candidate: candidate)
                guard score >= 0.55 else { return nil }
                return MatchedActivityCandidate(summary: candidate, similarity: score)
            }
            .sorted {
                if abs($0.similarity - $1.similarity) > 0.001 {
                    return $0.similarity > $1.similarity
                }
                return $0.summary.startedAt > $1.summary.startedAt
            }
            .prefix(8)
            .map { $0 }
    }

    private var anchorMenu: some View {
        Menu {
            ForEach(summaries.prefix(30)) { summary in
                Button {
                    selectedSessionID = summary.sessionID
                } label: {
                    Label(
                        "\(effectiveKind(summary)?.label ?? effectiveActivity(summary)) · \(summary.startedAt.formatted(date: .abbreviated, time: .omitted))",
                        systemImage: effectiveKind(summary)?.symbol ?? "figure.mixed.cardio"
                    )
                }
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.circle")
        }
        .accessibilityLabel("Choisir la séance de référence")
    }

    private func anchorCard(_ anchor: TrackerSummary) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SÉANCE DE RÉFÉRENCE")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.mint)
                    Text(effectiveKind(anchor)?.label ?? effectiveActivity(anchor))
                        .font(.title2.weight(.black))
                    Text(anchor.startedAt, format: .dateTime.weekday(.wide).day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: effectiveKind(anchor)?.symbol ?? "figure.mixed.cardio")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 50, height: 50)
                    .background(.mint.opacity(0.12), in: Circle())
            }

            HStack(spacing: 10) {
                matchMetric(matchDistance(anchor.distanceMeters), "DISTANCE")
                matchMetric(matchDuration(anchor.duration), "TEMPS")
                matchMetric(primaryPaceOrSpeed(anchor), primaryPaceLabel(anchor))
            }
        }
        .matchPanel()
    }

    private func matchQualityCard(_ anchor: TrackerSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("MATCHING TRANSPARENT", systemImage: "scope")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.cyan)
                Spacer()
                Text("\(matches.count) match(s)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(matchRuleDescription(anchor))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Le score sert seulement à trouver des séances comparables. Il n’entre dans aucun score de santé, d’effort ou de récupération.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .matchPanel()
    }

    private func comparisonChart(
        _ anchor: TrackerSummary
    ) -> some View {
        let ordered =
            Array(matches.reversed())
            + [
                MatchedActivityCandidate(
                    summary: anchor,
                    similarity: 1
                )
            ]

        let selected = selectedChartDate.flatMap { date in
            ordered.min {
                abs(
                    $0.summary.startedAt
                        .timeIntervalSince(date)
                )
                <
                abs(
                    $1.summary.startedAt
                        .timeIntervalSince(date)
                )
            }
        }

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ÉVOLUTION")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)

                    Text(chartTitle(anchor))
                        .font(.headline.weight(.bold))
                }

                Spacer()

                Text("touche / glisse")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Chart(ordered) { item in
                LineMark(
                    x: .value(
                        "Date",
                        item.summary.startedAt
                    ),
                    y: .value(
                        chartTitle(anchor),
                        chartMetric(item.summary)
                    )
                )
                .foregroundStyle(
                    .cyan.opacity(0.55)
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
                        "Date",
                        item.summary.startedAt
                    ),
                    y: .value(
                        chartTitle(anchor),
                        chartMetric(item.summary)
                    )
                )
                .foregroundStyle(
                    item.summary.sessionID
                        == anchor.sessionID
                        ? Color.mint
                        : Color.cyan
                )
                .symbolSize(
                    item.summary.sessionID
                        == selected?.summary.sessionID
                        ? 95
                        : item.summary.sessionID
                            == anchor.sessionID
                            ? 72
                            : 42
                )

                if
                    item.summary.sessionID
                        == selected?.summary.sessionID
                {
                    RuleMark(
                        x: .value(
                            "Sélection",
                            item.summary.startedAt
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.45)
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
                                item.summary.startedAt
                                    .formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                            )
                            .font(
                                .caption2.weight(.black)
                            )

                            Text(
                                primaryPaceOrSpeed(
                                    item.summary
                                )
                            )
                            .font(
                                .caption.weight(.black)
                            )
                            .foregroundStyle(
                                item.summary.sessionID
                                    == anchor.sessionID
                                    ? Color.mint
                                    : Color.cyan
                            )
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
            .chartXSelection(
                value: $selectedChartDate
            )
            .frame(height: 190)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                        .foregroundStyle(
                            .white.opacity(0.06)
                        )
                    AxisValueLabel()
                }
            }
        }
        .matchPanel()
    }

    private func matchStack(
        _ anchor: TrackerSummary
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MATCHS")
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

            TabView {
                ForEach(matches) { match in
                    matchCard(
                        anchor: anchor,
                        match: match
                    )
                    .padding(.horizontal, 1)
                }
            }
            .frame(height: 405)
            .tabViewStyle(
                .page(indexDisplayMode: .automatic)
            )
        }
    }

    private func matchCard(anchor: TrackerSummary, match: MatchedActivityCandidate) -> some View {
        let candidate = match.summary
        let anchorEffort = effortEstimator.estimate(summary: anchor).score
        let candidateEffort = effortEstimator.estimate(summary: candidate).score

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.startedAt, format: .dateTime.weekday(.abbreviated).day().month().year())
                        .font(.headline.weight(.bold))
                    Text("Similarité \(Int((match.similarity * 100).rounded()))%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(similarityAccent(match.similarity))
                }
                Spacer()
                Text(deltaHeadline(anchor: anchor, candidate: candidate))
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(deltaAccent(anchor: anchor, candidate: candidate))
                    .multilineTextAlignment(.trailing)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                deltaMetric(
                    title: primaryPaceLabel(anchor),
                    current: primaryPaceOrSpeed(candidate),
                    delta: paceDeltaText(anchor: anchor, candidate: candidate),
                    symbol: "speedometer",
                    accent: .cyan
                )
                deltaMetric(
                    title: "FC moy.",
                    current: candidate.averageHeartRate > 0 ? String(format: "%.0f bpm", candidate.averageHeartRate) : "—",
                    delta: numericDelta(candidate.averageHeartRate, anchor.averageHeartRate, unit: " bpm", digits: 0),
                    symbol: "heart.fill",
                    accent: .pink
                )
                deltaMetric(
                    title: "Effort Tracker",
                    current: String(format: "%.1f / 10", candidateEffort),
                    delta: String(format: "%+.1f", candidateEffort - anchorEffort),
                    symbol: "scope",
                    accent: .orange
                )
                deltaMetric(
                    title: "D+",
                    current: String(format: "%.0f m", candidate.elevationGainMeters),
                    delta: numericDelta(candidate.elevationGainMeters, anchor.elevationGainMeters, unit: " m", digits: 0),
                    symbol: "mountain.2.fill",
                    accent: .mint
                )
                deltaMetric(
                    title: "Énergie",
                    current: candidate.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—",
                    delta: optionalDelta(candidate.activeEnergyKcal, anchor.activeEnergyKcal, unit: " kcal"),
                    symbol: "flame.fill",
                    accent: .orange
                )
                deltaMetric(
                    title: "Cadence",
                    current: candidate.averageCadenceSPM.map { String(format: "%.0f/min", $0) } ?? "—",
                    delta: optionalDelta(candidate.averageCadenceSPM, anchor.averageCadenceSPM, unit: "/min"),
                    symbol: "metronome.fill",
                    accent: .purple
                )
            }

            if let weather = weatherContext(candidate) {
                Label(weather, systemImage: "cloud.sun.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .matchPanel()
    }

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Lire la comparaison", systemImage: "checkmark.shield.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.mint)
            Text("Une séance plus rapide n’est pas automatiquement “meilleure” : fréquence cardiaque, effort, relief, météo et objectif changent le contexte. Tracker montre donc les dimensions séparément plutôt qu’un classement global.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Le matching actuel utilise les séances Tracker locales. Une future version pourra ajouter un fingerprint de parcours lorsque le matching de route sera suffisamment fiable.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .matchPanel()
    }

    private func refresh() {
        summaries = store.listSummaries().sorted { $0.startedAt > $1.startedAt }
        if selectedSessionID == nil { selectedSessionID = summaries.first?.sessionID }
    }

    private func effectiveActivity(_ summary: TrackerSummary) -> String {
        reviewStore.effectiveActivity(for: summary)
    }

    private func effectiveKind(_ summary: TrackerSummary) -> ActivityKind? {
        ActivityKind(rawValue: effectiveActivity(summary))
    }

    private func similarity(anchor: TrackerSummary, candidate: TrackerSummary) -> Double {
        let durationError = relativeError(anchor.duration, candidate.duration)
        let hasUsefulDistance = anchor.distanceMeters >= 500 && candidate.distanceMeters >= 500

        if hasUsefulDistance {
            let distanceError = relativeError(anchor.distanceMeters, candidate.distanceMeters)
            guard distanceError <= 0.45, durationError <= 0.60 else { return 0 }
            let elevationError = normalizedElevationError(anchor, candidate)
            return clamp01(1 - (distanceError * 0.58 + durationError * 0.30 + elevationError * 0.12))
        }

        guard durationError <= 0.45 else { return 0 }
        let heartError: Double
        if anchor.averageHeartRate > 0, candidate.averageHeartRate > 0 {
            heartError = min(1, abs(anchor.averageHeartRate - candidate.averageHeartRate) / 40)
        } else {
            heartError = 0.25
        }
        return clamp01(1 - (durationError * 0.82 + heartError * 0.18))
    }

    private func relativeError(_ lhs: Double, _ rhs: Double) -> Double {
        let denominator = max(abs(lhs), abs(rhs), 1)
        return abs(lhs - rhs) / denominator
    }

    private func normalizedElevationError(_ lhs: TrackerSummary, _ rhs: TrackerSummary) -> Double {
        let a = lhs.elevationGainMeters
        let b = rhs.elevationGainMeters
        if max(a, b) < 20 { return 0 }
        return min(1, relativeError(a, b))
    }

    private func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    private func matchRuleDescription(_ anchor: TrackerSummary) -> String {
        if anchor.distanceMeters >= 500 {
            return "Même sport · distance proche prioritaire · durée proche · relief utilisé comme nuance. Seuil minimal : 55% de similarité."
        }
        return "Même sport · durée proche prioritaire · fréquence cardiaque utilisée seulement comme nuance lorsque disponible. Seuil minimal : 55%."
    }

    private func chartTitle(_ summary: TrackerSummary) -> String {
        summary.distanceMeters >= 500 ? "Allure / vitesse" : "Effort Tracker"
    }

    private func chartMetric(_ summary: TrackerSummary) -> Double {
        if summary.distanceMeters >= 500 {
            let kind = effectiveKind(summary)
            if kind == .running || kind == .walking || kind == .hiking || kind == .trackAndField {
                return paceMinutesPerKM(summary) ?? 0
            }
            return averageSpeedKPH(summary)
        }
        return effortEstimator.estimate(summary: summary).score
    }

    private func primaryPaceOrSpeed(_ summary: TrackerSummary) -> String {
        guard summary.distanceMeters >= 500 else {
            return String(format: "%.1f /10", effortEstimator.estimate(summary: summary).score)
        }
        let kind = effectiveKind(summary)
        if kind == .running || kind == .walking || kind == .hiking || kind == .trackAndField {
            guard let pace = paceMinutesPerKM(summary) else { return "—" }
            let minutes = Int(pace)
            let seconds = Int(((pace - Double(minutes)) * 60).rounded())
            return String(format: "%d:%02d /km", minutes, min(seconds, 59))
        }
        return String(format: "%.1f km/h", averageSpeedKPH(summary))
    }

    private func primaryPaceLabel(_ summary: TrackerSummary) -> String {
        guard summary.distanceMeters >= 500 else { return "EFFORT" }
        let kind = effectiveKind(summary)
        return (kind == .running || kind == .walking || kind == .hiking || kind == .trackAndField) ? "ALLURE" : "VITESSE"
    }

    private func paceMinutesPerKM(_ summary: TrackerSummary) -> Double? {
        guard summary.distanceMeters >= 100, summary.duration > 0 else { return nil }
        return summary.duration / 60 / (summary.distanceMeters / 1000)
    }

    private func averageSpeedKPH(_ summary: TrackerSummary) -> Double {
        guard summary.duration > 0 else { return 0 }
        return summary.distanceMeters / summary.duration * 3.6
    }

    private func deltaHeadline(anchor: TrackerSummary, candidate: TrackerSummary) -> String {
        guard anchor.distanceMeters >= 500, candidate.distanceMeters >= 500 else {
            let delta = effortEstimator.estimate(summary: candidate).score - effortEstimator.estimate(summary: anchor).score
            return String(format: "effort %+.1f", delta)
        }

        let kind = effectiveKind(anchor)
        if kind == .running || kind == .walking || kind == .hiking || kind == .trackAndField,
           let anchorPace = paceMinutesPerKM(anchor), let candidatePace = paceMinutesPerKM(candidate) {
            let deltaSeconds = (candidatePace - anchorPace) * 60
            if abs(deltaSeconds) < 1 { return "allure ≈" }
            return String(format: "%+.0fs/km", deltaSeconds)
        }

        return String(format: "%+.1f km/h", averageSpeedKPH(candidate) - averageSpeedKPH(anchor))
    }

    private func deltaAccent(anchor: TrackerSummary, candidate: TrackerSummary) -> Color {
        guard anchor.distanceMeters >= 500, candidate.distanceMeters >= 500 else { return .orange }
        let kind = effectiveKind(anchor)
        if kind == .running || kind == .walking || kind == .hiking || kind == .trackAndField,
           let anchorPace = paceMinutesPerKM(anchor), let candidatePace = paceMinutesPerKM(candidate) {
            return candidatePace <= anchorPace ? .mint : .orange
        }
        return averageSpeedKPH(candidate) >= averageSpeedKPH(anchor) ? .mint : .orange
    }

    private func paceDeltaText(anchor: TrackerSummary, candidate: TrackerSummary) -> String {
        deltaHeadline(anchor: anchor, candidate: candidate)
    }

    private func numericDelta(_ current: Double, _ reference: Double, unit: String, digits: Int) -> String {
        guard current.isFinite, reference.isFinite, current > 0, reference > 0 else { return "—" }
        return String(format: "%+.*f%@", digits, current - reference, unit)
    }

    private func optionalDelta(_ current: Double?, _ reference: Double?, unit: String) -> String {
        guard let current, let reference else { return "—" }
        return String(format: "%+.0f%@", current - reference, unit)
    }

    private func weatherContext(_ summary: TrackerSummary) -> String? {
        guard let snapshots = summary.weatherSnapshots, !snapshots.isEmpty else { return nil }
        let temperatures = snapshots.compactMap(\.temperatureC)
        let winds = snapshots.compactMap(\.windSpeedKPH)
        var parts: [String] = []
        if !temperatures.isEmpty {
            parts.append(String(format: "%.1f°C", temperatures.reduce(0, +) / Double(temperatures.count)))
        }
        if !winds.isEmpty {
            parts.append(String(format: "vent %.0f km/h", winds.reduce(0, +) / Double(winds.count)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func matchMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func deltaMetric(title: String, current: String, delta: String, symbol: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol).foregroundStyle(accent)
                Spacer()
                Text(delta)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(current)
                .font(.subheadline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(title.uppercased())
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(9)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func similarityAccent(_ similarity: Double) -> Color {
        similarity >= 0.82 ? .mint : (similarity >= 0.68 ? .cyan : .orange)
    }
}

private struct MatchedActivityCandidate: Identifiable {
    let summary: TrackerSummary
    let similarity: Double
    var id: String { summary.sessionID }
}

private extension View {
    func matchPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func matchDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : "\(minutes) min"
}

private func matchDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}
