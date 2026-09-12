import Foundation
import HealthKit
import SwiftUI

/// Read-only diagnostic for managed Tracker workouts that are not historical
/// restoration objects. This exists to identify stale/hidden HealthKit objects
/// before any destructive cleanup decision is made.
@MainActor
final class HistoricalManagedWorkoutAudit: ObservableObject {
    struct Record: Identifiable, Equatable {
        let id: UUID
        let sessionID: String
        let activityLabel: String
        let activityRawValue: UInt
        let startDate: Date
        let endDate: Date
        let duration: TimeInterval
        let sourceBundle: String
        let sourceVersion: String?
        let selectedActivity: String?
        let initialHealthActivity: String?
        let algorithmVersion: String?
        let generation: String?
        let rawRestoration: Bool
    }

    @Published private(set) var records: [Record] = []
    @Published private(set) var status = ""
    @Published private(set) var isLoading = false

    private let healthStore = HKHealthStore()
    private let managedKey = "com.rzbck.watchsensorlab.managed"
    private let sessionKey = "com.rzbck.watchsensorlab.session_id"
    private let rawRestoreKey = "com.rzbck.watchsensorlab.raw_restoration"
    private let selectedActivityKey = "com.rzbck.watchsensorlab.selected_activity"
    private let initialActivityKey = "com.rzbck.watchsensorlab.healthkit_initial_activity"
    private let algorithmKey = "com.rzbck.watchsensorlab.algorithm_version"
    private let generationKey = "com.rzbck.watchsensorlab.historical_generation"

    func refresh(summaries: [TrackerSummary]) {
        guard !isLoading else { return }
        isLoading = true
        status = "Audit HealthKit lecture seule…"

        Task {
            defer { isLoading = false }
            do {
                var found: [Record] = []
                for summary in summaries {
                    found.append(contentsOf: try await normalManagedWorkouts(for: summary))
                }
                records = found.sorted { $0.startDate > $1.startDate }
                status = records.isEmpty
                    ? "Aucun workout Tracker non-restauration détecté."
                    : "\(records.count) workout(s) Tracker non-restauration détecté(s) par HealthKit."
            } catch {
                status = "Audit HealthKit échoué · \(error.localizedDescription)"
            }
        }
    }

    private func normalManagedWorkouts(for summary: TrackerSummary) async throws -> [Record] {
        let predicate = HKQuery.predicateForSamples(
            withStart: summary.startedAt.addingTimeInterval(-120),
            end: summary.endedAt.addingTimeInterval(120),
            options: []
        )
        let samples = try await querySamples(
            type: HKObjectType.workoutType(),
            predicate: predicate
        )
        return (samples as? [HKWorkout] ?? []).compactMap { workout in
            guard (workout.metadata?[managedKey] as? Bool) == true,
                  (workout.metadata?[sessionKey] as? String) == summary.sessionID,
                  (workout.metadata?[rawRestoreKey] as? Bool) != true else {
                return nil
            }

            let activity = ActivityKind(healthKitType: workout.workoutActivityType)
            return Record(
                id: workout.uuid,
                sessionID: summary.sessionID,
                activityLabel: activity?.label ?? "HK \(workout.workoutActivityType.rawValue)",
                activityRawValue: workout.workoutActivityType.rawValue,
                startDate: workout.startDate,
                endDate: workout.endDate,
                duration: workout.duration,
                sourceBundle: workout.sourceRevision.source.bundleIdentifier,
                sourceVersion: workout.sourceRevision.version,
                selectedActivity: workout.metadata?[selectedActivityKey] as? String,
                initialHealthActivity: workout.metadata?[initialActivityKey] as? String,
                algorithmVersion: workout.metadata?[algorithmKey] as? String,
                generation: workout.metadata?[generationKey] as? String,
                rawRestoration: false
            )
        }
    }

    private func querySamples(
        type: HKSampleType,
        predicate: NSPredicate?
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }
}

struct HistoricalRecoveryDiagnosticHostView: View {
    @StateObject private var audit = HistoricalManagedWorkoutAudit()
    @State private var expanded = false
    private let store = NativeSessionStore()

    var body: some View {
        VStack(spacing: 0) {
            if !audit.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        expanded.toggle()
                    } label: {
                        HStack {
                            Label(
                                "Diagnostic HealthKit lecture seule · \(audit.records.count)",
                                systemImage: "magnifyingglass.circle"
                            )
                            .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                    }
                    .buttonStyle(.plain)

                    if expanded {
                        ForEach(audit.records) { record in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Session \(record.sessionID)")
                                Text("UUID \(record.id.uuidString)")
                                Text("Type \(record.activityLabel) · HK \(record.activityRawValue)")
                                Text(
                                    "Début \(record.startDate.formatted(.iso8601)) · durée \(String(format: \"%.1f\", record.duration)) s"
                                )
                                Text("Source \(record.sourceBundle) · version \(record.sourceVersion ?? "—")")
                                Text("selected_activity \(record.selectedActivity ?? "—")")
                                Text("healthkit_initial_activity \(record.initialHealthActivity ?? "—")")
                                Text("algorithm_version \(record.algorithmVersion ?? "—")")
                                Text("historical_generation \(record.generation ?? "—")")
                            }
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.yellow.opacity(0.10))
            }

            HistoricalHealthKitRepairV4View()
        }
        .task {
            audit.refresh(summaries: store.listSummaries())
        }
    }
}
