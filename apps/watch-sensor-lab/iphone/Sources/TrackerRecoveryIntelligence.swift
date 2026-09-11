import Charts
import Foundation
import HealthKit
import SwiftUI

struct TrackerSleepNight: Identifiable, Equatable {
    let date: Date
    let startedAt: Date
    let endedAt: Date
    let totalSleep: TimeInterval
    let awake: TimeInterval
    let core: TimeInterval
    let deep: TimeInterval
    let rem: TimeInterval
    let unspecified: TimeInterval
    let interruptions: Int
    let source: String

    var id: String { "\(source)-\(date.timeIntervalSince1970)" }

    var window: TimeInterval {
        max(totalSleep, endedAt.timeIntervalSince(startedAt))
    }

    var efficiency: Double {
        guard window > 0 else { return 0 }
        return min(1, max(0, totalSleep / window))
    }
}

struct TrackerRecoveryFactor: Identifiable, Equatable {
    let id: String
    let title: String
    let score: Double?
    let value: String
    let detail: String
    let symbol: String
    let source: String
    let weight: Double
    let confidence: Double
}

struct TrackerRecoverySnapshot: Equatable {
    let score: Double?
    let confidence: Double
    let label: String
    let explanation: String
    let factors: [TrackerRecoveryFactor]
    let currentSleep: TrackerSleepNight?
    let sleepBaselineHours: Double?
    let sleepConsistencyMinutes: Double?
    let sleepDeficit7DaysHours: Double?
    let sleepTrend: [TrackerSleepNight]
    let workloadRatio: Double?
    let generatedAt: Date
}

final class TrackerRecoveryIntelligenceReader {
    private struct DatedValue {
        let date: Date
        let value: Double
        let source: String
    }

    private struct SleepGroupKey: Hashable {
        let source: String
        let night: Date
    }

    private struct SleepCandidate {
        let night: TrackerSleepNight
        let stagedSeconds: TimeInterval
    }

    private let store = HKHealthStore()
    private let calendar = Calendar.autoupdatingCurrent

    func load(completion: @escaping (TrackerRecoverySnapshot) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                completion(Self.emptySnapshot(explanation: "Apple Health n’est pas disponible sur cet appareil."))
            }
            return
        }

        let types = readTypes()
        store.requestAuthorization(toShare: [], read: types) { [weak self] _, _ in
            guard let self else { return }
            self.loadAuthorized(completion: completion)
        }
    }

    private func readTypes() -> Set<HKObjectType> {
        var result: Set<HKObjectType> = [HKObjectType.workoutType()]
        let identifiers: [HKQuantityTypeIdentifier] = [
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .respiratoryRate,
            .appleSleepingWristTemperature,
        ]
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                result.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            result.insert(sleep)
        }
        return result
    }

    private func loadAuthorized(completion: @escaping (TrackerRecoverySnapshot) -> Void) {
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -45, to: now) ?? .distantPast
        let group = DispatchGroup()
        let lock = NSLock()

        var sleepNights: [TrackerSleepNight] = []
        var hrv: [DatedValue] = []
        var restingHR: [DatedValue] = []
        var respiratory: [DatedValue] = []
        var wristTemperature: [DatedValue] = []
        var workouts: [HKWorkout] = []

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            group.enter()
            loadSleepNights(type: sleepType, start: start, end: now) { values in
                lock.lock(); sleepNights = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            group.enter()
            loadDailyValues(type: type, unit: .secondUnit(with: .milli), start: start, end: now) { values in
                lock.lock(); hrv = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            group.enter()
            loadDailyValues(type: type, unit: bpm, start: start, end: now) { values in
                lock.lock(); restingHR = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) {
            let breaths = HKUnit.count().unitDivided(by: .minute())
            group.enter()
            loadDailyValues(type: type, unit: breaths, start: start, end: now) { values in
                lock.lock(); respiratory = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            group.enter()
            loadDailyValues(type: type, unit: .degreeCelsius(), start: start, end: now) { values in
                lock.lock(); wristTemperature = values; lock.unlock(); group.leave()
            }
        }

        group.enter()
        loadWorkouts(start: start, end: now) { values in
            lock.lock(); workouts = values; lock.unlock(); group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            let snapshot = self.makeSnapshot(
                now: now,
                sleepNights: sleepNights,
                hrv: hrv,
                restingHR: restingHR,
                respiratory: respiratory,
                wristTemperature: wristTemperature,
                workouts: workouts
            )
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private func loadDailyValues(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        completion: @escaping ([DatedValue]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { [calendar] _, samples, _ in
            var buckets: [Date: [(Double, String)]] = [:]
            for sample in samples as? [HKQuantitySample] ?? [] {
                guard let value = sample.quantity.trackerDoubleValue(for: unit) else {
                    continue
                }
                let day = calendar.startOfDay(for: sample.endDate)
                buckets[day, default: []].append((value, sample.sourceRevision.source.name))
            }

            let values = buckets.compactMap { day, entries -> DatedValue? in
                let numbers = entries.map(\.0)
                guard let value = Self.median(numbers) else { return nil }
                let source = entries.last?.1 ?? "Apple Health"
                return DatedValue(date: day, value: value, source: source)
            }
            .sorted { $0.date < $1.date }
            completion(values)
        }
        store.execute(query)
    }

    private func loadWorkouts(start: Date, end: Date, completion: @escaping ([HKWorkout]) -> Void) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, samples, _ in
            completion(samples as? [HKWorkout] ?? [])
        }
        store.execute(query)
    }

    private func loadSleepNights(
        type: HKCategoryType,
        start: Date,
        end: Date,
        completion: @escaping ([TrackerSleepNight]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [calendar] _, samples, _ in
            let sleepSamples = samples as? [HKCategorySample] ?? []
            var groups: [SleepGroupKey: [HKCategorySample]] = [:]

            for sample in sleepSamples {
                guard Self.isUsefulSleepValue(sample.value) else { continue }
                let midpoint = sample.startDate.addingTimeInterval(sample.endDate.timeIntervalSince(sample.startDate) / 2)
                let shifted = midpoint.addingTimeInterval(-12 * 3600)
                let night = calendar.startOfDay(for: shifted)
                let key = SleepGroupKey(source: sample.sourceRevision.source.name, night: night)
                groups[key, default: []].append(sample)
            }

            var candidatesByNight: [Date: [SleepCandidate]] = [:]
            for (key, samples) in groups {
                guard let candidate = Self.makeSleepCandidate(key: key, samples: samples) else { continue }
                candidatesByNight[key.night, default: []].append(candidate)
            }

            let nights = candidatesByNight.compactMap { _, candidates -> TrackerSleepNight? in
                candidates.max { lhs, rhs in
                    if abs(lhs.stagedSeconds - rhs.stagedSeconds) > 60 {
                        return lhs.stagedSeconds < rhs.stagedSeconds
                    }
                    return lhs.night.totalSleep < rhs.night.totalSleep
                }?.night
            }
            .sorted { $0.endedAt < $1.endedAt }

            completion(nights)
        }
        store.execute(query)
    }

    private func makeSnapshot(
        now: Date,
        sleepNights: [TrackerSleepNight],
        hrv: [DatedValue],
        restingHR: [DatedValue],
        respiratory: [DatedValue],
        wristTemperature: [DatedValue],
        workouts: [HKWorkout]
    ) -> TrackerRecoverySnapshot {
        let recentSleep = sleepNights.filter { now.timeIntervalSince($0.endedAt) <= 48 * 3600 }.last
        let previousSleep = recentSleep.map { current in
            Array(sleepNights.filter { $0.endedAt < current.startedAt }.suffix(30))
        } ?? Array(sleepNights.suffix(30))

        let sleepBaseline = Self.median(previousSleep.map { $0.totalSleep / 3600 })
        let bedtimeBaseline = Self.median(previousSleep.map { Self.anchoredBedtimeMinutes($0.startedAt) })
        let consistency = recentSleep.flatMap { current -> Double? in
            guard let bedtimeBaseline else { return nil }
            return Self.clockDistanceMinutes(Self.anchoredBedtimeMinutes(current.startedAt), bedtimeBaseline)
        }

        let durationScore: Double? = {
            guard let recentSleep, let sleepBaseline, previousSleep.count >= 5 else { return nil }
            let deltaHours = abs(recentSleep.totalSleep / 3600 - sleepBaseline)
            return Self.clamp(100 - deltaHours * 22, 20, 100)
        }()

        let consistencyScore: Double? = consistency.map { deviation in
            Self.clamp(100 - max(0, deviation - 15) * (100 / 165), 0, 100)
        }

        let continuityScore: Double? = recentSleep.map { night in
            let efficiency = night.efficiency * 100
            let interruptionScore = Self.clamp(100 - Double(night.interruptions) * 9, 30, 100)
            return efficiency * 0.8 + interruptionScore * 0.2
        }

        let sleepScore = Self.weightedScore([
            (durationScore, 0.50),
            (consistencyScore, 0.30),
            (continuityScore, 0.20),
        ])
        let sleepConfidence = min(1, Double(previousSleep.count) / 21.0)

        let hrvFactor = makeStabilityFactor(
            id: "hrv",
            title: "VFC",
            values: hrv,
            unit: "ms",
            digits: 0,
            symbol: "waveform.path.ecg",
            weight: 0.20,
            minimumBaseline: 10,
            preferredBaseline: 21
        )
        let restingFactor = makeStabilityFactor(
            id: "resting_hr",
            title: "FC repos",
            values: restingHR,
            unit: "bpm",
            digits: 0,
            symbol: "heart.fill",
            weight: 0.15,
            minimumBaseline: 10,
            preferredBaseline: 21
        )
        let respiratoryFactor = makeStabilityFactor(
            id: "respiratory",
            title: "Respiration nuit",
            values: respiratory,
            unit: "resp/min",
            digits: 1,
            symbol: "lungs.fill",
            weight: 0.075,
            minimumBaseline: 7,
            preferredBaseline: 14
        )
        let temperatureFactor = makeStabilityFactor(
            id: "wrist_temperature",
            title: "Temp. poignet",
            values: wristTemperature,
            unit: "°C",
            digits: 2,
            symbol: "thermometer.medium",
            weight: 0.075,
            minimumBaseline: 7,
            preferredBaseline: 14
        )

        let sleepFactor = TrackerRecoveryFactor(
            id: "sleep",
            title: "Nuit",
            score: sleepScore,
            value: recentSleep.map { Self.durationText($0.totalSleep) } ?? "—",
            detail: Self.sleepDetail(
                baselineHours: sleepBaseline,
                consistencyMinutes: consistency,
                interruptions: recentSleep?.interruptions
            ),
            symbol: "bed.double.fill",
            source: recentSleep?.source ?? "Apple Health",
            weight: 0.35,
            confidence: recentSleep == nil ? 0 : sleepConfidence
        )

        let workload = makeWorkloadFactor(now: now, workouts: workouts)
        let factors = [sleepFactor, hrvFactor, restingFactor, workload.factor, respiratoryFactor, temperatureFactor]

        let weighted = factors.compactMap { factor -> (Double, Double)? in
            guard let score = factor.score, factor.confidence > 0 else { return nil }
            return (score, factor.weight * factor.confidence)
        }
        let score = Self.weightedScore(weighted)
        let totalWeight = factors.reduce(0) { $0 + $1.weight }
        let coveredWeight = factors.reduce(0) { $0 + $1.weight * min(1, max(0, $1.confidence)) }
        let confidence = totalWeight > 0 ? Self.clamp(coveredWeight / totalWeight * 100, 0, 100) : 0

        let label = Self.recoveryLabel(score: score, confidence: confidence)
        let explanation: String
        if score == nil {
            explanation = "Collecte en cours : l’indice apparaît lorsque suffisamment de données Apple Health personnelles sont lisibles."
        } else {
            explanation = "Indice Tracker calculé localement à partir de tes propres repères. Les facteurs absents sont ignorés plutôt que remplacés par zéro."
        }

        let deficit: Double? = sleepBaseline.map { baseline in
            Array(sleepNights.suffix(7)).reduce(0.0) { partial, night in
                partial + max(0, baseline - night.totalSleep / 3600)
            }
        }

        return TrackerRecoverySnapshot(
            score: score,
            confidence: confidence,
            label: label,
            explanation: explanation,
            factors: factors,
            currentSleep: recentSleep,
            sleepBaselineHours: sleepBaseline,
            sleepConsistencyMinutes: consistency,
            sleepDeficit7DaysHours: deficit,
            sleepTrend: Array(sleepNights.suffix(14)),
            workloadRatio: workload.ratio,
            generatedAt: now
        )
    }

    private func makeStabilityFactor(
        id: String,
        title: String,
        values: [DatedValue],
        unit: String,
        digits: Int,
        symbol: String,
        weight: Double,
        minimumBaseline: Int,
        preferredBaseline: Int
    ) -> TrackerRecoveryFactor {
        guard let latest = values.last else {
            return TrackerRecoveryFactor(
                id: id,
                title: title,
                score: nil,
                value: "—",
                detail: "Pas de donnée lisible",
                symbol: symbol,
                source: "Apple Health",
                weight: weight,
                confidence: 0
            )
        }

        let baselineValues = Array(values.dropLast().suffix(30)).map(\.value)
        let baseline = Self.median(baselineValues)
        let mad = baseline.flatMap { center in Self.median(baselineValues.map { abs($0 - center) }) }
        let enough = baselineValues.count >= minimumBaseline

        let score: Double?
        let detail: String
        if let baseline, enough {
            let robustScale = max((mad ?? 0) * 1.4826, max(abs(baseline) * 0.04, id == "wrist_temperature" ? 0.08 : 0.5))
            let deviation = abs(latest.value - baseline) / robustScale
            score = Self.clamp(100 - min(3.5, deviation) * 17, 35, 100)
            let delta = latest.value - baseline
            detail = String(format: "repère %.1f · écart %+.1f", baseline, delta)
        } else {
            score = nil
            detail = "Repère personnel en construction"
        }

        let format = "% .\(digits)f"
        let cleanValue = String(format: format, latest.value).trimmingCharacters(in: .whitespaces)
        return TrackerRecoveryFactor(
            id: id,
            title: title,
            score: score,
            value: "\(cleanValue) \(unit)",
            detail: detail,
            symbol: symbol,
            source: latest.source,
            weight: weight,
            confidence: enough ? min(1, Double(baselineValues.count) / Double(preferredBaseline)) : 0
        )
    }

    private func makeWorkloadFactor(now: Date, workouts: [HKWorkout]) -> (factor: TrackerRecoveryFactor, ratio: Double?) {
        let recentStart = calendar.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        let referenceStart = calendar.date(byAdding: .day, value: -35, to: now) ?? .distantPast
        let recent = workouts.filter { $0.startDate >= recentStart && $0.startDate <= now }
        let reference = workouts.filter { $0.startDate >= referenceStart && $0.startDate < recentStart }
        let recentHours = recent.reduce(0.0) { $0 + $1.duration } / 3600
        let referenceWeeklyHours = reference.reduce(0.0) { $0 + $1.duration } / 3600 / 4

        guard referenceWeeklyHours >= 0.25 else {
            return (
                TrackerRecoveryFactor(
                    id: "workload",
                    title: "Pression entraînement",
                    score: nil,
                    value: String(format: "%.1f h / 7j", recentHours),
                    detail: "Référence 28j insuffisante",
                    symbol: "figure.run",
                    source: "Apple Health",
                    weight: 0.15,
                    confidence: 0
                ),
                nil
            )
        }

        let ratio = recentHours / referenceWeeklyHours
        let score: Double
        switch ratio {
        case ...1.10:
            score = 100
        case ...1.50:
            score = 100 - (ratio - 1.10) / 0.40 * 25
        case ...2.00:
            score = 75 - (ratio - 1.50) / 0.50 * 30
        default:
            score = 35
        }

        let detail = String(format: "%.2fx ta moyenne hebdo précédente", ratio)
        return (
            TrackerRecoveryFactor(
                id: "workload",
                title: "Pression entraînement",
                score: score,
                value: String(format: "%.1f h / 7j", recentHours),
                detail: detail,
                symbol: "figure.run",
                source: "Apple Health",
                weight: 0.15,
                confidence: min(1, Double(reference.count) / 8.0 + 0.35)
            ),
            ratio
        )
    }

    private static func makeSleepCandidate(key: SleepGroupKey, samples: [HKCategorySample]) -> SleepCandidate? {
        let asleepSamples = samples.filter { isAsleepValue($0.value) }
        guard !asleepSamples.isEmpty else { return nil }

        let asleepIntervals = mergeIntervals(asleepSamples.map { ($0.startDate, $0.endDate) })
        let totalSleep = asleepIntervals.reduce(0.0) { $0 + max(0, $1.1.timeIntervalSince($1.0)) }
        guard totalSleep >= 3600, totalSleep <= 14 * 3600,
              let start = asleepIntervals.first?.0,
              let end = asleepIntervals.last?.1 else { return nil }

        let awakeIntervals = mergeIntervals(
            samples
                .filter { $0.value == HKCategoryValueSleepAnalysis.awake.rawValue }
                .map { (max($0.startDate, start), min($0.endDate, end)) }
                .filter { $0.1 > $0.0 }
        )
        let awake = awakeIntervals.reduce(0.0) { $0 + $1.1.timeIntervalSince($1.0) }
        let interruptions = awakeIntervals.filter { $0.1.timeIntervalSince($0.0) >= 120 }.count

        func stageSeconds(_ stage: HKCategoryValueSleepAnalysis) -> TimeInterval {
            samples
                .filter { $0.value == stage.rawValue }
                .reduce(0.0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate)) }
        }

        let core = stageSeconds(.asleepCore)
        let deep = stageSeconds(.asleepDeep)
        let rem = stageSeconds(.asleepREM)
        let unspecified = stageSeconds(.asleepUnspecified)
        let staged = core + deep + rem

        return SleepCandidate(
            night: TrackerSleepNight(
                date: key.night,
                startedAt: start,
                endedAt: end,
                totalSleep: totalSleep,
                awake: awake,
                core: min(totalSleep, core),
                deep: min(totalSleep, deep),
                rem: min(totalSleep, rem),
                unspecified: min(totalSleep, unspecified),
                interruptions: interruptions,
                source: key.source
            ),
            stagedSeconds: staged
        )
    }

    private static func isUsefulSleepValue(_ value: Int) -> Bool {
        isAsleepValue(value) || value == HKCategoryValueSleepAnalysis.awake.rawValue
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
        let sorted = intervals
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
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

    private static func anchoredBedtimeMinutes(_ date: Date) -> Double {
        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
        var minute = Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        if minute < 12 * 60 { minute += 24 * 60 }
        return minute
    }

    private static func clockDistanceMinutes(_ lhs: Double, _ rhs: Double) -> Double {
        let raw = abs(lhs - rhs)
        return min(raw, abs(1440 - raw))
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

    private static func weightedScore(_ values: [(Double?, Double)]) -> Double? {
        let available = values.compactMap { value, weight -> (Double, Double)? in
            guard let value, value.isFinite, weight > 0 else { return nil }
            return (value, weight)
        }
        let weight = available.reduce(0) { $0 + $1.1 }
        guard weight > 0 else { return nil }
        return available.reduce(0) { $0 + $1.0 * $1.1 } / weight
    }

    private static func weightedScore(_ values: [(Double, Double)]) -> Double? {
        let weight = values.reduce(0) { $0 + $1.1 }
        guard weight > 0 else { return nil }
        return values.reduce(0) { $0 + $1.0 * $1.1 } / weight
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value))
    }

    private static func recoveryLabel(score: Double?, confidence: Double) -> String {
        guard let score, confidence >= 25 else { return "Repères en construction" }
        switch score {
        case 85...: return "Signaux très stables"
        case 70...: return "Équilibre favorable"
        case 55...: return "Équilibre variable"
        default: return "Récupération à privilégier"
        }
    }

    private static func sleepDetail(
        baselineHours: Double?,
        consistencyMinutes: Double?,
        interruptions: Int?
    ) -> String {
        var parts: [String] = []
        if let baselineHours { parts.append(String(format: "repère %.1fh", baselineHours)) }
        if let consistencyMinutes { parts.append("±\(Int(consistencyMinutes.rounded())) min coucher") }
        if let interruptions { parts.append("\(interruptions) réveil\(interruptions == 1 ? "" : "s")") }
        return parts.isEmpty ? "Analyse nocturne en construction" : parts.joined(separator: " · ")
    }

    private static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return String(format: "%dh%02d", minutes / 60, minutes % 60)
    }

    private static func emptySnapshot(explanation: String) -> TrackerRecoverySnapshot {
        TrackerRecoverySnapshot(
            score: nil,
            confidence: 0,
            label: "Indisponible",
            explanation: explanation,
            factors: [],
            currentSleep: nil,
            sleepBaselineHours: nil,
            sleepConsistencyMinutes: nil,
            sleepDeficit7DaysHours: nil,
            sleepTrend: [],
            workloadRatio: nil,
            generatedAt: Date()
        )
    }
}

struct TrackerRecoveryIntelligenceCard: View {
    @State private var snapshot: TrackerRecoverySnapshot?
    @State private var loading = true

    private let reader = TrackerRecoveryIntelligenceReader()

    var body: some View {
        NavigationLink {
            if let snapshot {
                TrackerRecoveryDetailView(snapshot: snapshot)
            } else {
                ProgressView("Analyse Apple Health…")
                    .navigationTitle("Indice Tracker")
            }
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("INTELLIGENCE TRACKER")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.cyan)
                        Text(snapshot?.label ?? (loading ? "Analyse en cours" : "Repères en construction"))
                            .font(.title3.weight(.black))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                    recoveryGauge
                }

                if let snapshot {
                    HStack(spacing: 8) {
                        miniFactor(snapshot, id: "sleep")
                        miniFactor(snapshot, id: "hrv")
                        miniFactor(snapshot, id: "workload")
                    }
                    Text(snapshot.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                HStack {
                    Label("Score explicable", systemImage: "list.bullet.clipboard.fill")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(17)
            .background(
                LinearGradient(
                    colors: [.cyan.opacity(0.16), .indigo.opacity(0.12), .white.opacity(0.045)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .task { refresh() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var recoveryGauge: some View {
        if let score = snapshot?.score {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, max(0, score / 100)))
                    .stroke(recoveryAccent(score), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(score.rounded()))")
                    .font(.headline.weight(.black))
                    .monospacedDigit()
            }
            .frame(width: 58, height: 58)
        } else {
            Image(systemName: "sparkles")
                .font(.title2.weight(.bold))
                .foregroundStyle(.cyan)
                .frame(width: 58, height: 58)
                .background(.cyan.opacity(0.10), in: Circle())
        }
    }

    private func miniFactor(_ snapshot: TrackerRecoverySnapshot, id: String) -> some View {
        let factor = snapshot.factors.first { $0.id == id }
        return VStack(alignment: .leading, spacing: 3) {
            Image(systemName: factor?.symbol ?? "circle.dashed")
                .foregroundStyle(factor.map { factorAccent($0.score) } ?? .secondary)
            Text(factor?.value ?? "—")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(factor?.title.uppercased() ?? "—")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var accessibilitySummary: String {
        guard let snapshot else { return "Intelligence Tracker, analyse en cours" }
        if let score = snapshot.score {
            return "Indice Tracker \(Int(score.rounded())) sur 100, \(snapshot.label), confiance \(Int(snapshot.confidence.rounded())) pour cent"
        }
        return "Indice Tracker, repères personnels en construction"
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }
}

struct TrackerRecoveryDetailView: View {
    let snapshot: TrackerRecoverySnapshot

    @State private var selectedSleepDate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                factorGrid
                sleepLab
                confidenceCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.indigo.opacity(0.10), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Indice Tracker")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.08), lineWidth: 10)
                if let score = snapshot.score {
                    Circle()
                        .trim(from: 0, to: min(1, max(0, score / 100)))
                        .stroke(recoveryAccent(score), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(score.rounded()))")
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                } else {
                    Image(systemName: "ellipsis")
                        .font(.title2.weight(.black))
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 5) {
                Text(snapshot.label)
                    .font(.title2.weight(.black))
                Text("Confiance \(Int(snapshot.confidence.rounded()))%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
                Text(snapshot.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var factorGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("POURQUOI CET INDICE")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                Spacer()

                Label(
                    "glisse",
                    systemImage: "arrow.left.and.right"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
            }

            TabView {
                ForEach(snapshot.factors) { factor in
                    recoveryFactorCard(factor)
                        .padding(.horizontal, 1)
                }
            }
            .frame(height: 162)
            .tabViewStyle(
                .page(indexDisplayMode: .automatic)
            )
        }
    }

    private func recoveryFactorCard(
        _ factor: TrackerRecoveryFactor
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: factor.symbol)
                    .foregroundStyle(
                        factorAccent(factor.score)
                    )

                Spacer()

                if let score = factor.score {
                    Text("\(Int(score.rounded()))")
                        .font(.caption.weight(.black))
                        .monospacedDigit()
                        .foregroundStyle(
                            factorAccent(factor.score)
                        )
                }
            }

            Text(factor.title.uppercased())
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(.secondary)

            Text(factor.value)
                .font(.title3.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)

            Text(factor.detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)

            Text(factor.source)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 128,
            alignment: .leading
        )
        .padding(13)
        .background(
            factorAccent(factor.score).opacity(0.07),
            in: RoundedRectangle(
                cornerRadius: 18,
                style: .continuous
            )
        )
    }

    private var selectedSleepTrendNight: TrackerSleepNight? {
        guard let selectedSleepDate else {
            return nil
        }

        return snapshot.sleepTrend.min {
            abs(
                $0.endedAt.timeIntervalSince(
                    selectedSleepDate
                )
            )
            <
            abs(
                $1.endedAt.timeIntervalSince(
                    selectedSleepDate
                )
            )
        }
    }

    @ViewBuilder
    private var sleepLab: some View {
        if let night = snapshot.currentSleep {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SOMMEIL · LAB")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        Text("Ta nuit, sans score opaque")
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    Image(systemName: "moon.stars.fill").foregroundStyle(.indigo)
                }

                HStack(spacing: 8) {
                    sleepMetric("TOTAL", recoveryDuration(night.totalSleep), .indigo)
                    sleepMetric("CONTINUITÉ", "\(Int((night.efficiency * 100).rounded()))%", .cyan)
                    sleepMetric("RÉVEILS", "\(night.interruptions)", .orange)
                }

                if night.core + night.deep + night.rem > 0 {
                    GeometryReader { proxy in
                        let total = max(1, night.core + night.deep + night.rem)
                        HStack(spacing: 2) {
                            Rectangle().fill(Color.cyan.opacity(0.75)).frame(width: proxy.size.width * night.core / total)
                            Rectangle().fill(Color.indigo).frame(width: proxy.size.width * night.deep / total)
                            Rectangle().fill(Color.purple).frame(width: proxy.size.width * night.rem / total)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 12)

                    HStack(spacing: 12) {
                        sleepLegend("Core", night.core, .cyan)
                        sleepLegend("Profond", night.deep, .indigo)
                        sleepLegend("REM", night.rem, .purple)
                    }
                }

                if !snapshot.sleepTrend.isEmpty {
                    Chart(snapshot.sleepTrend) { item in
                        BarMark(
                            x: .value(
                                "Nuit",
                                item.endedAt,
                                unit: .day
                            ),
                            y: .value(
                                "Heures",
                                item.totalSleep / 3600
                            )
                        )
                        .foregroundStyle(
                            item.id == night.id
                                ? Color.cyan
                                : Color.indigo.opacity(0.55)
                        )
                        .cornerRadius(3)

                        if
                            item.id
                                == selectedSleepTrendNight?.id
                        {
                            RuleMark(
                                x: .value(
                                    "Sélection",
                                    item.endedAt
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(0.45)
                            )
                            .annotation(
                                position: .top,
                                spacing: 4
                            ) {
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    Text(
                                        item.endedAt.formatted(
                                            date: .abbreviated,
                                            time: .omitted
                                        )
                                    )
                                    .font(
                                        .caption2.weight(.black)
                                    )

                                    Text(
                                        recoveryDuration(
                                            item.totalSleep
                                        )
                                    )
                                    .font(
                                        .caption.weight(.black)
                                    )
                                    .foregroundStyle(.cyan)
                                    .monospacedDigit()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    .ultraThinMaterial,
                                    in: RoundedRectangle(
                                        cornerRadius: 9,
                                        style: .continuous
                                    )
                                )
                                .allowsHitTesting(false)
                            }
                        }

                        if let baseline = snapshot.sleepBaselineHours {
                            RuleMark(
                                y: .value(
                                    "Repère",
                                    baseline
                                )
                            )
                            .foregroundStyle(
                                .white.opacity(0.35)
                            )
                            .lineStyle(
                                StrokeStyle(
                                    lineWidth: 1,
                                    dash: [4, 4]
                                )
                            )
                        }
                    }
                    .chartXSelection(
                        value: $selectedSleepDate
                    )
                    .frame(height: 150)
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(.white.opacity(0.05))
                            AxisValueLabel()
                        }
                    }
                }

                HStack(spacing: 9) {
                    if let baseline = snapshot.sleepBaselineHours {
                        sleepMetric("REPÈRE", String(format: "%.1fh", baseline), .mint)
                    }
                    if let consistency = snapshot.sleepConsistencyMinutes {
                        sleepMetric("RÉGULARITÉ", "±\(Int(consistency.rounded()))m", .cyan)
                    }
                    if let deficit = snapshot.sleepDeficit7DaysHours {
                        sleepMetric("ÉCART 7J", deficit > 0.05 ? String(format: "-%.1fh", deficit) : "0h", .orange)
                    }
                }

                Text("Les phases, réveils et durées proviennent des échantillons Apple Health lisibles. L’Indice Tracker utilise ton historique personnel ; il ne reproduit pas le Sleep Score Apple et ne constitue pas un diagnostic médical.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(15)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var confidenceCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Confiance et couverture", systemImage: "checkmark.shield.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.mint)
            ProgressView(value: snapshot.confidence, total: 100)
                .tint(.mint)
            Text("La confiance augmente avec le nombre de nuits et de jours disponibles pour construire tes repères. Un facteur manquant réduit la confiance au lieu d’être inventé ou remplacé par une moyenne de population.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(15)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func sleepMetric(_ label: String, _ value: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.black))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(8)
        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func sleepLegend(_ label: String, _ seconds: TimeInterval, _ accent: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text("\(label) \(recoveryDuration(seconds))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private func recoveryAccent(_ score: Double) -> Color {
    switch score {
    case 85...: return .mint
    case 70...: return .cyan
    case 55...: return .orange
    default: return .pink
    }
}

private func factorAccent(_ score: Double?) -> Color {
    guard let score else { return .secondary }
    return recoveryAccent(score)
}

private func recoveryDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}
