import Charts
import SwiftUI

struct TrackerCorrelationPoint: Identifiable, Equatable {
    let date: Date
    let x: Double
    let y: Double
    var id: String { "\(date.timeIntervalSince1970)-\(x)-\(y)" }
}

struct TrackerCorrelationInsight: Identifiable, Equatable {
    let id: String
    let title: String
    let xLabel: String
    let yLabel: String
    let xUnit: String
    let yUnit: String
    let points: [TrackerCorrelationPoint]
    let correlation: Double?
    let minimumSamples: Int
    let note: String
    let symbol: String

    var isReady: Bool { points.count >= minimumSamples && correlation != nil }
}

struct TrackerCorrelationSnapshot: Equatable {
    let insights: [TrackerCorrelationInsight]
    let windowDays: Int
    let generatedAt: Date
}

final class TrackerCorrelationReader {
    private let historyReader = TrackerCorrelationHistoryReader()

    func load(days: Int, completion: @escaping (TrackerCorrelationSnapshot) -> Void) {
        let boundedDays = min(90, max(30, days))
        historyReader.load(days: boundedDays) { history in
            completion(
                TrackerCorrelationSnapshot(
                    insights: Self.makeInsights(history: history),
                    windowDays: boundedDays,
                    generatedAt: Date()
                )
            )
        }
    }

    private static func makeInsights(history: TrackerCorrelationHistorySnapshot) -> [TrackerCorrelationInsight] {
        [
            TrackerCorrelationInsight(
                id: "sleep_hrv",
                title: "Sommeil ↔ VFC",
                xLabel: "Sommeil",
                yLabel: "VFC lendemain",
                xUnit: "h",
                yUnit: "ms",
                points: history.sleepHRVPoints,
                correlation: pearson(history.sleepHRVPoints),
                minimumSamples: 10,
                note: "Associe la durée de chaque nuit à la VFC Apple Health du jour où la nuit se termine.",
                symbol: "waveform.path.ecg"
            ),
            TrackerCorrelationInsight(
                id: "sleep_rhr",
                title: "Sommeil ↔ FC repos",
                xLabel: "Sommeil",
                yLabel: "FC repos lendemain",
                xUnit: "h",
                yUnit: "bpm",
                points: history.sleepRestingHeartRatePoints,
                correlation: pearson(history.sleepRestingHeartRatePoints),
                minimumSamples: 10,
                note: "Compare la durée de sommeil à la FC au repos lisible le jour suivant.",
                symbol: "heart.fill"
            ),
            TrackerCorrelationInsight(
                id: "training_sleep",
                title: "Entraînement ↔ Sommeil",
                xLabel: "Minutes veille",
                yLabel: "Sommeil nuit suivante",
                xUnit: "min",
                yUnit: "h",
                points: history.trainingSleepPoints,
                correlation: pearson(history.trainingSleepPoints),
                minimumSamples: 10,
                note: "Compare le volume d’entraînement du jour civil précédent à la durée de la nuit suivante.",
                symbol: "figure.run"
            ),
        ]
    }

    private static func pearson(_ points: [TrackerCorrelationPoint]) -> Double? {
        guard points.count >= 3 else { return nil }
        let n = Double(points.count)
        let meanX = points.reduce(0) { $0 + $1.x } / n
        let meanY = points.reduce(0) { $0 + $1.y } / n
        let numerator = points.reduce(0.0) { partial, point in
            partial + (point.x - meanX) * (point.y - meanY)
        }
        let sumX = points.reduce(0.0) { $0 + pow($1.x - meanX, 2) }
        let sumY = points.reduce(0.0) { $0 + pow($1.y - meanY, 2) }
        let denominator = sqrt(sumX * sumY)
        guard denominator > 0 else { return nil }
        let value = numerator / denominator
        return value.isFinite ? min(1, max(-1, value)) : nil
    }
}

struct TrackerCorrelationLabEntryCard: View {
    var body: some View {
        NavigationLink {
            TrackerCorrelationLabView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .frame(width: 48, height: 48)
                    .background(.cyan.opacity(0.13), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("CORRELATION · LAB")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                    Text("Découvrir tes associations personnelles")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("30 / 60 / 90 j · min 10 paires · n et r visibles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private enum TrackerCorrelationPeriod: Int, CaseIterable, Identifiable {
    case days30 = 30
    case days60 = 60
    case days90 = 90

    var id: Int { rawValue }
    var label: String { "\(rawValue) j" }
}

struct TrackerCorrelationLabView: View {
    @State private var snapshot: TrackerCorrelationSnapshot?
    @State private var loading = true
    @State private var period: TrackerCorrelationPeriod = .days30
    @State private var insightPage = "sleep_hrv"
    @State private var selectedCorrelationX: Double?

    private let reader = TrackerCorrelationReader()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                intro
                periodPicker

                if let snapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("ANALYSES")
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

                        TabView(selection: $insightPage) {
                            ForEach(snapshot.insights) { insight in
                                correlationCard(insight)
                                    .tag(insight.id)
                                    .padding(.horizontal, 1)
                            }
                        }
                        .frame(height: 370)
                        .tabViewStyle(
                            .page(indexDisplayMode: .automatic)
                        )
                        .onChange(of: insightPage) { _, _ in
                            selectedCorrelationX = nil
                        }
                    }
                } else if loading {
                    ProgressView("Croisement des données personnelles…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }

                methodology
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.cyan.opacity(0.10), .purple.opacity(0.05), .black],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Correlation · Lab")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { refresh() }
        .task { refresh() }
        .onChange(of: period) { _, _ in refresh() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Associations personnelles", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.title3.weight(.black))
                .foregroundStyle(.cyan)
            Text("Tracker croise uniquement les données Apple Health accessibles à l’app et n’affiche une interprétation qu’après un minimum de paires. Une corrélation décrit une association : elle ne prouve pas qu’un facteur cause l’autre.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .correlationPanel()
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FENÊTRE D’ANALYSE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                if loading {
                    ProgressView().controlSize(.mini)
                }
            }
            Picker("Fenêtre d’analyse", selection: $period) {
                ForEach(TrackerCorrelationPeriod.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Text("La fenêtre change les paires réellement analysées et recalcule r ; elle ne dilue pas un résultat 30 jours dans un historique plus long.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .correlationPanel()
    }

    private func correlationCard(_ insight: TrackerCorrelationInsight) -> some View {
        let selected = selectedCorrelationX.flatMap { x in
            insight.points.min {
                abs($0.x - x) < abs($1.x - x)
            }
        }

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Image(systemName: insight.symbol)
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(.headline.weight(.bold))
                    Text("n = \(insight.points.count) / min \(insight.minimumSamples)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if insight.isReady, let r = insight.correlation {
                    Text(String(format: "r %.2f", r))
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(correlationAccent(r))
                } else {
                    Text("EN COURS")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.orange)
                }
            }

            if insight.points.count >= 3 {
                Chart(insight.points) { point in
                    PointMark(
                        x: .value(
                            insight.xLabel,
                            point.x
                        ),
                        y: .value(
                            insight.yLabel,
                            point.y
                        )
                    )
                    .foregroundStyle(
                        insight.isReady
                            ? Color.cyan
                            : Color.secondary
                    )
                    .symbolSize(
                        point.id == selected?.id
                            ? 90
                            : 48
                    )

                    if point.id == selected?.id {
                        RuleMark(
                            x: .value(
                                "Sélection",
                                point.x
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
                                Text(
                                    point.date.formatted(
                                        date: .abbreviated,
                                        time: .omitted
                                    )
                                )
                                .font(
                                    .caption2.weight(.black)
                                )

                                Text(
                                    String(
                                        format: "%.1f %@",
                                        point.x,
                                        insight.xUnit
                                    )
                                )
                                .font(
                                    .caption.weight(.bold)
                                )

                                Text(
                                    String(
                                        format: "%.1f %@",
                                        point.y,
                                        insight.yUnit
                                    )
                                )
                                .font(
                                    .caption.weight(.black)
                                )
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
                .chartXSelection(
                    value: $selectedCorrelationX
                )
                .frame(height: 175)
                .chartXAxisLabel(insight.xUnit)
                .chartYAxisLabel(insight.yUnit)
            }

            if insight.isReady, let r = insight.correlation {
                Text(correlationDescription(r))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(correlationAccent(r))
            } else {
                ProgressView(
                    value: Double(min(insight.points.count, insight.minimumSamples)),
                    total: Double(insight.minimumSamples)
                )
                .tint(.cyan)
                Text("Encore \(max(0, insight.minimumSamples - insight.points.count)) paire(s) avant d’interpréter cette relation.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(insight.note)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .correlationPanel()
    }

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Garde-fous", systemImage: "checkmark.shield.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.mint)
            Text("Le coefficient r mesure une association linéaire de -1 à +1. Tracker affiche le nombre de paires et exige au moins 10 observations avant de qualifier la relation. Aucun résultat n’est présenté comme une preuve de causalité, un diagnostic ou une recommandation médicale.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Les fenêtres 30 / 60 / 90 jours relisent directement sommeil, VFC, FC au repos et historique d’entraînement disponibles dans Apple Health. Les doublons de sommeil multi-sources sont réduits en conservant, pour une nuit donnée, la source offrant la nuit la mieux documentée.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func refresh() {
        loading = true
        reader.load(days: period.rawValue) { value in
            snapshot = value
            loading = false
        }
    }

    private func correlationDescription(_ value: Double) -> String {
        let magnitude = abs(value)
        let strength: String
        switch magnitude {
        case ..<0.20: strength = "Association très faible"
        case ..<0.40: strength = "Association faible"
        case ..<0.60: strength = "Association modérée"
        case ..<0.80: strength = "Association marquée"
        default: strength = "Association forte"
        }
        if magnitude < 0.20 { return strength }
        return "\(strength) · direction \(value > 0 ? "positive" : "inverse")"
    }

    private func correlationAccent(_ value: Double) -> Color {
        let magnitude = abs(value)
        if magnitude < 0.20 { return .secondary }
        if magnitude < 0.60 { return .cyan }
        return .mint
    }
}

private extension View {
    func correlationPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}
