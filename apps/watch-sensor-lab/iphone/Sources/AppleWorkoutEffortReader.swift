import Foundation
import HealthKit

struct AppleWorkoutEffortSnapshot: Equatable {
    let perceivedScore: Double?
    let estimatedScore: Double?
    let workoutSource: String?
    let workoutDate: Date?

    var hasAnyValue: Bool {
        perceivedScore != nil || estimatedScore != nil
    }
}

final class AppleWorkoutEffortReader {
    private let store = HKHealthStore()
    private static let trackerSessionMetadataKey = "com.rzbck.watchsensorlab.session_id"

    func load(summary: TrackerSummary, completion: @escaping (AppleWorkoutEffortSnapshot?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        guard #available(iOS 18.0, *) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        guard let perceivedType = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore),
              let estimatedType = HKQuantityType.quantityType(forIdentifier: .estimatedWorkoutEffortScore) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            perceivedType,
            estimatedType,
        ]

        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] _, _ in
            guard let self else { return }
            self.findTrackerWorkout(summary: summary) { workout in
                guard let workout else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let group = DispatchGroup()
                let lock = NSLock()
                var perceived: Double?
                var estimated: Double?

                group.enter()
                self.loadEffort(type: perceivedType, workout: workout) { value in
                    lock.lock(); perceived = value; lock.unlock()
                    group.leave()
                }

                group.enter()
                self.loadEffort(type: estimatedType, workout: workout) { value in
                    lock.lock(); estimated = value; lock.unlock()
                    group.leave()
                }

                group.notify(queue: .main) {
                    let snapshot = AppleWorkoutEffortSnapshot(
                        perceivedScore: perceived,
                        estimatedScore: estimated,
                        workoutSource: workout.sourceRevision.source.name,
                        workoutDate: workout.endDate
                    )
                    completion(snapshot.hasAnyValue ? snapshot : nil)
                }
            }
        }
    }

    @available(iOS 18.0, *)
    private func findTrackerWorkout(summary: TrackerSummary, completion: @escaping (HKWorkout?) -> Void) {
        let start = summary.startedAt.addingTimeInterval(-120)
        let end = summary.endedAt.addingTimeInterval(120)
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: datePredicate,
            limit: 64,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let workouts = samples as? [HKWorkout] ?? []

            if let exact = workouts.first(where: {
                ($0.metadata?[Self.trackerSessionMetadataKey] as? String) == summary.sessionID
            }) {
                completion(exact)
                return
            }

            // Metadata can be unavailable on older/imported records. Only fall back when
            // activity and time overlap make the association unambiguous enough.
            let candidates = workouts.filter { workout in
                guard let kind = ActivityKind(healthKitType: workout.workoutActivityType),
                      kind.rawValue == summary.activity else { return false }
                let startDelta = abs(workout.startDate.timeIntervalSince(summary.startedAt))
                let durationDelta = abs(workout.duration - summary.duration)
                return startDelta <= 30 && durationDelta <= 90
            }
            completion(candidates.count == 1 ? candidates[0] : nil)
        }
        store.execute(query)
    }

    @available(iOS 18.0, *)
    private func loadEffort(
        type: HKQuantityType,
        workout: HKWorkout,
        completion: @escaping (Double?) -> Void
    ) {
        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            let value = sample.quantity.doubleValue(for: .appleEffortScore())
            guard value.isFinite, value > 0 else {
                completion(nil)
                return
            }
            completion(min(10, max(1, value)))
        }
        store.execute(query)
    }
}
