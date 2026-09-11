import SwiftUI

struct TrackerDailyBriefItem: Identifiable, Equatable {
    enum Tone: String {
        case favorable
        case neutral
        case attention
        case building
    }

    let id: String
    let title: String
    let value: String
    let explanation: String
    let source: String
    let symbol: String
    let tone: Tone
}

struct TrackerDailyBriefSnapshot: Equatable {
    let headline: String
    let summary: String
    let confidence: Double
    let items: [TrackerDailyBriefItem]
    let generatedAt: Date
}

final class TrackerDailyBriefReader {
    private let recoveryReader = TrackerRecoveryIntelligenceReader()
    private let healthReader = HealthProgressionReader()

    func load(completion: @escaping (TrackerDailyBriefSnapshot) -> Void) {
        let group = DispatchGroup()
        var recovery: TrackerRecoverySnapshot?
        var health = HealthProgressionData.empty

        group.enter()
        recoveryReader.load { value in
            recovery = value
            group.leave()
        }

        group.enter()
        healthReader.load { value in
            health = value
            group.leave()
        }

        group.notify(queue: .main) {
            completion(Self.makeSnapshot(recovery: recovery, health: health))
        }
    }

    private static func makeSnapshot(
        recovery: TrackerRecoverySnapshot?,
        health: HealthProgressionData
    ) -> TrackerDailyBriefSnapshot {
        var items: [TrackerDailyBriefItem] = []

        if let recovery {
            let recoveryTone: TrackerDailyBriefItem.Tone
            if let score = recovery.score, recovery.confidence >= 25 {
                recoveryTone = score >= 70 ? .favorable : (score >= 55 ? .neutral : .attention)
            } else {
                recoveryTone = .building
            }
            items.append(
                TrackerDailyBriefItem(
                    id: "recovery",
                    title: "Récupération",
                    value: recovery.score.map { "\(Int($0.rounded())) / 100" } ?? "Repères en cours",
                    explanation: recovery.label,
                    source: "Indice Tracker · Apple Health",
                    symbol: "sparkles",
                    tone: recoveryTone
                )
            )

            if let night = recovery.currentSleep {
                let baseline = recovery.sleepBaselineHours
                let currentHours = night.totalSleep / 3600
                let delta = baseline.map { currentHours - $0 }
                let detail: String
                if let delta {
                    detail = String(format: "%+.1fh vs ton repère · continuité %.0f%%", delta, night.efficiency * 100)
                } else {
                    detail = String(format: "Continuité %.0f%% · repère en construction", night.efficiency * 100)
                }
                let tone: TrackerDailyBriefItem.Tone
                if let delta, delta < -1.0 { tone = .attention }
                else if night.efficiency >= 0.88 { tone = .favorable }
                else { tone = .neutral }

                items.append(
                    TrackerDailyBriefItem(
                        id: "sleep",
                        title: "Dernière nuit",
                        value: briefDuration(night.totalSleep),
                        explanation: detail,
                        source: night.source,
                        symbol: "bed.double.fill",
                        tone: tone
                    )
                )
            }

            if let ratio = recovery.workloadRatio {
                let tone: TrackerDailyBriefItem.Tone
                switch ratio {
                case ..<0.65: tone = .neutral
                case ..<1.45: tone = .favorable
                default: tone = .attention
                }
                items.append(
                    TrackerDailyBriefItem(
                        id: "load",
                        title: "Volume récent",
                        value: String(format: "%.2fx", ratio),
                        explanation: "7 jours vs moyenne hebdomadaire des 28 jours précédents",
                        source: "Apple Health · contexte de volume",
                        symbol: "chart.bar.fill",
                        tone: tone
                    )
                )
            }
        }

        if let hrv = health.hrvSDNN {
            let delta = health.hrvBaseline.map { hrv.value - $0 }
            let detail = delta.map { String(format: "%+.0f ms vs moyenne récente", $0) } ?? "Moyenne personnelle en construction"
            items.append(
                TrackerDailyBriefItem(
                    id: "hrv",
                    title: "VFC",
                    value: String(format: "%.0f ms", hrv.value),
                    explanation: detail,
                    source: hrv.source,
                    symbol: "waveform.path.ecg",
                    tone: baselineTone(current: hrv.value, baseline: health.hrvBaseline, higherIsGenerallyFavorable: true)
                )
            )
        }

        if let resting = health.restingHeartRate {
            let delta = health.restingHeartRateBaseline.map { resting.value - $0 }
            let detail = delta.map { String(format: "%+.0f bpm vs moyenne récente", $0) } ?? "Moyenne personnelle en construction"
            items.append(
                TrackerDailyBriefItem(
                    id: "resting_hr",
                    title: "FC au repos",
                    value: String(format: "%.0f bpm", resting.value),
                    explanation: detail,
                    source: resting.source,
                    symbol: "heart.fill",
                    tone: baselineTone(current: resting.value, baseline: health.restingHeartRateBaseline, higherIsGenerallyFavorable: false)
                )
            )
        }

        let selected = Array(items.prefix(5))
        let confidence = recovery?.confidence ?? 0
        let headline: String
        let summary: String

        if selected.isEmpty {
            headline = "Repères en construction"
            summary = "Apple Health n’a pas encore fourni assez de signaux lisibles pour un brief personnel fiable."
        } else if let recovery, let score = recovery.score, recovery.confidence >= 25 {
            headline = recovery.label
            if score >= 70 {
                summary = "Tes principaux signaux sont globalement cohérents avec tes repères personnels. Ouvre le brief pour voir les écarts qui expliquent cette lecture."
            } else if score >= 55 {
                summary = "Les signaux sont partagés aujourd’hui. Le détail montre lesquels s’écartent de tes habitudes et lesquels restent stables."
            } else {
                summary = "Plusieurs signaux demandent de l’attention par rapport à tes propres repères. Le détail garde chaque facteur et sa source séparés."
            }
        } else {
            headline = "Brief partiel"
            summary = "Quelques signaux sont disponibles, mais la confiance reste limitée. Tracker évite de compléter les trous avec des valeurs supposées."
        }

        return TrackerDailyBriefSnapshot(
            headline: headline,
            summary: summary,
            confidence: confidence,
            items: selected,
            generatedAt: Date()
        )
    }

    private static func baselineTone(
        current: Double,
        baseline: Double?,
        higherIsGenerallyFavorable: Bool
    ) -> TrackerDailyBriefItem.Tone {
        guard let baseline, baseline > 0 else { return .building }
        let relative = (current - baseline) / baseline
        if abs(relative) < 0.08 { return .neutral }
        let favorable = higherIsGenerallyFavorable ? relative > 0 : relative < 0
        return favorable ? .favorable : .attention
    }
}

struct TrackerDailyBriefCard: View {
    @State private var snapshot: TrackerDailyBriefSnapshot?
    @State private var loading = true

    private let reader = TrackerDailyBriefReader()

    var body: some View {
        NavigationLink {
            TrackerDailyBriefDetailView(snapshot: snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DAILY BRIEF")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.mint)
                        Text(snapshot?.headline ?? (loading ? "Analyse en cours" : "Repères en construction"))
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.mint)
                }

                if let snapshot {
                    Text(snapshot.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)

                    HStack(spacing: 7) {
                        ForEach(snapshot.items.prefix(3)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Image(systemName: item.symbol)
                                    .foregroundStyle(briefAccent(item.tone))
                                Text(item.value)
                                    .font(.caption.weight(.black))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.65)
                                Text(item.title.uppercased())
                                    .font(.system(size: 7, weight: .black))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                            .padding(8)
                            .background(briefAccent(item.tone).opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                    }
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                HStack {
                    Text(snapshot.map { "Confiance \(Int($0.confidence.rounded()))%" } ?? "Confiance en calcul")
                    Spacer()
                    Label("Pourquoi ?", systemImage: "chevron.right")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [.mint.opacity(0.13), .cyan.opacity(0.07), .white.opacity(0.035)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .task { refresh() }
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }
}

struct TrackerDailyBriefDetailView: View {
    let snapshot: TrackerDailyBriefSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(snapshot.headline)
                            .font(.title2.weight(.black))
                        Text(snapshot.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: snapshot.confidence, total: 100)
                            .tint(.mint)
                        Text("Confiance \(Int(snapshot.confidence.rounded()))%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.mint)
                    }
                    .briefPanel()

                    ForEach(snapshot.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: item.symbol)
                                    .foregroundStyle(briefAccent(item.tone))
                                Text(item.title)
                                    .font(.headline.weight(.bold))
                                Spacer()
                                Text(item.value)
                                    .font(.headline.weight(.black))
                                    .monospacedDigit()
                            }
                            Text(item.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Label(item.source, systemImage: "checkmark.shield.fill")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(briefAccent(item.tone).opacity(0.07), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label("Interprétation, pas diagnostic", systemImage: "info.circle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.cyan)
                        Text("Le brief compare des signaux lisibles à tes propres repères récents. Il ne déduit pas une cause à partir d’une simple corrélation et ne remplace pas un avis médical. Une donnée absente reste absente.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .briefPanel()
                } else {
                    ProgressView("Construction du brief…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Daily Brief")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension View {
    func briefPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func briefAccent(_ tone: TrackerDailyBriefItem.Tone) -> Color {
    switch tone {
    case .favorable: return .mint
    case .neutral: return .cyan
    case .attention: return .orange
    case .building: return .secondary
    }
}

private func briefDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}
