import Charts
import Foundation
import HealthKit
import SwiftUI

struct TrackerCardioTrendPoint: Identifiable, Equatable {
    let date: Date
    let value: Double
    let source: String

    var id: String { "\(source)-\(date.timeIntervalSince1970)-\(value)" }
}

struct TrackerCardioFitnessSnapshot: Equatable {
    let vo2Max: [TrackerCardioTrendPoint]
    let heartRateRecovery: [TrackerCardioTrendPoint]
    let restingHeartRate: [TrackerCardioTrendPoint]
    let bodyMass: [TrackerCardioTrendPoint]
    let generatedAt: Date
}

final class TrackerCardioFitnessReader {
    private let store = HKHealthStore()
    private let calendar = Calendar.autoupdatingCurrent

    func load(completion: @escaping (TrackerCardioFitnessSnapshot) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                completion(TrackerCardioFitnessSnapshot(vo2Max: [], heartRateRecovery: [], restingHeartRate: [], bodyMass: [], generatedAt: Date()))
            }
            return
        }

        let identifiers: [HKQuantityTypeIdentifier] = [
            .vo2Max,
            .heartRateRecoveryOneMinute,
            .restingHeartRate,
            .bodyMass,
        ]
        var types = Set<HKObjectType>()
        for identifier in identifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        store.requestAuthorization(toShare: [], read: types) { [weak self] _, _ in
            guard let self else { return }
            self.loadAuthorized(completion: completion)
        }
    }

    private func loadAuthorized(completion: @escaping (TrackerCardioFitnessSnapshot) -> Void) {
        let now = Date()
        let start = calendar.date(byAdding: .year, value: -1, to: now) ?? .distantPast
        let group = DispatchGroup()
        let lock = NSLock()
        var vo2: [TrackerCardioTrendPoint] = []
        var recovery: [TrackerCardioTrendPoint] = []
        var resting: [TrackerCardioTrendPoint] = []
        var mass: [TrackerCardioTrendPoint] = []

        if let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
            group.enter()
            loadDaily(type: type, unit: TrackerHealthUnits.vo2Max, start: start, end: now, reduce: .latest) { values in
                lock.lock(); vo2 = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) {
            group.enter()
            loadDaily(type: type, unit: .count(), start: start, end: now, reduce: .latest) { values in
                lock.lock(); recovery = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            group.enter()
            loadDaily(type: type, unit: bpm, start: start, end: now, reduce: .median) { values in
                lock.lock(); resting = values; lock.unlock(); group.leave()
            }
        }

        if let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            group.enter()
            loadDaily(type: type, unit: .gramUnit(with: .kilo), start: start, end: now, reduce: .latest) { values in
                lock.lock(); mass = values; lock.unlock(); group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(
                TrackerCardioFitnessSnapshot(
                    vo2Max: vo2,
                    heartRateRecovery: recovery,
                    restingHeartRate: resting,
                    bodyMass: mass,
                    generatedAt: now
                )
            )
        }
    }

    private enum Reduction {
        case latest
        case median
    }

    private func loadDaily(
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        reduce: Reduction,
        completion: @escaping ([TrackerCardioTrendPoint]) -> Void
    ) {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [calendar] _, samples, _ in
            var buckets: [Date: [(value: Double, date: Date, source: String)]] = [:]
            for sample in samples as? [HKQuantitySample] ?? [] {
                guard let value = sample.quantity.trackerDoubleValue(for: unit) else {
                    continue
                }
                let day = calendar.startOfDay(for: sample.endDate)
                buckets[day, default: []].append((value, sample.endDate, sample.sourceRevision.source.name))
            }

            let points = buckets.compactMap { day, values -> TrackerCardioTrendPoint? in
                guard !values.isEmpty else { return nil }
                switch reduce {
                case .latest:
                    guard let item = values.max(by: { $0.date < $1.date }) else { return nil }
                    return TrackerCardioTrendPoint(date: day, value: item.value, source: item.source)
                case .median:
                    let sorted = values.map(\.value).sorted()
                    let middle = sorted.count / 2
                    let value: Double
                    if sorted.count.isMultiple(of: 2) {
                        value = (sorted[middle - 1] + sorted[middle]) / 2
                    } else {
                        value = sorted[middle]
                    }
                    let source = values.last?.source ?? "Apple Health"
                    return TrackerCardioTrendPoint(date: day, value: value, source: source)
                }
            }
            .sorted { $0.date < $1.date }
            completion(points)
        }
        store.execute(query)
    }
}

struct TrackerCardioFitnessCard: View {
    @State private var snapshot: TrackerCardioFitnessSnapshot?
    @State private var loading = true

    private let reader = TrackerCardioFitnessReader()

    var body: some View {
        NavigationLink {
            TrackerCardioFitnessLabView(initialSnapshot: snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARDIO LAB")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.orange)
                        Text("Capacité et récupération")
                            .font(.headline.weight(.bold))
                    }
                    Spacer()
                    Image(systemName: "heart.text.square.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.pink)
                }

                HStack(spacing: 8) {
                    compactCell("VO₂ MAX", snapshot?.vo2Max.last.map { String(format: "%.1f", $0.value) } ?? "—", "lungs.fill", .orange)
                    compactCell("RÉCUP. 1 MIN", snapshot?.heartRateRecovery.last.map { String(format: "%.0f", $0.value) } ?? "—", "heart.circle.fill", .pink)
                    compactCell("FC REPOS", snapshot?.restingHeartRate.last.map { String(format: "%.0f", $0.value) } ?? "—", "heart.fill", .cyan)
                }

                HStack {
                    Text(loading ? "Lecture Apple Health…" : "Tendances sur 12 mois")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(15)
            .background(
                LinearGradient(
                    colors: [.orange.opacity(0.10), .pink.opacity(0.08), .white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .task { refresh() }
    }

    private func compactCell(_ label: String, _ value: String, _ symbol: String, _ accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(accent)
            Text(value)
                .font(.subheadline.weight(.black))
                .monospacedDigit()
                .minimumScaleFactor(0.65)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(8)
        .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }
}

struct TrackerCardioFitnessLabView: View {
    let initialSnapshot: TrackerCardioFitnessSnapshot?

    @State private var snapshot: TrackerCardioFitnessSnapshot?
    @State private var loading = false
    @State private var range: CardioLabRange = .sixMonths

    private let reader = TrackerCardioFitnessReader()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                rangePicker
                vo2Section
                recoverySection
                restingHeartRateSection
                weightSection
                interpretationCard
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.08), .indigo.opacity(0.06), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Cardio Lab")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            snapshot = initialSnapshot
            if snapshot == nil { refresh() }
        }
        .refreshable { refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CAPACITÉ CARDIO")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.orange)
                    Text(snapshot?.vo2Max.last.map { String(format: "%.1f mL/kg/min", $0.value) } ?? "Repères en construction")
                        .font(.title2.weight(.black))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "lungs.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let change = comparisonChange(points: snapshot?.vo2Max ?? [], days: 30) {
                Text(String(format: "%+.1f%% vs 30 jours précédents", change))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.cyan)
            } else {
                Text("La comparaison apparaît quand deux fenêtres de données sont disponibles.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(17)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var rangePicker: some View {
        Picker("Période", selection: $range) {
            ForEach(CardioLabRange.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var vo2Section: some View {
        trendSection(
            title: "VO₂ MAX",
            subtitle: "Apple Health · capacité cardio relative",
            symbol: "lungs.fill",
            accent: .orange,
            points: filtered(snapshot?.vo2Max ?? []),
            unit: "mL/kg/min",
            digits: 1
        )
    }

    @ViewBuilder
    private var recoverySection: some View {
        trendSection(
            title: "RÉCUPÉRATION FC · 1 MIN",
            subtitle: "Baisse de fréquence cardiaque après l’exercice",
            symbol: "heart.circle.fill",
            accent: .pink,
            points: filtered(snapshot?.heartRateRecovery ?? []),
            unit: "bpm",
            digits: 0
        )
    }

    @ViewBuilder
    private var restingHeartRateSection: some View {
        trendSection(
            title: "FC AU REPOS",
            subtitle: "Tendance personnelle · pas de seuil diagnostic",
            symbol: "heart.fill",
            accent: .cyan,
            points: filtered(snapshot?.restingHeartRate ?? []),
            unit: "bpm",
            digits: 0
        )
    }

    @ViewBuilder
    private var weightSection: some View {
        trendSection(
            title: "POIDS",
            subtitle: "Contexte corporel · séparé de la récupération",
            symbol: "scalemass.fill",
            accent: .mint,
            points: filtered(snapshot?.bodyMass ?? []),
            unit: "kg",
            digits: 1
        )
    }

    private var interpretationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Lecture intelligente, pas un classement", systemImage: "info.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.mint)
            Text("Le VO₂ max affiché est celui lisible dans Apple Health. Le poids n’est pas appliqué une seconde fois : cette valeur est déjà relative au poids. La récupération FC, la FC au repos et le poids restent des tendances séparées avec leur propre provenance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Watch Tracker privilégie les changements par rapport à ton historique personnel. Aucune de ces courbes ne constitue un diagnostic médical.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(15)
        .background(.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func trendSection(
        title: String,
        subtitle: String,
        symbol: String,
        accent: Color,
        points: [TrackerCardioTrendPoint],
        unit: String,
        digits: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: symbol)
                        .font(.caption.weight(.black))
                        .foregroundStyle(accent)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let latest = points.last {
                    Text(format(latest.value, digits: digits, unit: unit))
                        .font(.headline.weight(.black))
                        .monospacedDigit()
                }
            }

            if points.count >= 2 {
                Chart(points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(accent)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accent.opacity(0.20), accent.opacity(0.01)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(.white.opacity(0.05))
                        AxisValueLabel()
                    }
                }
                .accessibilityLabel("Graphique \(title), \(points.count) points sur \(range.label)")
            } else if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ContentUnavailableView(
                    "Pas assez de données",
                    systemImage: symbol,
                    description: Text("La courbe apparaît quand au moins deux valeurs Apple Health sont lisibles sur cette période.")
                )
                .frame(minHeight: 100)
            }

            if let latest = points.last {
                HStack {
                    Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text(latest.source)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(15)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func filtered(_ points: [TrackerCardioTrendPoint]) -> [TrackerCardioTrendPoint] {
        guard let days = range.days,
              let threshold = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -days, to: Date()) else { return points }
        return points.filter { $0.date >= threshold }
    }

    private func comparisonChange(points: [TrackerCardioTrendPoint], days: Int) -> Double? {
        let now = Date()
        guard let currentStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -days, to: now),
              let previousStart = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -(days * 2), to: now) else { return nil }
        let current = points.filter { $0.date >= currentStart }.map(\.value)
        let previous = points.filter { $0.date >= previousStart && $0.date < currentStart }.map(\.value)
        guard let currentAverage = average(current),
              let previousAverage = average(previous),
              abs(previousAverage) > 0.0001 else { return nil }
        return (currentAverage - previousAverage) / previousAverage * 100
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func format(_ value: Double, digits: Int, unit: String) -> String {
        let text: String
        if digits == 0 {
            text = String(format: "%.0f", value)
        } else {
            text = String(format: "%.1f", value)
        }
        return "\(text) \(unit)"
    }

    private func refresh() {
        loading = true
        reader.load { value in
            snapshot = value
            loading = false
        }
    }
}

private enum CardioLabRange: String, CaseIterable, Identifiable {
    case month
    case threeMonths
    case sixMonths
    case year

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "1 m"
        case .threeMonths: return "3 m"
        case .sixMonths: return "6 m"
        case .year: return "1 an"
        }
    }

    var days: Int? {
        switch self {
        case .month: return 30
        case .threeMonths: return 90
        case .sixMonths: return 183
        case .year: return 365
        }
    }
}
