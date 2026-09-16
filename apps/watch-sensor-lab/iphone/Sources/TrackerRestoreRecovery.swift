import HealthKit
import SwiftUI

extension TrackerModel {
    func workflowRestoreHistoricalActivity(
        sessionID: String,
        activity: ActivityKind
    ) {
        restoreHistoricalActivityFromRaw(
            sessionID: sessionID,
            activity: activity
        )
    }
}

struct TrackerRestoreRecoveryView: View {
    @EnvironmentObject private var tracker: TrackerModel

    @State private var summaries: [TrackerSummary] = []
    @State private var readableHealthSessionIDs: Set<String> = []
    @State private var loading = true

    private let store = NativeSessionStore()
    private let healthStore = HKHealthStore()

    private var candidates: [TrackerSummary] {
        summaries
            .filter {
                !readableHealthSessionIDs.contains($0.sessionID)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Comparaison Tracker / Santé…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if candidates.isEmpty {
                    ContentUnavailableView(
                        "Aucune séance à restaurer",
                        systemImage: "checkmark.circle.fill",
                        description: Text(
                            "Toutes les séances Tracker locales ont actuellement un workout Tracker lisible dans Santé."
                        )
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(
                                    "Récupération Santé",
                                    systemImage: "arrow.clockwise.heart.fill"
                                )
                                .font(.headline.weight(.bold))

                                Text(
                                    "Ces séances existent encore dans Tracker mais aucun workout Tracker portant le même identifiant n’est actuellement lisible dans Santé. La Watch refusera toute restauration si un doublon existe réellement."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                .orange.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )

                            ForEach(candidates, id: \.sessionID) { summary in
                                TrackerRestoreCandidateCard(summary: summary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .refreshable { refresh() }
                }
            }
            .navigationTitle("Récupération")
            .onAppear { refresh() }
            .onChange(of: tracker.historicalRepairStatus) { _, status in
                guard !status.isEmpty else { return }
                refresh()
            }
        }
        .preferredColorScheme(.dark)
    }

    private func refresh() {
        loading = true
        summaries = store.listSummaries()

        guard HKHealthStore.isHealthDataAvailable() else {
            readableHealthSessionIDs = []
            loading = false
            return
        }

        let workoutType = HKObjectType.workoutType()

        healthStore.requestAuthorization(
            toShare: [],
            read: [workoutType]
        ) { _, _ in
            let sort = NSSortDescriptor(
                key: HKSampleSortIdentifierStartDate,
                ascending: false
            )

            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let values = samples as? [HKWorkout] ?? []
                let ids = Set(
                    values.compactMap {
                        $0.metadata?["com.rzbck.watchsensorlab.session_id"] as? String
                    }
                )

                DispatchQueue.main.async {
                    readableHealthSessionIDs = ids
                    loading = false
                }
            }

            healthStore.execute(query)
        }
    }
}

private struct TrackerRestoreCandidateCard: View {
    @EnvironmentObject private var tracker: TrackerModel

    let summary: TrackerSummary

    @State private var selection: ActivityKind?
    @State private var confirming = false

    private var activities: [ActivityKind] {
        ActivityKind.allCases.filter { !$0.isAutomatic }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        ActivityKind(rawValue: summary.activity)?.label
                            ?? summary.activity
                    )
                    .font(.headline.weight(.bold))

                    Text(
                        summary.startedAt,
                        format: .dateTime.day().month().year().hour().minute()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 14) {
                restoreMetric(
                    value: restoreDistance(summary.distanceMeters),
                    label: "Distance"
                )
                restoreMetric(
                    value: restoreDuration(summary.duration),
                    label: "Actif"
                )
                restoreMetric(
                    value: summary.activeEnergyKcal.map {
                        String(format: "%.0f kcal", $0)
                    } ?? "—",
                    label: "Énergie"
                )
            }

            Picker("Sport à restaurer", selection: $selection) {
                Text("Choisir…")
                    .tag(Optional<ActivityKind>.none)

                ForEach(activities) { activity in
                    Text(activity.label)
                        .tag(Optional(activity))
                }
            }
            .pickerStyle(.menu)

            Button {
                confirming = true
            } label: {
                Label(
                    "Restaurer dans Santé",
                    systemImage: "heart.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(selection == nil)

            if tracker.historicalRepairSessionID == summary.sessionID,
               !tracker.historicalRepairStatus.isEmpty {
                Text(tracker.historicalRepairStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            .white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .confirmationDialog(
            "Restaurer cette séance dans Santé ?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            if let selection {
                Button("Restaurer en \(selection.label)") {
                    tracker.workflowRestoreHistoricalActivity(
                        sessionID: summary.sessionID,
                        activity: selection
                    )
                }
            }

            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "La Watch vérifiera d’abord qu’aucun workout Tracker n’existe déjà pour ce session ID. Aucun workout existant n’est supprimé par ce chemin."
            )
        }
    }

    private func restoreMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func restoreDistance(_ meters: Double) -> String {
    meters >= 1000
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.0f m", meters)
}

private func restoreDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0
        ? String(format: "%dh%02d", hours, minutes)
        : "\(minutes) min"
}
