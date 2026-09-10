import SwiftUI

struct TodayDashboardView: View {
    @EnvironmentObject private var tracker: TrackerModel
    let openActivity: () -> Void
    let openHistory: () -> Void

    @State private var summaries: [TrackerSummary] = []
    private let store = NativeSessionStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    statusHero
                    weeklyOverview
                    lastActivityCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Aujourd’hui")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.crop.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Profil et réglages")
                }
            }
            .onAppear { refresh() }
            .onChange(of: tracker.lastSummary) { _, _ in refresh() }
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
}

struct ActivityHubView: View {
    @EnvironmentObject private var tracker: TrackerModel

    var body: some View {
        Group {
            if tracker.isActive {
                LiveTrackerView()
            } else {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            activityHero
                            readinessCard
                            autoPauseCard
                        }
                        .padding(16)
                    }
                    .navigationTitle("Activité")
                    .onAppear { tracker.requestLocationPermission() }
                }
            }
        }
    }

    private var activityHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NOUVELLE ACTIVITÉ")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(tracker.selectedActivity.label)
                        .font(.title2.weight(.bold))
                    if tracker.selectedActivity.isAutomatic {
                        Text("La Watch adapte le type d’activité avec une détection conservatrice.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: tracker.selectedActivity.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.mint)
            }

            Menu {
                Section("Recommandé") {
                    activityMenuButton(.automatic)
                    activityMenuButton(.walking)
                    activityMenuButton(.running)
                    activityMenuButton(.cycling)
                    activityMenuButton(.hiking)
                    activityMenuButton(.swimBikeRun)
                }
                Section("Tous les sports") {
                    ForEach(ActivityKind.allCases.filter {
                        ![.automatic, .walking, .running, .cycling, .hiking, .swimBikeRun].contains($0)
                    }) { activity in
                        activityMenuButton(activity)
                    }
                }
            } label: {
                HStack {
                    Label(tracker.selectedActivity.label, systemImage: tracker.selectedActivity.symbol)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { tracker.startFromPhone() } label: {
                Label("Démarrer", systemImage: "play.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(tracker.pendingCommand != nil)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PRÉPARATION")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ReadinessPill(title: "Watch", ready: tracker.watchReachable, symbol: "applewatch")
                ReadinessPill(title: "GPS", ready: tracker.horizontalAccuracy >= 0, symbol: "location.fill")
                ReadinessPill(title: "Santé", ready: tracker.healthAuthorized, symbol: "heart.text.square.fill")
            }
            Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var autoPauseCard: some View {
        Toggle(
            isOn: Binding(
                get: { tracker.autoPauseEnabled },
                set: { tracker.setAutoPauseEnabled($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pause automatique")
                    .font(.headline)
                Text("La Watch garde l’autorité. Les réglages détaillés seront centralisés sur l’iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.mint)
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func activityMenuButton(_ activity: ActivityKind) -> some View {
        Button {
            tracker.selectActivity(activity)
        } label: {
            Label(activity.label, systemImage: activity.symbol)
        }
    }
}

struct ProgressionDashboardView: View {
    @State private var summaries: [TrackerSummary] = []
    private let store = NativeSessionStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Tes tendances personnelles")
                        .font(.title3.weight(.bold))
                    Text("Cette première vue utilise uniquement les activités Watch Tracker déjà enregistrées. L’enrichissement historique Apple Health sera ajouté séparément pour ne jamais confondre absence de permission et valeur zéro.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    comparisonCard
                    foundationCard
                }
                .padding(16)
            }
            .navigationTitle("Progression")
            .onAppear { summaries = store.listSummaries() }
        }
    }

    private var comparisonCard: some View {
        let seven = aggregate(days: 7)
        let twentyEight = aggregate(days: 28)

        return VStack(alignment: .leading, spacing: 12) {
            Text("CHARGE D’ACTIVITÉ")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                DashboardMetric(value: dashboardDuration(seven.duration), label: "7 jours", symbol: "7.circle.fill")
                DashboardMetric(value: dashboardDuration(twentyEight.duration), label: "28 jours", symbol: "calendar.circle.fill")
            }

            Text(progressMessage(sevenDays: seven.duration, twentyEightDays: twentyEight.duration))
                .font(.subheadline.weight(.semibold))
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var foundationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Bientôt : contexte Santé", systemImage: "heart.text.square.fill")
                .font(.headline.weight(.bold))
            Text("Sommeil, FC au repos, HRV et autres tendances HealthKit ne seront affichés qu’avec des données réellement lisibles et une provenance claire.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func aggregate(days: Int) -> (duration: TimeInterval, distance: Double, count: Int) {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let filtered = summaries.filter { $0.startedAt >= threshold }
        return (
            filtered.reduce(0) { $0 + $1.duration },
            filtered.reduce(0) { $0 + $1.distanceMeters },
            filtered.count
        )
    }

    private func progressMessage(sevenDays: TimeInterval, twentyEightDays: TimeInterval) -> String {
        guard twentyEightDays > 0 else { return "Enregistre quelques séances pour construire une tendance fiable." }
        let weeklyBaseline = twentyEightDays / 4.0
        guard weeklyBaseline > 0 else { return "Données insuffisantes pour comparer les périodes." }
        let ratio = sevenDays / weeklyBaseline
        if ratio > 1.25 { return "Volume récent nettement au-dessus de ta moyenne des 4 dernières semaines." }
        if ratio < 0.75 { return "Volume récent plus léger que ta moyenne des 4 dernières semaines." }
        return "Volume récent proche de ta moyenne des 4 dernières semaines."
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
