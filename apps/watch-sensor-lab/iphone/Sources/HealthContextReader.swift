import Foundation
import HealthKit

struct HealthContextMetric: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let detail: String
}

struct HealthContextReport: Equatable {
    let metrics: [HealthContextMetric]
    let note: String?

    static let empty = HealthContextReport(metrics: [], note: nil)
}

/// Reads HealthKit metrics that may contextualize a recorded activity.
///
/// Important: most mobility metrics below are system-generated samples and are not guaranteed to
/// exist during every workout. They are intentionally presented as Health context, never as a live
/// sensor stream produced by Watch Tracker.
final class HealthContextReader {
    private let healthStore = HKHealthStore()
    private let aggregationQueue = DispatchQueue(label: "com.rzbck.watchsensorlab.health-context")

    private struct Definition {
        let order: Int
        let id: String
        let label: String
        let type: HKQuantityType
        let unit: HKUnit
        let options: HKStatisticsOptions
        let start: (TrackerSummary) -> Date
        let end: (TrackerSummary) -> Date
        let detail: String
        let formatter: (Double) -> String
    }

    func load(for summary: TrackerSummary, completion: @escaping (HealthContextReport) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(HealthContextReport(metrics: [], note: "HealthKit indisponible sur cet appareil."))
            return
        }

        let definitions = makeDefinitions()
        let readTypes = Set(definitions.map { $0.type as HKObjectType })

        healthStore.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, error in
            guard let self else { return }
            if let error {
                DispatchQueue.main.async {
                    completion(HealthContextReport(metrics: [], note: "Contexte Santé indisponible : \(error.localizedDescription)"))
                }
                return
            }

            self.query(definitions: definitions, summary: summary, completion: completion)
        }
    }

    private func query(
        definitions: [Definition],
        summary: TrackerSummary,
        completion: @escaping (HealthContextReport) -> Void
    ) {
        let group = DispatchGroup()
        var results: [(Int, HealthContextMetric)] = []

        for definition in definitions {
            group.enter()
            let predicate = HKQuery.predicateForSamples(
                withStart: definition.start(summary),
                end: definition.end(summary),
                options: []
            )
            let query = HKStatisticsQuery(
                quantityType: definition.type,
                quantitySamplePredicate: predicate,
                options: definition.options
            ) { [weak self] _, statistics, _ in
                defer { group.leave() }
                guard let self, let quantity = self.quantity(from: statistics, options: definition.options) else { return }
                let raw = quantity.doubleValue(for: definition.unit)
                guard raw.isFinite else { return }

                let metric = HealthContextMetric(
                    id: definition.id,
                    label: definition.label,
                    value: definition.formatter(raw),
                    detail: definition.detail
                )
                self.aggregationQueue.sync {
                    results.append((definition.order, metric))
                }
            }
            healthStore.execute(query)
        }

        group.notify(queue: .main) {
            let metrics = self.aggregationQueue.sync {
                results.sorted { $0.0 < $1.0 }.map(\.1)
            }
            let note = metrics.isEmpty
                ? "Aucune métrique Santé contextuelle disponible sur les fenêtres analysées. Ce n’est pas une erreur : plusieurs métriques de mobilité sont produites seulement dans des conditions précises."
                : "Ces valeurs viennent de Santé et peuvent être calculées par Apple hors du flux temps réel de Watch Tracker."
            completion(HealthContextReport(metrics: metrics, note: note))
        }
    }

    private func quantity(from statistics: HKStatistics?, options: HKStatisticsOptions) -> HKQuantity? {
        guard let statistics else { return nil }
        if options.contains(.discreteMax) { return statistics.maximumQuantity() }
        if options.contains(.cumulativeSum) { return statistics.sumQuantity() }
        return statistics.averageQuantity()
    }

    private func makeDefinitions() -> [Definition] {
        let bpm = HKUnit.count().unitDivided(by: HKUnit.minute())
        let breathsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let percent = HKUnit.percent()
        let sessionStart: (TrackerSummary) -> Date = { $0.startedAt }
        let sessionEnd: (TrackerSummary) -> Date = { $0.endedAt }
        let respiratoryStart: (TrackerSummary) -> Date = { $0.startedAt.addingTimeInterval(-12 * 3600) }
        let respiratoryEnd: (TrackerSummary) -> Date = { $0.endedAt.addingTimeInterval(12 * 3600) }
        let steadinessStart: (TrackerSummary) -> Date = { $0.startedAt.addingTimeInterval(-7 * 24 * 3600) }
        let steadinessEnd: (TrackerSummary) -> Date = { $0.endedAt }
        let recoveryStart: (TrackerSummary) -> Date = { $0.endedAt }
        let recoveryEnd: (TrackerSummary) -> Date = { $0.endedAt.addingTimeInterval(10 * 60) }

        var definitions: [Definition] = []

        func add(
            _ order: Int,
            _ identifier: HKQuantityTypeIdentifier,
            _ id: String,
            _ label: String,
            _ unit: HKUnit,
            _ options: HKStatisticsOptions = .discreteAverage,
            _ start: @escaping (TrackerSummary) -> Date = sessionStart,
            _ end: @escaping (TrackerSummary) -> Date = sessionEnd,
            _ detail: String,
            _ formatter: @escaping (Double) -> String
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
            definitions.append(
                Definition(
                    order: order,
                    id: id,
                    label: label,
                    type: type,
                    unit: unit,
                    options: options,
                    start: start,
                    end: end,
                    detail: detail,
                    formatter: formatter
                )
            )
        }

        add(10, .walkingSpeed, "walking_speed", "Vitesse marche Santé", HKUnit.meter().unitDivided(by: HKUnit.second()), detail: "Pendant la fenêtre de l’activité, si iOS a produit des échantillons de mobilité.") {
            String(format: "%.1f km/h", $0 * 3.6)
        }
        add(11, .walkingStepLength, "walking_step_length", "Longueur de pas", HKUnit.meter(), detail: "Métrique de mobilité Apple, pas un flux live de l’app.") {
            String(format: "%.0f cm", $0 * 100)
        }
        add(12, .walkingAsymmetryPercentage, "walking_asymmetry", "Asymétrie marche", percent, detail: "Produite par iOS dans des conditions de marche adaptées.") {
            String(format: "%.1f %%", $0 * 100)
        }
        add(13, .walkingDoubleSupportPercentage, "walking_double_support", "Double appui", percent, detail: "Part du cycle de marche avec les deux pieds au sol.") {
            String(format: "%.1f %%", $0 * 100)
        }
        add(14, .appleWalkingSteadiness, "walking_steadiness", "Stabilité marche", percent, .discreteAverage, steadinessStart, steadinessEnd, "Contexte Santé sur les 7 jours précédant l’activité ; ce score n’est pas calculé en direct.") {
            String(format: "%.0f %%", $0 * 100)
        }

        add(20, .runningSpeed, "running_speed", "Vitesse course Santé", HKUnit.meter().unitDivided(by: HKUnit.second()), detail: "Disponible pour les courses lorsque le matériel/HealthKit produit cette métrique.") {
            String(format: "%.1f km/h", $0 * 3.6)
        }
        add(21, .runningPower, "running_power", "Puissance course", HKUnit.watt(), detail: "Puissance de course HealthKit lorsque disponible.") {
            String(format: "%.0f W", $0)
        }
        add(22, .runningStrideLength, "running_stride_length", "Longueur foulée", HKUnit.meter(), detail: "Longueur de foulée de course HealthKit.") {
            String(format: "%.0f cm", $0 * 100)
        }
        add(23, .runningGroundContactTime, "running_ground_contact", "Contact au sol", HKUnit.second(), detail: "Temps de contact au sol en course.") {
            String(format: "%.0f ms", $0 * 1000)
        }
        add(24, .runningVerticalOscillation, "running_vertical_oscillation", "Oscillation verticale", HKUnit.meter(), detail: "Oscillation verticale de course HealthKit.") {
            String(format: "%.1f cm", $0 * 100)
        }

        add(30, .heartRate, "heart_rate_max_health", "FC max Santé", bpm, .discreteMax, sessionStart, sessionEnd, "Maximum des échantillons HealthKit pendant la fenêtre de l’activité.") {
            String(format: "%.0f bpm", $0)
        }
        add(31, .heartRateRecoveryOneMinute, "heart_rate_recovery", "Récupération FC", bpm, .discreteAverage, recoveryStart, recoveryEnd, "Valeur HealthKit de récupération cardiaque trouvée dans les 10 minutes suivant l’arrêt.") {
            String(format: "%.0f bpm", $0)
        }
        add(32, .respiratoryRate, "respiratory_context", "Respiration Santé", breathsPerMinute, .discreteAverage, respiratoryStart, respiratoryEnd, "Contexte ±12 h autour de l’activité ; pas une mesure respiratoire live de l’entraînement.") {
            String(format: "%.1f resp/min", $0)
        }

        return definitions
    }
}
