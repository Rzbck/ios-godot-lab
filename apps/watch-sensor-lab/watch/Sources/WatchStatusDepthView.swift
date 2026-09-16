import SwiftUI

struct WatchStatusDepthView: View {
    @EnvironmentObject private var model: SensorModel
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        NavigationStack {
            TabView {
                devicePage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(0)
                    .accessibilityLabel("État des appareils")

                healthPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(1)
                    .accessibilityLabel("État Santé et GPS")

                recoveryPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(2)
                    .accessibilityLabel("Récupération et sommeil")

                cardioPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(3)
                    .accessibilityLabel("Cardio et signaux nocturnes")

                loadPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(4)
                    .accessibilityLabel("Charge récente")
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle("État")
        }
    }

    private var devicePage: some View {
        VStack(spacing: 8) {
            HStack {
                Text("APPAREILS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.cyan)
                Spacer()
                Image(systemName: model.phoneReachable ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundStyle(model.phoneReachable ? .mint : .orange)
            }

            StatusHero(
                title: model.phoneReachable ? "iPhone connecté" : "iPhone hors portée",
                detail: model.phoneReachable ? "Synchronisation temps réel disponible" : "La Watch conserve l’autorité de la séance active",
                symbol: model.phoneReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash",
                accent: model.phoneReachable ? .cyan : .orange
            )

            HStack(spacing: 7) {
                statusCell("Watch", "Active", "applewatch", .mint)
                statusCell("Historique", "\(history.activities.count)", "clock.arrow.circlepath", .pink)
            }

            Text("↓ Santé / GPS")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private var healthPage: some View {
        VStack(spacing: 8) {
            HStack {
                Text("CAPTEURS")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.pink)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 7) {
                statusCell(
                    "Santé",
                    model.healthAuthorized ? "OK" : "Accès",
                    "heart.fill",
                    model.healthAuthorized ? .pink : .orange
                )
                statusCell(
                    "GPS",
                    gpsLabel,
                    "location.fill",
                    model.horizontalAccuracy >= 0 ? .mint : .orange
                )
            }

            if model.horizontalAccuracy >= 0 {
                StatusHero(
                    title: "GPS ±\(Int(model.horizontalAccuracy.rounded())) m",
                    detail: gpsQualityText,
                    symbol: "location.circle.fill",
                    accent: gpsAccent
                )
            } else {
                StatusHero(
                    title: "GPS en attente",
                    detail: "La précision apparaît dès qu’une position exploitable est disponible.",
                    symbol: "location.magnifyingglass",
                    accent: .orange
                )
            }

            Text("↓ Récupération")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var recoveryPage: some View {
        if let wellness = history.wellness {
            VStack(spacing: 7) {
                HStack {
                    Text("RÉCUPÉRATION")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text("\(Int(wellness.recoveryConfidence.rounded()))% conf.")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    recoveryGauge(wellness)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(wellness.recoveryLabel)
                            .font(.headline.weight(.black))
                            .lineLimit(2)
                            .minimumScaleFactor(0.68)
                        Text("Indice personnel · Health")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 7) {
                    statusCell(
                        "Sommeil",
                        wellness.sleepSeconds.map(compactStatusDuration) ?? "—",
                        "bed.double.fill",
                        .indigo
                    )
                    statusCell(
                        "VFC nuit",
                        wellness.nightHRVMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—",
                        "waveform.path.ecg",
                        .purple
                    )
                }

                HStack(spacing: 7) {
                    statusCell(
                        "Continuité",
                        wellness.sleepEfficiency.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                        "moon.stars.fill",
                        .cyan
                    )
                    statusCell(
                        "Écart 7j",
                        wellness.sleepDeficit7DaysHours.map { $0 > 0.05 ? String(format: "-%.1fh", $0) : "0h" } ?? "—",
                        "chart.bar.fill",
                        .orange
                    )
                }
            }
            .padding(.horizontal, 4)
        } else {
            wellnessEmptyPage(
                title: "RÉCUPÉRATION",
                detail: "Ouvre l’app iPhone pour synchroniser les données Santé résumées.",
                symbol: "sparkles",
                accent: .cyan
            )
        }
    }

    @ViewBuilder
    private var cardioPage: some View {
        if let wellness = history.wellness {
            VStack(spacing: 8) {
                HStack {
                    Text("CARDIO · NUIT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.pink)
                    Spacer()
                    Image(systemName: "heart.text.square.fill")
                        .foregroundStyle(.pink)
                }

                HStack(spacing: 7) {
                    statusCell(
                        "VO₂ max",
                        wellness.vo2Max.map { String(format: "%.1f", $0) } ?? "—",
                        "lungs.fill",
                        .orange
                    )
                    statusCell(
                        "Récup FC",
                        wellness.heartRateRecoveryOneMinuteBPM.map { String(format: "%.0f bpm", $0) } ?? "—",
                        "heart.circle.fill",
                        .pink
                    )
                }

                HStack(spacing: 7) {
                    statusCell(
                        "FC nuit",
                        wellness.nightHeartRateBPM.map { String(format: "%.0f bpm", $0) } ?? "—",
                        "heart.fill",
                        .pink
                    )
                    statusCell(
                        "Respiration",
                        wellness.nightRespiratoryRate.map { String(format: "%.1f/min", $0) } ?? "—",
                        "lungs.fill",
                        .cyan
                    )
                }

                HStack(spacing: 7) {
                    statusCell(
                        "Oxygène",
                        wellness.oxygenSaturationPercent.map { String(format: "%.0f%%", $0) } ?? "—",
                        "drop.fill",
                        .blue
                    )
                    statusCell(
                        "Temp. nuit",
                        wellness.wristTemperatureCelsius.map { String(format: "%.2f°", $0) } ?? "—",
                        "thermometer.medium",
                        .orange
                    )
                }

                Text("Contexte personnel · pas un diagnostic")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        } else {
            wellnessEmptyPage(
                title: "CARDIO · NUIT",
                detail: "Les signaux apparaissent après synchronisation depuis l’iPhone.",
                symbol: "heart.text.square",
                accent: .pink
            )
        }
    }

    private var loadPage: some View {
        let reference = history.twentyEightDays.duration / 4
        let ratio = reference > 0 ? history.sevenDays.duration / reference : 0

        return VStack(spacing: 8) {
            HStack {
                Text("CHARGE")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.purple)
                Spacer()
                Text("7 j / 28 j")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, max(0, ratio)))
                    .stroke(
                        LinearGradient(colors: [.purple, .cyan], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text(loadLabel(ratio))
                        .font(.headline.weight(.black))
                        .minimumScaleFactor(0.65)
                    Text(reference > 0 ? String(format: "%.0f%%", ratio * 100) : "—")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)

            HStack(spacing: 7) {
                statusCell("7 jours", compactStatusDuration(history.sevenDays.duration), "calendar", .cyan)
                statusCell("Référence", compactStatusDuration(reference), "chart.bar.fill", .purple)
            }

            Text("Comparaison de volume, pas un diagnostic médical")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    private func recoveryGauge(_ wellness: WatchWellnessDigest) -> some View {
        let score = wellness.recoveryScore
        return ZStack {
            Circle().stroke(.white.opacity(0.08), lineWidth: 7)
            if let score {
                Circle()
                    .trim(from: 0, to: min(1, max(0, score / 100)))
                    .stroke(recoveryWatchAccent(score), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(score.rounded()))")
                    .font(.headline.weight(.black))
                    .monospacedDigit()
            } else {
                Image(systemName: "ellipsis")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 66, height: 66)
    }

    private func wellnessEmptyPage(title: String, detail: String, symbol: String, accent: Color) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(accent)
                Spacer()
            }
            StatusHero(
                title: "Données en attente",
                detail: detail,
                symbol: symbol,
                accent: accent
            )
        }
        .padding(.horizontal, 4)
    }

    private var gpsLabel: String {
        guard model.horizontalAccuracy >= 0 else { return "…" }
        return "±\(Int(model.horizontalAccuracy.rounded())) m"
    }

    private var gpsQualityText: String {
        switch model.horizontalAccuracy {
        case ..<0: return "Acquisition"
        case 0..<8: return "Très bonne précision"
        case 8..<20: return "Précision correcte"
        default: return "Précision faible : attendre si possible avant de démarrer"
        }
    }

    private var gpsAccent: Color {
        guard model.horizontalAccuracy >= 0 else { return .orange }
        if model.horizontalAccuracy < 8 { return .mint }
        if model.horizontalAccuracy < 20 { return .yellow }
        return .orange
    }

    private func loadLabel(_ ratio: Double) -> String {
        guard history.twentyEightDays.duration > 0 else { return "Pas assez" }
        switch ratio {
        case ..<0.65: return "En dessous"
        case ..<0.90: return "Un peu bas"
        case ..<1.15: return "Stable"
        case ..<1.45: return "Au-dessus"
        default: return "Très haut"
        }
    }

    private func statusCell(_ title: String, _ value: String, _ symbol: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title).foregroundStyle(.secondary)
            }
            .font(.system(size: 8, weight: .bold))
            Text(value)
                .font(.caption.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(.horizontal, 8)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct StatusHero: View {
    let title: String
    let detail: String
    let symbol: String
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2.weight(.bold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detail)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func compactStatusDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes)m"
}

private func recoveryWatchAccent(_ score: Double) -> Color {
    switch score {
    case 85...: return .mint
    case 70...: return .cyan
    case 55...: return .orange
    default: return .pink
    }
}
