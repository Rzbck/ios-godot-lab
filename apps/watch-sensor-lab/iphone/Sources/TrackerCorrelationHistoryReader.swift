import Foundation
import HealthKit

struct TrackerCorrelationHistorySnapshot {
    let sleepHRVPoints: [TrackerCorrelationPoint]
    let sleepRestingHeartRatePoints: [TrackerCorrelationPoint]
    let trainingSleepPoints: [TrackerCorrelationPoint]
}

final class TrackerCorrelationHistoryReader {
    private struct SleepGroupKey: Hashable {
        let source: String
        let night: Date
    }

    private struct SleepNight {
        let endedAt: Date
        let totalSleep: TimeInterval
        let stagedSeconds: TimeInterval
    }

    private struct DailyValue {
        let date: Date
        let value: Double
    }

    private let store = HKHealthStore()
    private let workoutReader = HealthWorkoutHistoryReader()
    private let calendar = Calendar.autoupdatingCurrent

    func load(days: Int, completion: @escaping (TrackerCorrelationHistorySnapshot) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                completion(Self.emptySnapshot)
            }
            return
        }

        let boundedDays = min(90, max(30, days))
        var readTypes: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleep)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            readTypes.insert(hrv)
        }
        if let resting = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            readTypes.insert(resting)
        }

        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, _ in
            guard let self else { return }
            self.loadAuthorized(days: boundedDays, completion: completion)
        }
    }

    private func loadAuthorized(days: Int, completion: @escaping (TrackerCorrelationHistorySnapshot) -> Void) {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -days, to: now) ?? .distantPast
        let group = DispatchGroup()
        let lock = NSLock()

        var sleep: [SleepNight] = []
        var hrv: [DailyValue] = []
        var resting: [DailyValue] = []
        var workouts: [HealthWorkoutRecord] = []

        if let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            group.enter()
            loadSleep(type: type, start: start, end: now) { values in
                lock.lock(); sleep = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            loadDailyMedian(type: type, unit: .secondUnit(with: .milli), start: start, end: now) { values in
                lock.lock(); hrv = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            let bpm = HKUnit.count().unitDivided(by: .minute())
            loadDailyMedian(type: type, unit: bpm, start: start, end: now) { values in
                lock.lock(); resting = values; lock.unlock(); group.leave()
            }
        }

        group.enter()
        workoutReader.loadAll { values in
            lock.lock(); workouts = values.filter { $0.startedAt >= start && $0.startedAt <= now }; lock.unlock(); group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let snapshot = TrackerCorrelationHistorySnapshot(
                sleepHRVPoints: self.pairSleepWithHealth(sleep: sleep, health: hrv),
                sleepRestingHeartRatePoints: self.pairSleepWithHealth(sleep: sleep, health: resting),
                trainingSleepPoints: self.pairTrainingWithSleep(sleep: sleep, workouts: workouts)
            )
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private func loadDailyMedian(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        completion: @escaping ([DailyValue]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [calendar] _, samples, _ in
            var buckets: [Date: [Double]] = [:]
            for sample in samples as? [HKQuantitySample] ?? [] {
                guard let value = sample.quantity.trackerDoubleValue(for: unit) else {
                    continue
                }
                let day = calendar.startOfDay(for: sample.endDate)
                buckets[day, default: []].append(value)
            }

            let values = buckets.compactMap { day, entries -> DailyValue? in
                guard let median = Self.median(entries) else { return nil }
                return DailyValue(date: day, value: median)
            }
            .sorted { $0.date < $1.date }
            completion(values)
        }
        store.execute(query)
    }

    private func loadSleep(
        type: HKCategoryType,
        start: Date,
        end: Date,
        completion: @escaping ([SleepNight]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [calendar] _, samples, _ in
            let sleepSamples = (samples as? [HKCategorySample] ?? []).filter {
                Self.isAsleepValue($0.value)
            }
            var groups: [SleepGroupKey: [HKCategorySample]] = [:]

            for sample in sleepSamples {
                let midpoint = sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
                let shifted = midpoint.addingTimeInterval(-12 * 3600)
                let night = calendar.startOfDay(for: shifted)
                let key = SleepGroupKey(source: sample.sourceRevision.source.name, night: night)
                groups[key, default: []].append(sample)
            }

            var candidatesByNight: [Date: [SleepNight]] = [:]
            for (key, values) in groups {
                guard let night = Self.makeSleepNight(samples: values) else { continue }
                candidatesByNight[key.night, default: []].append(night)
            }

            let nights = candidatesByNight.compactMap { _, candidates -> SleepNight? in
                candidates.max { lhs, rhs in
                    if abs(lhs.stagedSeconds - rhs.stagedSeconds) > 60 {
                        return lhs.stagedSeconds < rhs.stagedSeconds
                    }
                    return lhs.totalSleep < rhs.totalSleep
                }
            }
            .sorted { $0.endedAt < $1.endedAt }
            completion(nights)
        }
        store.execute(query)
    }

    private func pairSleepWithHealth(sleep: [SleepNight], health: [DailyValue]) -> [TrackerCorrelationPoint] {
        sleep.compactMap { night in
            let targetDay = calendar.startOfDay(for: night.endedAt)
            guard let value = health.first(where: { calendar.isDate($0.date, inSameDayAs: targetDay) }) else {
                return nil
            }
            return TrackerCorrelationPoint(date: targetDay, x: night.totalSleep / 3600, y: value.value)
        }
        .sorted { $0.date < $1.date }
    }

    private func pairTrainingWithSleep(
        sleep: [SleepNight],
        workouts: [HealthWorkoutRecord]
    ) -> [TrackerCorrelationPoint] {
        sleep.compactMap { night in
            let sleepDay = calendar.startOfDay(for: night.endedAt)
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: sleepDay) else {
                return nil
            }
            let minutes = workouts
                .filter { $0.startedAt >= previousDay && $0.startedAt < sleepDay }
                .reduce(0.0) { $0 + $1.duration } / 60
            return TrackerCorrelationPoint(date: sleepDay, x: minutes, y: night.totalSleep / 3600)
        }
        .sorted { $0.date < $1.date }
    }

    private static func makeSleepNight(samples: [HKCategorySample]) -> SleepNight? {
        let intervals = mergeIntervals(samples.map { ($0.startDate, $0.endDate) })
        let total = intervals.reduce(0.0) { $0 + max(0, $1.1.timeIntervalSince($1.0)) }
        guard total >= 3600, total <= 14 * 3600, let endedAt = intervals.last?.1 else { return nil }

        let staged = samples
            .filter {
                $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            }
            .reduce(0.0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) }

        return SleepNight(endedAt: endedAt, totalSleep: total, stagedSeconds: staged)
    }

    private static func isAsleepValue(_ value: Int) -> Bool {
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

    private static func mergeIntervals(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
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

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static let emptySnapshot = TrackerCorrelationHistorySnapshot(
        sleepHRVPoints: [],
        sleepRestingHeartRatePoints: [],
        trainingSleepPoints: []
    )
}
