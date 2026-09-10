import SwiftUI

struct WatchProgressionDepthView: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        TabView {
            WatchTodayProgressPage(history: history)
            WatchWeekProgressPage(history: history)
            WatchMonthProgressPage(history: history)
        }
        .tabViewStyle(.verticalPage)
    }
}

private struct WatchTodayProgressPage: View {
    @ObservedObject var history: WatchRecentHistoryStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("AUJOURD’HUI")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.cyan)
                    Text("Ton activité du jour")
                        .font(.caption.weight(.bold))
                }
                Spacer()
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(.yellow)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.cyan.opacity(0.18), .indigo.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 4) {
                    Text(compactDepthDuration(history.today.duration))
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("temps actif")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 82)

            HStack(spacing: 7) {
                depthMetric("\(history.today.count)", "séances", "figure.run", .orange)
                depthMetric(compactDepthDistance(history.today.distanceMeters), "distance", "location.fill", .mint)
            }

            Text("↓ 7 jours")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}

private struct WatchWeekProgressPage: View {
    @ObservedObject var history: WatchRecentHistoryStore

    private var current: [WatchHistoryDayBucket] {
        Array(history.daily28.suffix(7))
    }

    private var previous: [WatchHistoryDayBucket] {
        guard history.daily28.count >= 14 else { return [] }
        return Array(history.daily28.suffix(14).prefix(7))
    }

    private var currentMinutes: Double {
        current.reduce(0) { $0 + $1.duration } / 60
    }

    private var previousMinutes: Double {
        previous.reduce(0) { $0 + $1.duration } / 60
    }

    private var delta: String {
        guard previousMinutes > 0 else { return "nouveau repère" }
        let value = (currentMinutes - previousMinutes) / previousMinutes
        if abs(value) < 0.03 { return "≈ semaine passée" }
        return String(format: "%@%.0f%% vs avant", value >= 0 ? "+" : "", value * 100)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("7 JOURS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.cyan)
                    Text(compactDepthDuration(history.sevenDays.duration))
                        .font(.headline.weight(.black))
                }
                Spacer()
                Text(delta)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(previousMinutes > 0 && currentMinutes < previousMinutes ? Color.orange : Color.mint)
                    .multilineTextAlignment(.trailing)
            }

            WatchComparisonBars(current: current, previous: previous)
                .frame(height: 92)

            HStack(spacing: 7) {
                depthMetric("\(history.sevenDays.count)", "séances", "figure.run", .orange)
                depthMetric(compactDepthDistance(history.sevenDays.distanceMeters), "distance", "location.fill", .mint)
            }

            Text("gris = 7 j précédents · ↓ 28 jours")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }
}

private struct WatchMonthProgressPage: View {
    @ObservedObject var history: WatchRecentHistoryStore

    private var weeks: [Double] {
        let values = Array(history.daily28.suffix(28))
        guard !values.isEmpty else { return [] }
        return stride(from: 0, to: values.count, by: 7).map { start in
            let end = min(start + 7, values.count)
            return values[start..<end].reduce(0) { $0 + $1.duration } / 60
        }
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("28 JOURS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.purple)
                    Text(compactDepthDuration(history.twentyEightDays.duration))
                        .font(.headline.weight(.black))
                }
                Spacer()
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.purple)
            }

            WatchWeeklyBars(values: weeks)
                .frame(height: 92)

            HStack(spacing: 7) {
                depthMetric("\(history.twentyEightDays.count)", "séances", "figure.run", .orange)
                depthMetric(compactDepthDistance(history.twentyEightDays.distanceMeters), "distance", "location.fill", .mint)
            }

            Text("4 semaines · tourne la couronne ou glisse ↑↓")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }
}

private struct WatchComparisonBars: View {
    let current: [WatchHistoryDayBucket]
    let previous: [WatchHistoryDayBucket]

    private var maxMinutes: Double {
        let values = current.map { $0.duration / 60 } + previous.map { $0.duration / 60 }
        return max(1, values.max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 3) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 6, height: barHeight(previous, index: index))
                        Capsule()
                            .fill(Color.cyan)
                            .frame(width: 6, height: barHeight(current, index: index))
                    }
                    Text(dayLabel(index))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }

    private func barHeight(_ values: [WatchHistoryDayBucket], index: Int) -> CGFloat {
        guard index < values.count else { return 2 }
        let minutes = values[index].duration / 60
        return CGFloat(max(2, min(68, minutes / maxMinutes * 68)))
    }

    private func dayLabel(_ index: Int) -> String {
        guard index < current.count else { return "·" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EE"
        return String(formatter.string(from: current[index].date).prefix(1)).uppercased()
    }
}

private struct WatchWeeklyBars: View {
    let values: [Double]

    private var maximum: Double { max(1, values.max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 4) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .cyan],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(width: 20, height: CGFloat(max(3, min(68, value / maximum * 68))))
                    Text("S\(index + 1)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
    }
}

private func depthMetric(_ value: String, _ label: String, _ symbol: String, _ accent: Color) -> some View {
    HStack(spacing: 5) {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(accent)
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.caption.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
    }
    .padding(.horizontal, 7)
    .frame(height: 34)
    .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
}

private func compactDepthDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes)m"
}

private func compactDepthDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}
