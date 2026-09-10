import Charts
import HealthKit
import SwiftUI

struct HealthEnergyTimelinePoint: Identifiable, Equatable {
    let timestamp: Date
    let cumulativeKcal: Double
    var id: Date { timestamp }
}

final class HealthEnergyTimelineLoader {
    private let healthStore = HKHealthStore()

    func load(for summary: TrackerSummary, completion: @escaping ([HealthEnergyTimelinePoint]) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion([])
            return
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: summary.startedAt,
            end: summary.endedAt,
            options: [.strictStartDate, .strictEndDate]
        )
        var interval = DateComponents()
        interval.second = 30

        let query = HKStatisticsCollectionQuery(
            quantityType: energyType,
            quantitySamplePredicate: predicate,
            options: .cumulativeSum,
            anchorDate: summary.startedAt,
            intervalComponents: interval
        )
        query.initialResultsHandler = { _, collection, _ in
            guard let collection else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            var points: [HealthEnergyTimelinePoint] = []
            var cumulative = 0.0
            collection.enumerateStatistics(from: summary.startedAt, to: summary.endedAt) { statistics, _ in
                if let quantity = statistics.sumQuantity() {
                    cumulative += max(0, quantity.doubleValue(for: .kilocalorie()))
                }
                points.append(
                    HealthEnergyTimelinePoint(
                        timestamp: min(statistics.endDate, summary.endedAt),
                        cumulativeKcal: cumulative
                    )
                )
            }
            DispatchQueue.main.async { completion(points) }
        }
        healthStore.execute(query)
    }
}

struct HealthEnergyTimelineView: View {
    let summary: TrackerSummary

    @State private var points: [HealthEnergyTimelinePoint] = []
    @State private var loaded = false
    private let loader = HealthEnergyTimelineLoader()

    var body: some View {
        Group {
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("CALORIES CUMULÉES", systemImage: "flame.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("kcal")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Chart(points) { point in
                        AreaMark(
                            x: .value("Temps", point.timestamp),
                            y: .value("Calories", point.cumulativeKcal)
                        )
                        LineMark(
                            x: .value("Temps", point.timestamp),
                            y: .value("Calories", point.cumulativeKcal)
                        )
                    }
                    .frame(height: 130)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.hour().minute())
                        }
                    }
                    Text("Progression reconstruite depuis les échantillons d’énergie active HealthKit associés à la fenêtre de l’activité.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if loaded {
                EmptyView()
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Chargement de la progression calories…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            loader.load(for: summary) { values in
                points = values
                loaded = true
            }
        }
    }
}
