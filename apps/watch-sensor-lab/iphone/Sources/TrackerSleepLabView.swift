import Charts
import SwiftUI

struct TrackerSleepLabEntryCard: View {
    var body: some View {
        NavigationLink {
            TrackerSleepLabView()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "bed.double.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 48, height: 48)
                    .background(.indigo.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("SOMMEIL · LAB")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.indigo)
                    Text("Comprendre la nuit, pas seulement la noter")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Repère personnel · régularité · continuité · dette · phases")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(15)
            .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct TrackerSleepLabView: View {
    @State private var snapshot: TrackerRecoverySnapshot?
    @State private var loading = true
    @State private var selectedSleepDate: Date?

    private let reader = TrackerRecoveryIntelligenceReader()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let snapshot, let night = snapshot.currentSleep {
                    hero(snapshot: snapshot, night: night)
                    contextGrid(snapshot: snapshot, night: night)
                    stageCard(night: night)
                    trendCard(snapshot: snapshot, currentNight: night)
                    TrackerNightVitalsCard()
                    interpretationCard(snapshot: snapshot)
                } else if loading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Analyse des nuits Apple Health…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ContentUnavailableView(
                        "Sommeil insuffisamment documenté",
                        systemImage: "bed.double",
                        description: Text("Porte l’Apple Watch la nuit et autorise les données Sommeil pour construire tes repères personnels.")
                    )
                    .frame(minHeight: 280)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.14), .purple.opacity(0.06), .black],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Sommeil · Lab")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { refresh() }
        .task { refresh() }
    }

    private func hero(snapshot: TrackerRecoverySnapshot, night: TrackerSleepNight) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DERNIÈRE NUIT")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.indigo)
                    Text(sleepDuration(night.totalSleep))
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("\(night.startedAt.formatted(date: .omitted, time: .shortened)) → \(night.endedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .frame(width: 56, height: 56)
                    .background(.indigo.opacity(0.14), in: Circle())
            }

            if let baseline = snapshot.sleepBaselineHours {
                let current = night.totalSleep / 3600
                let delta = current - baseline
                HStack {
                    Label(
                        String(format: "%+.1fh vs ton repère", delta),
                        systemImage: delta >= -0.25 ? "equal.circle.fill" : "arrow.down.circle.fill"
                    )
                    .font(.caption.weight(.bold))
                    .foregroundStyle(abs(delta) <= 0.5 ? Color.mint : Color.orange)
                    Spacer()
                    Text(String(format: "repère %.1fh", baseline))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sleepPanel()
    }

    private func contextGrid(
        snapshot: TrackerRecoverySnapshot,
        night: TrackerSleepNight
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("REPÈRES DE NUIT")
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
                sleepContextCell(
                    "CONTINUITÉ",
                    "\(Int((night.efficiency * 100).rounded()))%",
                    "temps endormi / fenêtre",
                    "arrow.triangle.2.circlepath",
                    .cyan
                )

                sleepContextCell(
                    "RÉVEILS",
                    "\(night.interruptions)",
                    night.interruptions == 1
                        ? "interruption ≥ 2 min"
                        : "interruptions ≥ 2 min",
                    "eye.fill",
                    .orange
                )

                sleepContextCell(
                    "RÉGULARITÉ",
                    snapshot.sleepConsistencyMinutes.map {
                        "±\(Int($0.rounded())) min"
                    } ?? "—",
                    "écart au coucher habituel",
                    "clock.fill",
                    .mint
                )

                sleepContextCell(
                    "ÉCART 7 J",
                    snapshot.sleepDeficit7DaysHours.map {
                        $0 > 0.05
                            ? String(
                                format: "-%.1fh",
                                $0
                            )
                            : "0h"
                    } ?? "—",
                    "cumul vs repère personnel",
                    "calendar.badge.clock",
                    .purple
                )
            }
            .frame(height: 122)
            .tabViewStyle(
                .page(indexDisplayMode: .automatic)
            )
        }
        .sleepPanel()
    }

    private func stageCard(night: TrackerSleepNight) -> some View {
        let staged = night.core + night.deep + night.rem
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PHASES")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("Répartition de la nuit")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Text(night.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if staged > 0 {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.cyan.opacity(0.78))
                            .frame(width: proxy.size.width * night.core / staged)
                        Rectangle()
                            .fill(Color.indigo)
                            .frame(width: proxy.size.width * night.deep / staged)
                        Rectangle()
                            .fill(Color.purple)
                            .frame(width: proxy.size.width * night.rem / staged)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 15)

                HStack(spacing: 8) {
                    stageValue("Core", night.core, .cyan)
                    stageValue("Profond", night.deep, .indigo)
                    stageValue("REM", night.rem, .purple)
                }
            } else {
                Text("Les phases détaillées ne sont pas disponibles pour cette nuit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Les phases sont affichées comme contexte Apple Health. Tracker ne les transforme pas en diagnostic ni en objectif universel de pourcentage.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .sleepPanel()
    }

    private func trendCard(snapshot: TrackerRecoverySnapshot, currentNight: TrackerSleepNight) -> some View {
        let selected = selectedSleepDate.flatMap { date in
            snapshot.sleepTrend.min {
                abs(
                    $0.endedAt.timeIntervalSince(date)
                )
                <
                abs(
                    $1.endedAt.timeIntervalSince(date)
                )
            }
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("14 NUITS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text("Durée vs ton propre repère")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Text("\(snapshot.sleepTrend.count) nuits")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }

            Chart(snapshot.sleepTrend) { item in
                BarMark(
                    x: .value(
                        "Nuit",
                        item.endedAt,
                        unit: .day
                    ),
                    y: .value(
                        "Heures",
                        item.totalSleep / 3600
                    )
                )
                .foregroundStyle(
                    item.id == currentNight.id
                        ? Color.cyan
                        : Color.indigo.opacity(0.55)
                )
                .cornerRadius(3)

                if item.id == selected?.id {
                    RuleMark(
                        x: .value(
                            "Sélection",
                            item.endedAt
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
                        spacing: 5,
                        overflowResolution: AnnotationOverflowResolution(
                            x: .fit(to: .chart),
                            y: .fit(to: .chart)
                        )
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Text(
                                item.endedAt.formatted(
                                    date: .abbreviated,
                                    time: .omitted
                                )
                            )
                            .font(
                                .caption2.weight(.black)
                            )

                            Text(
                                sleepDuration(
                                    item.totalSleep
                                )
                            )
                            .font(
                                .caption.weight(.black)
                            )
                            .foregroundStyle(.cyan)
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

                if let baseline = snapshot.sleepBaselineHours {
                    RuleMark(
                        y: .value(
                            "Repère",
                            baseline
                        )
                    )
                    .foregroundStyle(
                        .white.opacity(0.38)
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
                value: $selectedSleepDate
            )
            .frame(height: 185)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    AxisValueLabel()
                }
            }
        }
        .sleepPanel()
    }

    private func interpretationCard(snapshot: TrackerRecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pourquoi pas un deuxième Sleep Score ?", systemImage: "checkmark.shield.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.mint)
            Text("Apple fournit désormais son propre score de sommeil. Tracker garde donc ici les dimensions séparées : durée vs repère personnel, régularité, continuité, phases, Vitals Nuit et écart cumulé. L’Indice Tracker global reste une vue de récupération multi-signal, pas une copie du score Sommeil Apple.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Confiance récupération actuelle : \(Int(snapshot.confidence.rounded()))%")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.cyan)
        }
        .padding(15)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sleepContextCell(
        _ title: String,
        _ value: String,
        _ detail: String,
        _ symbol: String,
        _ accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(accent)
            Text(title)
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(11)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stageValue(_ label: String, _ seconds: TimeInterval, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(sleepDuration(seconds))
                .font(.subheadline.weight(.black))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }
}

private extension View {
    func sleepPanel() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func sleepDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}
