import Foundation
import HealthKit
import SwiftUI

struct HealthWorkoutRecord: Identifiable, Equatable {
    let id: UUID
    let activity: ActivityKind
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let activeEnergyKcal: Double?
    let sourceName: String
    let trackerSessionID: String?

    var isWatchTrackerWorkout: Bool { trackerSessionID != nil }
}

final class HealthWorkoutHistoryReader {
    private let store = HKHealthStore()

    func loadAll(completion: @escaping ([HealthWorkoutRecord]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion([]) }
            return
        }

        let workoutType = HKObjectType.workoutType()
        store.requestAuthorization(toShare: [], read: [workoutType]) { [weak self] _, _ in
            guard let self else { return }
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                let values = (samples as? [HKWorkout] ?? []).map(Self.makeRecord)
                DispatchQueue.main.async { completion(values) }
            }
            self.store.execute(query)
        }
    }

    private static func makeRecord(_ workout: HKWorkout) -> HealthWorkoutRecord {
        let metadata = workout.metadata ?? [:]
        let sessionID = metadata["com.rzbck.watchsensorlab.session_id"] as? String
        let activity = ActivityKind(healthKitType: workout.workoutActivityType) ?? .other
        let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
        let energy = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())

        return HealthWorkoutRecord(
            id: workout.uuid,
            activity: activity,
            startedAt: workout.startDate,
            endedAt: workout.endDate,
            duration: workout.duration,
            distanceMeters: max(0, distance),
            activeEnergyKcal: energy.map { max(0, $0) },
            sourceName: workout.sourceRevision.source.name,
            trackerSessionID: sessionID
        )
    }
}

struct HistoryEntryView: View {
    private enum Source: String, CaseIterable, Identifiable {
        case health
        case tracker

        var id: String { rawValue }
        var label: String { self == .health ? "Santé" : "Tracker" }
    }

    @State private var source: Source = .health

    var body: some View {
        VStack(spacing: 0) {
            Picker("Source", selection: $source) {
                ForEach(Source.allCases) { item in
                    Text(item.label).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if source == .health {
                HealthWorkoutHistoryView()
            } else {
                ActivityHistoryView()
            }
        }
        .preferredColorScheme(.dark)
    }
}

private enum HealthHistoryPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "7 j"
        case .month: return "30 j"
        case .all: return "Tout"
        }
    }

    var threshold: Date? {
        switch self {
        case .week: return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        case .all: return nil
        }
    }
}

private struct HealthWorkoutHistoryView: View {
    @State private var records: [HealthWorkoutRecord] = []
    @State private var period: HealthHistoryPeriod = .month
    @State private var searchText = ""
    @State private var loading = true

    private let reader = HealthWorkoutHistoryReader()

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Lecture de l’historique Santé…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if filteredRecords.isEmpty {
                    ContentUnavailableView(
                        "Aucune activité Santé lisible",
                        systemImage: "heart.text.square",
                        description: Text("Watch Tracker affiche uniquement les entraînements que Santé autorise l’app à lire. Une absence de données peut aussi correspondre à un accès non partagé ou limité.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            HealthHistoryOverview(records: filteredRecords)

                            Picker("Période", selection: $period) {
                                ForEach(HealthHistoryPeriod.allCases) { item in
                                    Text(item.label).tag(item)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack {
                                Label("Toutes les apps Santé", systemImage: "heart.text.square.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(filteredRecords.count) séance\(filteredRecords.count > 1 ? "s" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }

                            ForEach(filteredRecords) { record in
                                NavigationLink {
                                    HealthWorkoutDetailView(record: record)
                                } label: {
                                    HealthWorkoutRow(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Historique Santé")
            .searchable(text: $searchText, prompt: "Sport, app ou date")
            .refreshable { refresh() }
            .onAppear { refresh() }
        }
    }

    private var filteredRecords: [HealthWorkoutRecord] {
        records.filter { record in
            if let threshold = period.threshold, record.startedAt < threshold { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let date = record.startedAt.formatted(date: .abbreviated, time: .shortened)
            return record.activity.label.localizedCaseInsensitiveContains(query)
                || record.sourceName.localizedCaseInsensitiveContains(query)
                || date.localizedCaseInsensitiveContains(query)
        }
    }

    private func refresh() {
        loading = true
        reader.loadAll { values in
            records = values
            loading = false
        }
    }
}

private struct HealthHistoryOverview: View {
    let records: [HealthWorkoutRecord]

    private var distance: Double { records.reduce(0) { $0 + $1.distanceMeters } }
    private var duration: TimeInterval { records.reduce(0) { $0 + $1.duration } }
    private var energy: Double { records.compactMap(\.activeEnergyKcal).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOUTES LES ACTIVITÉS ACCESSIBLES")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                HealthHistoryMetric(value: "\(records.count)", label: "séances")
                HealthHistoryMetric(value: healthDistance(distance), label: "distance")
                HealthHistoryMetric(value: healthDuration(duration), label: "temps")
            }

            if energy > 0 {
                Label("\(Int(energy.rounded())) kcal actives", systemImage: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct HealthWorkoutRow: View {
    let record: HealthWorkoutRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: record.activity.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.mint)
                    .frame(width: 34, height: 34)
                    .background(.mint.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(record.activity.label)
                        .font(.headline.weight(.bold))
                    Text(record.startedAt, format: .dateTime.weekday(.abbreviated).day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if record.isWatchTrackerWorkout {
                    Text("TRACKER")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.mint)
                }
            }

            HStack(spacing: 16) {
                HealthHistoryValue(value: healthDistance(record.distanceMeters), label: "Distance")
                HealthHistoryValue(value: healthDuration(record.duration), label: "Temps")
                HealthHistoryValue(
                    value: record.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—",
                    label: "Énergie"
                )
            }

            Label(record.sourceName, systemImage: "square.stack.3d.up.fill")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct HealthWorkoutDetailView: View {
    let record: HealthWorkoutRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: record.activity.symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.mint)
                        .frame(width: 46, height: 46)
                        .background(.mint.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.activity.label)
                            .font(.title2.weight(.bold))
                        Text(record.startedAt, format: .dateTime.day().month().year().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    HealthDetailMetric(title: "DISTANCE", value: healthDistance(record.distanceMeters), symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    HealthDetailMetric(title: "DURÉE", value: healthDuration(record.duration), symbol: "timer")
                    HealthDetailMetric(title: "ÉNERGIE", value: record.activeEnergyKcal.map { String(format: "%.0f kcal", $0) } ?? "—", symbol: "flame.fill")
                    HealthDetailMetric(title: "SOURCE", value: record.sourceName, symbol: "heart.text.square.fill")
                }

                VStack(alignment: .leading, spacing: 7) {
                    Label("Provenance Santé", systemImage: "info.circle.fill")
                        .font(.headline)
                    Text(record.isWatchTrackerWorkout
                         ? "Cette séance existe aussi dans Watch Tracker. Ouvre l’onglet Tracker pour ses détails enrichis, son parcours et sa trace technique."
                         : "Cette séance provient de Santé et peut avoir été enregistrée par Apple Fitness ou une autre app autorisée.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
        }
        .navigationTitle(record.activity.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HealthHistoryMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
    }
}

private struct HealthHistoryValue: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct HealthDetailMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.65)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func healthDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func healthDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0 ? String(format: "%dh%02d", hours, minutes) : "\(minutes) min"
}
