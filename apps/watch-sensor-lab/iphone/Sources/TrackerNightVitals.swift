import Foundation
import HealthKit
import SwiftUI

struct TrackerNightVital: Identifiable, Equatable {
    let id: String
    let title: String
    let value: Double
    let unit: String
    let samples: Int
    let source: String
    let symbol: String
}

struct TrackerNightVitalsSnapshot: Equatable {
    let sleepStart: Date
    let sleepEnd: Date
    let source: String
    let vitals: [TrackerNightVital]
    let generatedAt: Date

    var coverage: Double {
        let expected = 5.0
        return min(1, Double(vitals.count) / expected)
    }
}

final class TrackerNightVitalsReader {
    private let store = HKHealthStore()

    func load(completion: @escaping (TrackerNightVitalsSnapshot?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var read: Set<HKObjectType> = [sleepType]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .appleSleepingWristTemperature,
            .oxygenSaturation,
        ]
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                read.insert(type)
            }
        }

        store.requestAuthorization(toShare: [], read: read) { [weak self] _, _ in
            guard let self else { return }
            self.findLatestSleepWindow(type: sleepType) { window in
                guard let window else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                self.loadVitals(window: window, completion: completion)
            }
        }
    }

    private struct SleepWindow {
        let start: Date
        let end: Date
        let source: String
    }

    private func findLatestSleepWindow(
        type: HKCategoryType,
        completion: @escaping (SleepWindow?) -> Void
    ) {
        let now = Date()
        let start = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -40, to: now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let values = (samples as? [HKCategorySample] ?? []).filter { Self.isAsleep($0.value) }
            guard !values.isEmpty else {
                completion(nil)
                return
            }

            let grouped = Dictionary(grouping: values, by: { $0.sourceRevision.source.name })
            let candidates = grouped.compactMap { source, sourceSamples -> (SleepWindow, TimeInterval)? in
                let intervals = Self.merge(sourceSamples.map { ($0.startDate, $0.endDate) })
                guard let first = intervals.first?.0,
                      let last = intervals.last?.1 else { return nil }
                let total = intervals.reduce(0.0) { $0 + max(0, $1.1.timeIntervalSince($1.0)) }
                guard total >= 3600 else { return nil }
                return (SleepWindow(start: first, end: last, source: source), total)
            }

            completion(candidates.max(by: { $0.1 < $1.1 })?.0)
        }
        store.execute(query)
    }

    private func loadVitals(
        window: SleepWindow,
        completion: @escaping (TrackerNightVitalsSnapshot?) -> Void
    ) {
        let group = DispatchGroup()
        let lock = NSLock()
        var vitals: [TrackerNightVital] = []

        func query(
            id: String,
            title: String,
            identifier: HKQuantityTypeIdentifier,
            unit: HKUnit,
            displayUnit: String,
            symbol: String,
            transform: @escaping (Double) -> Double = { $0 }
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
            group.enter()
            self.medianSample(type: type, unit: unit, start: window.start, end: window.end) { result in
                if let result {
                    let value = transform(result.value)
                    if value.isFinite {
                        lock.lock()
                        vitals.append(
                            TrackerNightVital(
                                id: id,
                                title: title,
                                value: value,
                                unit: displayUnit,
                                samples: result.samples,
                                source: result.source,
                                symbol: symbol
                            )
                        )
                        lock.unlock()
                    }
                }
                group.leave()
            }
        }

        let bpm = HKUnit.count().unitDivided(by: .minute())
        query(id: "heart_rate", title: "FC nocturne", identifier: .heartRate, unit: bpm, displayUnit: "bpm", symbol: "heart.fill")
        query(id: "hrv", title: "VFC nocturne", identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), displayUnit: "ms", symbol: "waveform.path.ecg")
        query(id: "respiratory", title: "Respiration", identifier: .respiratoryRate, unit: bpm, displayUnit: "resp/min", symbol: "lungs.fill")
        query(id: "temperature", title: "Temp. poignet", identifier: .appleSleepingWristTemperature, unit: .degreeCelsius(), displayUnit: "°C", symbol: "thermometer.medium")
        query(id: "oxygen", title: "Oxygène", identifier: .oxygenSaturation, unit: .percent(), displayUnit: "%", symbol: "drop.fill", transform: { $0 * 100 })

        group.notify(queue: .main) {
            let orderedIDs = ["heart_rate", "hrv", "respiratory", "temperature", "oxygen"]
            vitals.sort {
                (orderedIDs.firstIndex(of: $0.id) ?? Int.max) < (orderedIDs.firstIndex(of: $1.id) ?? Int.max)
            }
            completion(
                TrackerNightVitalsSnapshot(
                    sleepStart: window.start,
                    sleepEnd: window.end,
                    source: window.source,
                    vitals: vitals,
                    generatedAt: Date()
                )
            )
        }
    }

    private struct MedianResult {
        let value: Double
        let samples: Int
        let source: String
    }

    private func medianSample(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        completion: @escaping (MedianResult?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            let typed = samples as? [HKQuantitySample] ?? []
            let values = typed.compactMap { sample -> Double? in
                let value = sample.quantity.doubleValue(for: unit)
                return value.isFinite ? value : nil
            }
            guard let median = Self.median(values) else {
                completion(nil)
                return
            }
            let sourceCounts = Dictionary(grouping: typed, by: { $0.sourceRevision.source.name })
                .mapValues(\.count)
            let source = sourceCounts.max(by: { $0.value < $1.value })?.key ?? "Apple Health"
            completion(MedianResult(value: median, samples: values.count, source: source))
        }
        store.execute(query)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func merge(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for interval in sorted {
            if let last = merged.last, interval.0 <= last.1 {
                merged[merged.count - 1] = (last.0, max(last.1, interval.1))
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    private static func isAsleep(_ value: Int) -> Bool {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
             HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
             HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return true
        default:
            return false
        }
    }
}

struct TrackerNightVitalsCard: View {
    @State private var snapshot: TrackerNightVitalsSnapshot?
    @State private var loading = true

    private let reader = TrackerNightVitalsReader()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("VITALS · NUIT")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.indigo)
                    Text("Mesurés pendant ton sommeil")
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.indigo)
            }

            if let snapshot {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(snapshot.vitals) { vital in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Image(systemName: vital.symbol).foregroundStyle(vitalAccent(vital.id))
                                Spacer()
                                Text("\(vital.samples)x")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(vitalText(vital))
                                .font(.headline.weight(.black))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                            Text(vital.title.uppercased())
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text(vital.source)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                        .padding(9)
                        .background(vitalAccent(vital.id).opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                HStack {
                    Text(snapshot.sleepStart.formatted(date: .omitted, time: .shortened))
                    Image(systemName: "arrow.right")
                    Text(snapshot.sleepEnd.formatted(date: .omitted, time: .shortened))
                    Spacer()
                    Text("\(Int((snapshot.coverage * 100).rounded()))% signaux")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text("Valeurs médianes des échantillons Health lisibles dans la fenêtre de sommeil. Elles servent de contexte personnel, pas de diagnostic.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if loading {
                ProgressView("Analyse de la nuit…")
                    .font(.caption)
            } else {
                Text("Pas encore de nuit suffisamment documentée dans Apple Health.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .task { refresh() }
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }

    private func vitalText(_ vital: TrackerNightVital) -> String {
        switch vital.id {
        case "temperature": return String(format: "%.2f %@", vital.value, vital.unit)
        case "respiratory": return String(format: "%.1f %@", vital.value, vital.unit)
        case "oxygen": return String(format: "%.0f%@", vital.value, vital.unit)
        default: return String(format: "%.0f %@", vital.value, vital.unit)
        }
    }

    private func vitalAccent(_ id: String) -> Color {
        switch id {
        case "heart_rate": return .pink
        case "hrv": return .purple
        case "respiratory": return .cyan
        case "temperature": return .orange
        case "oxygen": return .blue
        default: return .mint
        }
    }
}
