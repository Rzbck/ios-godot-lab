import SwiftUI

struct WatchProgressionDepthView: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        NavigationStack {
            TabView {
                todayPage
                .containerBackground(for: .tabView) { Color.clear }
                .tag(0)
                .accessibilityLabel("Progression aujourd’hui")

                weekPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(1)
                    .accessibilityLabel("Progression sept jours")

                monthPage
                    .containerBackground(for: .tabView) { Color.clear }
                    .tag(2)
                    .accessibilityLabel("Progression vingt-huit jours")
            }
            .tabViewStyle(.verticalPage)
            .navigationTitle("Progression")
        }
    }

    private var todayPage: some View {
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
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
            }

            NavigationLink {
                WatchProgressDetailView(
                    title: "Aujourd’hui",
                    primary: compactDepthDuration(history.today.duration),
                    subtitle: "Temps actif",
                    stats: history.today,
                    buckets: Array(history.daily28.suffix(1)),
                    accent: .cyan
                )
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [.cyan.opacity(0.18), .indigo.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 4) {
                        Text(compactDepthDuration(history.today.duration))
                            .font(.system(size: 30, weight: .black, design: .rounded))
                            .monospacedDigit()
                        HStack(spacing: 4) {
                            Text("temps actif")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 82)
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                metricLink("\(history.today.count)", "séances", "figure.run", .orange, title: "Séances aujourd’hui", stats: history.today, buckets: Array(history.daily28.suffix(1)))
                metricLink(compactDepthDistance(history.today.distanceMeters), "distance", "location.fill", .mint, title: "Distance aujourd’hui", stats: history.today, buckets: Array(history.daily28.suffix(1)))
            }

            Text("↓ 7 jours · touche une zone pour le détail")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private var weekPage: some View {
        let current = Array(history.daily28.suffix(7))
        let previous = history.daily28.count >= 14 ? Array(history.daily28.suffix(14).prefix(7)) : []
        let currentMinutes = current.reduce(0) { $0 + $1.duration } / 60
        let previousMinutes = previous.reduce(0) { $0 + $1.duration } / 60

        return VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("7 JOURS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.cyan)
                    Text(compactDepthDuration(history.sevenDays.duration))
                        .font(.headline.weight(.black))
                }
                Spacer()
                Text(deltaLabel(current: currentMinutes, previous: previousMinutes))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(previousMinutes > 0 && currentMinutes < previousMinutes ? Color.orange : Color.mint)
                    .multilineTextAlignment(.trailing)
            }

            NavigationLink {
                WatchComparisonDetailView(current: current, previous: previous)
            } label: {
                VStack(spacing: 4) {
                    WatchComparisonBars(current: current, previous: previous)
                        .frame(height: 86)
                    HStack {
                        Text("actuel / précédent")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                metricLink("\(history.sevenDays.count)", "séances", "figure.run", .orange, title: "Séances sur 7 jours", stats: history.sevenDays, buckets: current)
                metricLink(compactDepthDistance(history.sevenDays.distanceMeters), "distance", "location.fill", .mint, title: "Distance sur 7 jours", stats: history.sevenDays, buckets: current)
            }

            Text("↓ 28 jours")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private var monthPage: some View {
        let values = Array(history.daily28.suffix(28))
        let weeks = stride(from: 0, to: values.count, by: 7).map { start -> Double in
            let end = min(start + 7, values.count)
            return values[start..<end].reduce(0) { $0 + $1.duration } / 60
        }

        return VStack(spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("28 JOURS")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.purple)
                    Text(compactDepthDuration(history.twentyEightDays.duration))
                        .font(.headline.weight(.black))
                }
                Spacer()
                Image(systemName: "chart.bar.fill").foregroundStyle(.purple)
            }

            NavigationLink {
                WatchProgressDetailView(
                    title: "28 jours",
                    primary: compactDepthDuration(history.twentyEightDays.duration),
                    subtitle: "Temps actif",
                    stats: history.twentyEightDays,
                    buckets: values,
                    accent: .purple
                )
            } label: {
                VStack(spacing: 4) {
                    WatchWeeklyBars(values: weeks).frame(height: 86)
                    HStack {
                        Text("4 semaines")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                metricLink("\(history.twentyEightDays.count)", "séances", "figure.run", .orange, title: "Séances sur 28 jours", stats: history.twentyEightDays, buckets: values)
                metricLink(compactDepthDistance(history.twentyEightDays.distanceMeters), "distance", "location.fill", .mint, title: "Distance sur 28 jours", stats: history.twentyEightDays, buckets: values)
            }

            Text("Touchez un bloc pour entrer dans le détail")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
    }

    private func metricLink(_ value: String, _ label: String, _ symbol: String, _ accent: Color, title: String, stats: WatchHistoryWindowStats, buckets: [WatchHistoryDayBucket]) -> some View {
        NavigationLink {
            WatchProgressDetailView(title: title, primary: value, subtitle: label, stats: stats, buckets: buckets, accent: accent)
        } label: {
            depthMetric(value, label, symbol, accent)
        }
        .buttonStyle(.plain)
    }

    private func deltaLabel(current: Double, previous: Double) -> String {
        guard previous > 0 else { return "nouveau repère" }
        let value = (current - previous) / previous
        if abs(value) < 0.03 { return "≈ semaine passée" }
        return String(format: "%@%.0f%% vs avant", value >= 0 ? "+" : "", value * 100)
    }
}

private struct WatchProgressDetailView: View {
    let title: String
    let primary: String
    let subtitle: String
    let stats: WatchHistoryWindowStats
    let buckets: [WatchHistoryDayBucket]
    let accent: Color

    var body: some View {
        TabView {
            VStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(accent)
                Text(primary)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 7) {
                    depthMetric("\(stats.count)", "séances", "figure.run", .orange)
                    depthMetric(compactDepthDistance(stats.distanceMeters), "distance", "location.fill", .mint)
                }
                Text("↓ tendance")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 7) {
                HStack {
                    Text("TENDANCE")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(accent)
                    Spacer()
                    Text("\(buckets.count) j")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                WatchSingleSeriesBars(values: buckets.map { $0.duration / 60 }, accent: accent)
                    .frame(height: 104)
                Text("Temps actif par jour")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(title)
    }
}

private struct WatchComparisonDetailView: View {
    let current: [WatchHistoryDayBucket]
    let previous: [WatchHistoryDayBucket]

    var body: some View {
        TabView {
            VStack(spacing: 8) {
                Text("7 jours vs avant")
                    .font(.headline.weight(.black))
                WatchComparisonBars(current: current, previous: previous)
                    .frame(height: 110)
                Text("cyan = actuel · gris = précédent")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                Text("Cumul")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                depthMetric(compactDepthDuration(current.reduce(0) { $0 + $1.duration }), "actuel", "calendar", .cyan)
                depthMetric(compactDepthDuration(previous.reduce(0) { $0 + $1.duration }), "précédent", "clock.arrow.circlepath", .secondary)
            }
            .padding(.horizontal, 4)
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle("Comparaison")
    }
}

private struct WatchComparisonBars: View {
    let current: [WatchHistoryDayBucket]
    let previous: [WatchHistoryDayBucket]

    private var maxMinutes: Double {
        max(1, (current.map { $0.duration / 60 } + previous.map { $0.duration / 60 }).max() ?? 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(0..<7), id: \.self) { index in
                VStack(spacing: 3) {
                    HStack(alignment: .bottom, spacing: 2) {
                        Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 6, height: barHeight(previous, index: index))
                        Capsule().fill(Color.cyan).frame(width: 6, height: barHeight(current, index: index))
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
        return CGFloat(max(2, min(68, (values[index].duration / 60) / maxMinutes * 68)))
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
                        .fill(LinearGradient(colors: [.purple, .cyan], startPoint: .bottom, endPoint: .top))
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

private struct WatchSingleSeriesBars: View {
    let values: [Double]
    let accent: Color
    private var maximum: Double { max(1, values.max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(max(2, min(92, value / maximum * 92))))
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
