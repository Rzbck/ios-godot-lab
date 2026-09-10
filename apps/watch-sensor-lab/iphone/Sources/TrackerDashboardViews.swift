import SwiftUI

struct TodayDashboardView: View {
    @EnvironmentObject private var tracker: TrackerModel
    let openActivity: () -> Void
    let openProgression: () -> Void
    let openHistory: () -> Void

    @AppStorage("tracker.healthInsightsEnabled") private var healthInsightsEnabled = false
    @State private var summaries: [TrackerSummary] = []
    @State private var health = HealthProgressionData.empty
    @State private var healthLoading = false
    @State private var showSettings = false

    private let store = NativeSessionStore()
    private let healthReader = HealthProgressionReader()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusHero
                    healthSnapshotCard
                    weeklyOverview
                    lastActivityCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
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
                TrackerSettingsView()
                    .environmentObject(tracker)
            }
            .refreshable {
                refresh()
                refreshHealthIfEnabled()
            }
            .onAppear {
                refresh()
                refreshHealthIfEnabled()
            }
            .onChange(of: tracker.lastSummary) { _, _ in refresh() }
            .onChange(of: healthInsightsEnabled) { _, enabled in
                if enabled { refreshHealthIfEnabled() }
            }
        }
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tracker.isActive ? "ACTIVITÉ EN COURS" : "PRÊT À BOUGER")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(tracker.isActive ? tracker.displayActivity.label : tracker.selectedActivity.label)
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Image(systemName: tracker.isActive ? tracker.displayActivity.symbol : "figure.run")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.mint)
            }

            HStack(spacing: 8) {
                ReadinessPill(title: "Watch", ready: tracker.watchReachable, symbol: "applewatch")
                ReadinessPill(title: "GPS", ready: tracker.horizontalAccuracy >= 0, symbol: "location.fill")
                ReadinessPill(title: "Santé", ready: tracker.healthAuthorized, symbol: "heart.text.square.fill")
            }

            Button(action: openActivity) {
                HStack(spacing: 10) {
                    Image(systemName: tracker.isActive ? "waveform.path.ecg" : "play.fill")
                    Text(tracker.isActive ? "VOIR L’ACTIVITÉ" : "DÉMARRER UNE ACTIVITÉ")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isActive ? .mint : .green)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private var healthSnapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("SANTÉ AUJOURD’HUI", systemImage: "heart.text.square.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Progression", action: openProgression)
                    .font(.caption.weight(.semibold))
            }

            if !healthInsightsEnabled {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "heart.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ajoute ton contexte Santé")
                            .font(.headline.weight(.bold))
                        Text("Sommeil, FC au repos, HRV, pas et autres tendances restent facultatifs et ne sont demandés que lorsque tu ouvres Progression.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Configurer dans Progression", action: openProgression)
                    .buttonStyle(.bordered)
            } else if healthLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Actualisation des données Santé…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TodayHealthMetric(
                        title: "Pas",
                        value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                        detail: "aujourd’hui",
                        symbol: "shoeprints.fill"
                    )
                    TodayHealthMetric(
                        title: "Sommeil",
                        value: health.sleepHours.map(todayHoursText) ?? "—",
                        detail: health.sleepSource ?? "indisponible / non partagé",
                        symbol: "bed.double.fill"
                    )
                    TodayHealthMetric(
                        title: "FC repos",
                        value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                        detail: health.restingHeartRate.map { $0.source } ?? "indisponible / non partagé",
                        symbol: "heart.fill"
                    )
                    TodayHealthMetric(
                        title: "HRV",
                        value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                        detail: health.hrvSDNN.map { $0.source } ?? "indisponible / non partagé",
                        symbol: "waveform.path.ecg"
                    )
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weeklyOverview: some View {
        let recent = summaries.filter { $0.startedAt >= weekStart }
        let distance = recent.reduce(0) { $0 + $1.distanceMeters }
        let duration = recent.reduce(0) { $0 + $1.duration }
        let energy = recent.compactMap(\.activeEnergyKcal).reduce(0, +)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CETTE SEMAINE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Historique", action: openHistory)
                    .font(.caption.weight(.semibold))
            }

            HStack(spacing: 10) {
                DashboardMetric(value: "\(recent.count)", label: "activités", symbol: "calendar")
                DashboardMetric(value: dashboardDistance(distance), label: "distance", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                DashboardMetric(value: dashboardDuration(duration), label: "temps", symbol: "timer")
            }

            if energy > 0 {
                Label("\(Int(energy.rounded())) kcal actives enregistrées", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var lastActivityCard: some View {
        if let summary = summaries.first {
            Button(action: openHistory) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("DERNIÈRE ACTIVITÉ")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }

                    HStack {
                        Label(
                            ActivityKind(rawValue: summary.activity)?.label ?? summary.activity,
                            systemImage: ActivityKind(rawValue: summary.activity)?.symbol ?? "figure.walk"
                        )
                        .font(.headline.weight(.bold))
                        Spacer()
                        Text(summary.startedAt, format: .dateTime.day().month().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 18) {
                        SummaryValue(value: dashboardDistance(summary.distanceMeters), label: "Distance")
                        SummaryValue(value: dashboardDuration(summary.duration), label: "Temps")
                        SummaryValue(
                            value: summary.averageHeartRate > 0 ? "\(Int(summary.averageHeartRate.rounded())) bpm" : "—",
                            label: "FC moy."
                        )
                    }
                }
                .padding(16)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            ContentUnavailableView(
                "Pas encore d’activité",
                systemImage: "figure.walk.circle",
                description: Text("Ta première séance apparaîtra ici avec ses métriques principales.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var weekStart: Date {
        Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
    }

    private func refresh() {
        summaries = store.listSummaries()
    }

    private func refreshHealthIfEnabled() {
        guard healthInsightsEnabled, !healthLoading else { return }
        healthLoading = true
        healthReader.load { result in
            health = result
            healthLoading = false
        }
    }
}

private struct ReadinessPill: View {
    let title: String
    let ready: Bool
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ready ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(ready ? Color.green.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
    }
}

private struct DashboardMetric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SummaryValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TodayHealthMetric: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .lineLimit(1)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func dashboardDistance(_ meters: Double) -> String {
    if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
    return String(format: "%.0f m", meters)
}

private func dashboardDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    if hours > 0 { return String(format: "%dh%02d", hours, minutes) }
    return "\(minutes) min"
}

private func todayHoursText(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}
