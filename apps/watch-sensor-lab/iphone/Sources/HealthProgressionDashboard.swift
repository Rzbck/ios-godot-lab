import Charts
import Foundation
import HealthKit
import SwiftUI

struct HealthTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct HealthReading: Equatable {
    let value: Double
    let date: Date
    let source: String
}

struct HealthProgressionData: Equatable {
    var restingHeartRate: HealthReading?
    var restingHeartRateBaseline: Double?
    var restingHeartRateTrend: [HealthTrendPoint] = []
    var hrvSDNN: HealthReading?
    var hrvBaseline: Double?
    var hrvTrend: [HealthTrendPoint] = []
    var vo2Max: HealthReading?
    var sleepHours: Double?
    var sleepSource: String?
    var stepsToday: Double?
    var activeEnergyToday: Double?
    var exerciseMinutesToday: Double?
    var note: String?

    static let empty = HealthProgressionData()
}

final class HealthProgressionReader {
    private let store = HKHealthStore()

    private var bpm: HKUnit {
        HKUnit.count().unitDivided(by: HKUnit.minute())
    }

    func load(completion: @escaping (HealthProgressionData) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(HealthProgressionData(note: "Santé n’est pas disponible sur cet appareil."))
            return
        }

        let readTypes = healthReadTypes()
        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    completion(HealthProgressionData(note: "Impossible de demander l’accès Santé : \(error.localizedDescription)"))
                }
                return
            }
            self.loadAuthorized(completion: completion)
        }
    }

    private func healthReadTypes() -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .vo2Max,
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
        ]
        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    private func loadAuthorized(completion: @escaping (HealthProgressionData) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var data = HealthProgressionData.empty
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let start28 = calendar.date(byAdding: .day, value: -28, to: now) ?? .distantPast
        let start14 = calendar.date(byAdding: .day, value: -14, to: now) ?? .distantPast

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            group.enter()
            latestQuantity(type: type, unit: bpm, since: start28) { reading in
                lock.lock(); data.restingHeartRate = reading; lock.unlock(); group.leave()
            }
            group.enter()
            averageQuantity(type: type, unit: bpm, since: start28) { value in
                lock.lock(); data.restingHeartRateBaseline = value; lock.unlock(); group.leave()
            }
            group.enter()
            dailyTrend(type: type, unit: bpm, since: start14) { points in
                lock.lock(); data.restingHeartRateTrend = points; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let unit = HKUnit.secondUnit(with: .milli)
            group.enter()
            latestQuantity(type: type, unit: unit, since: start28) { reading in
                lock.lock(); data.hrvSDNN = reading; lock.unlock(); group.leave()
            }
            group.enter()
            averageQuantity(type: type, unit: unit, since: start28) { value in
                lock.lock(); data.hrvBaseline = value; lock.unlock(); group.leave()
            }
            group.enter()
            dailyTrend(type: type, unit: unit, since: start14) { points in
                lock.lock(); data.hrvTrend = points; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            group.enter()
            latestQuantity(type: type, unit: HKUnit(from: "ml/kg*min"), since: calendar.date(byAdding: .month, value: -6, to: now) ?? .distantPast) { reading in
                lock.lock(); data.vo2Max = reading; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            group.enter()
            sumQuantity(type: type, unit: .count(), start: today, end: now) { value in
                lock.lock(); data.stepsToday = value; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            group.enter()
            sumQuantity(type: type, unit: .kilocalorie(), start: today, end: now) { value in
                lock.lock(); data.activeEnergyToday = value; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime) {
            group.enter()
            sumQuantity(type: type, unit: .minute(), start: today, end: now) { value in
                lock.lock(); data.exerciseMinutesToday = value; lock.unlock(); group.leave()
            }
        }

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            group.enter()
            loadRecentSleep(type: sleepType, now: now) { hours, source in
                lock.lock()
                data.sleepHours = hours
                data.sleepSource = source
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            if data.restingHeartRate == nil,
               data.hrvSDNN == nil,
               data.vo2Max == nil,
               data.sleepHours == nil,
               data.stepsToday == nil,
               data.activeEnergyToday == nil,
               data.exerciseMinutesToday == nil {
                data.note = "Aucune donnée Santé lisible pour le moment. Certaines données peuvent être absentes, non partagées avec Watch Tracker ou non produites par tes appareils."
            } else {
                data.note = "Données lues depuis Apple Health. Les comparaisons utilisent tes propres valeurs récentes et ne constituent pas un diagnostic médical."
            }
            completion(data)
        }
    }

    private func latestQuantity(
        type: HKQuantityType,
        unit: HKUnit,
        since start: Date,
        completion: @escaping (HealthReading?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            let value = sample.quantity.doubleValue(for: unit)
            guard value.isFinite else {
                completion(nil)
                return
            }
            completion(HealthReading(value: value, date: sample.endDate, source: sample.sourceRevision.source.name))
        }
        store.execute(query)
    }

    private func averageQuantity(
        type: HKQuantityType,
        unit: HKUnit,
        since start: Date,
        completion: @escaping (Double?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage) { _, statistics, _ in
            let value = statistics?.averageQuantity()?.doubleValue(for: unit)
            completion(value?.isFinite == true ? value : nil)
        }
        store.execute(query)
    }

    private func sumQuantity(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        completion: @escaping (Double?) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
            let value = statistics?.sumQuantity()?.doubleValue(for: unit)
            completion(value?.isFinite == true ? value : nil)
        }
        store.execute(query)
    }

    private func dailyTrend(
        type: HKQuantityType,
        unit: HKUnit,
        since start: Date,
        completion: @escaping ([HealthTrendPoint]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
            let calendar = Calendar.autoupdatingCurrent
            var buckets: [Date: (sum: Double, count: Int)] = [:]
            for sample in samples as? [HKQuantitySample] ?? [] {
                let value = sample.quantity.doubleValue(for: unit)
                guard value.isFinite else { continue }
                let day = calendar.startOfDay(for: sample.endDate)
                let existing = buckets[day] ?? (0, 0)
                buckets[day] = (existing.sum + value, existing.count + 1)
            }
            let points = buckets
                .map { day, bucket in HealthTrendPoint(date: day, value: bucket.sum / Double(bucket.count)) }
                .sorted { $0.date < $1.date }
            completion(points)
        }
        store.execute(query)
    }

    private func loadRecentSleep(
        type: HKCategoryType,
        now: Date,
        completion: @escaping (Double?, String?) -> Void
    ) {
        let start = Calendar.autoupdatingCurrent.date(byAdding: .hour, value: -36, to: now) ?? .distantPast
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let asleep = (samples as? [HKCategorySample] ?? []).filter { sample in
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                     HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    return true
                default:
                    return false
                }
            }
            guard !asleep.isEmpty else {
                completion(nil, nil)
                return
            }

            let intervals = asleep
                .map { ($0.startDate, $0.endDate) }
                .sorted { $0.0 < $1.0 }
            var merged: [(Date, Date)] = []
            for interval in intervals {
                if let last = merged.last, interval.0 <= last.1 {
                    merged[merged.count - 1] = (last.0, max(last.1, interval.1))
                } else {
                    merged.append(interval)
                }
            }
            let seconds = merged.reduce(0.0) { $0 + max(0, $1.1.timeIntervalSince($1.0)) }
            let latestSource = asleep.max(by: { $0.endDate < $1.endDate })?.sourceRevision.source.name
            completion(seconds > 0 ? seconds / 3600.0 : nil, latestSource)
        }
        store.execute(query)
    }
}

struct HealthProgressionDashboardView: View {
    @State private var health = HealthProgressionData.empty
    @State private var summaries: [TrackerSummary] = []
    @State private var loading = true

    private let reader = HealthProgressionReader()
    private let sessionStore = NativeSessionStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    activityLoadCard
                    todayHealthCard
                    personalBaselinesCard
                    trendCards
                    provenanceCard
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .navigationTitle("Progression")
            .refreshable { refresh() }
            .onAppear { refresh() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Ton évolution, pas une note opaque")
                .font(.title3.weight(.bold))
            Text("Watch Tracker combine tes séances locales avec les données que tu choisis de partager depuis Santé. Chaque valeur reste identifiable et comparable à tes propres repères.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var activityLoadCard: some View {
        let seven = activityAggregate(days: 7)
        let previous = activityAggregate(days: 28)
        let weeklyReference = max(0, (previous.duration - seven.duration) / 3.0)

        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("CHARGE D’ACTIVITÉ", symbol: "figure.run")
            HStack(spacing: 10) {
                HealthDashboardMetric(value: compactDuration(seven.duration), label: "7 derniers jours", symbol: "7.circle.fill")
                HealthDashboardMetric(value: compactDistance(seven.distance), label: "distance", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                HealthDashboardMetric(value: "\(seven.count)", label: "séances", symbol: "calendar")
            }
            Text(loadComparison(current: seven.duration, reference: weeklyReference))
                .font(.subheadline.weight(.semibold))
            Text("Référence = moyenne hebdomadaire des 3 semaines précédentes quand l’historique est suffisant.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    @ViewBuilder
    private var todayHealthCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("AUJOURD’HUI · SANTÉ", symbol: "heart.text.square.fill")
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Lecture de Santé…").foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    HealthDashboardMetric(
                        value: health.stepsToday.map { "\(Int($0.rounded()))" } ?? "—",
                        label: "pas",
                        symbol: "shoeprints.fill"
                    )
                    HealthDashboardMetric(
                        value: health.exerciseMinutesToday.map { "\(Int($0.rounded())) min" } ?? "—",
                        label: "exercice",
                        symbol: "timer"
                    )
                    HealthDashboardMetric(
                        value: health.activeEnergyToday.map { "\(Int($0.rounded()))" } ?? "—",
                        label: "kcal actives",
                        symbol: "flame.fill"
                    )
                }
            }
        }
        .dashboardCard()
    }

    private var personalBaselinesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("REPÈRES PERSONNELS", symbol: "waveform.path.ecg")

            HealthBaselineRow(
                title: "FC au repos",
                value: health.restingHeartRate.map { String(format: "%.0f bpm", $0.value) } ?? "—",
                comparison: personalComparison(latest: health.restingHeartRate?.value, baseline: health.restingHeartRateBaseline, lowerIsNotAutomaticallyBetter: true),
                detail: health.restingHeartRate.map { "Dernière mesure · \($0.source)" } ?? unavailableText
            )

            Divider().opacity(0.5)

            HealthBaselineRow(
                title: "HRV · SDNN",
                value: health.hrvSDNN.map { String(format: "%.0f ms", $0.value) } ?? "—",
                comparison: personalComparison(latest: health.hrvSDNN?.value, baseline: health.hrvBaseline, lowerIsNotAutomaticallyBetter: true),
                detail: health.hrvSDNN.map { "Dernière mesure · \($0.source)" } ?? unavailableText
            )

            Divider().opacity(0.5)

            HealthBaselineRow(
                title: "Sommeil récent",
                value: health.sleepHours.map { hoursText($0) } ?? "—",
                comparison: nil,
                detail: health.sleepSource.map { "Épisodes de sommeil récents · \($0)" } ?? unavailableText
            )

            Divider().opacity(0.5)

            HealthBaselineRow(
                title: "VO₂ max",
                value: health.vo2Max.map { String(format: "%.1f ml/kg/min", $0.value) } ?? "—",
                comparison: nil,
                detail: health.vo2Max.map { "Dernière estimation · \($0.source)" } ?? unavailableText
            )
        }
        .dashboardCard()
    }

    @ViewBuilder
    private var trendCards: some View {
        if health.restingHeartRateTrend.count >= 2 {
            HealthTrendCard(
                title: "FC au repos · 14 jours",
                unit: "bpm",
                points: health.restingHeartRateTrend
            )
        }
        if health.hrvTrend.count >= 2 {
            HealthTrendCard(
                title: "HRV SDNN · 14 jours",
                unit: "ms",
                points: health.hrvTrend
            )
        }
    }

    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("À PROPOS DES DONNÉES", symbol: "info.circle.fill")
            Text(health.note ?? "Les métriques Santé apparaissent uniquement lorsqu’une valeur lisible existe.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Une valeur absente n’est jamais transformée en zéro. Watch Tracker ne pose pas de diagnostic et n’invente pas de score médical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .dashboardCard()
    }

    private var unavailableText: String {
        "Donnée indisponible ou non partagée"
    }

    private func refresh() {
        summaries = sessionStore.listSummaries()
        loading = true
        reader.load { result in
            health = result
            loading = false
        }
    }

    private func activityAggregate(days: Int) -> (duration: TimeInterval, distance: Double, count: Int) {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        let values = summaries.filter { $0.startedAt >= threshold }
        return (
            values.reduce(0) { $0 + $1.duration },
            values.reduce(0) { $0 + $1.distanceMeters },
            values.count
        )
    }

    private func loadComparison(current: TimeInterval, reference: TimeInterval) -> String {
        guard reference > 0 else { return "Encore trop peu d’historique pour établir un repère hebdomadaire." }
        let delta = (current - reference) / reference
        if abs(delta) < 0.08 { return "Volume récent proche de tes trois semaines précédentes." }
        return delta > 0
            ? String(format: "Volume récent +%.0f %% par rapport à ton repère personnel.", delta * 100)
            : String(format: "Volume récent %.0f %% par rapport à ton repère personnel.", delta * 100)
    }

    private func personalComparison(latest: Double?, baseline: Double?, lowerIsNotAutomaticallyBetter: Bool) -> String? {
        guard let latest, let baseline, baseline > 0 else { return nil }
        let delta = (latest - baseline) / baseline
        if abs(delta) < 0.05 { return "proche de ta moyenne 28 j" }
        let direction = delta > 0 ? "au-dessus" : "en dessous"
        return String(format: "%.0f %% %@ de ta moyenne 28 j", abs(delta) * 100, direction)
    }

    private func sectionTitle(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.black))
            .foregroundStyle(.secondary)
    }
}

private struct HealthBaselineRow: View {
    let title: String
    let value: String
    let comparison: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value).font(.headline.weight(.bold)).monospacedDigit()
            }
            if let comparison {
                Text(comparison).font(.caption).foregroundStyle(.secondary)
            }
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

private struct HealthTrendCard: View {
    let title: String
    let unit: String
    let points: [HealthTrendPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            Chart(points) { point in
                LineMark(
                    x: .value("Jour", point.date),
                    y: .value(unit, point.value)
                )
                PointMark(
                    x: .value("Jour", point.date),
                    y: .value(unit, point.value)
                )
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 170)
        }
        .dashboardCard()
    }
}

private struct HealthDashboardMetric: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.mint)
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func dashboardCard() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private func compactDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.1f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func compactDuration(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 60 { return String(format: "%dh%02d", minutes / 60, minutes % 60) }
    return "\(minutes) min"
}

private func hoursText(_ hours: Double) -> String {
    let minutes = max(0, Int((hours * 60).rounded()))
    return String(format: "%dh%02d", minutes / 60, minutes % 60)
}
