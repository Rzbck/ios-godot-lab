import Combine
import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

/// Rewrites an Auto workout only when Watch Tracker actually detected more than one sport.
///
/// The live HKWorkoutSession remains untouched while the user is exercising. After STOP, this
/// reconciler waits for the Watch-owned HealthKit workout + route to be durable, then creates one
/// correctly typed HealthKit workout per detected segment. The original container is deleted only
/// after every replacement workout and route has been saved successfully. If anything fails, the
/// replacements are rolled back and the original workout is retained.
final class WatchAutoHealthReconciler: ObservableObject {
    static let shared = WatchAutoHealthReconciler()

    private struct Segment: Codable, Equatable {
        var activity: ActivityKind
        var startedAt: Date
        var endedAt: Date?
    }

    private struct Plan: Codable, Equatable {
        var sessionID: String
        var segments: [Segment]
        var stoppedAt: Date?
        var routeExpected: Bool
    }

    private struct Snapshot: Equatable {
        let phase: SensorModel.Phase
        let sessionID: String
        let selectedActivity: ActivityKind
        let effectiveActivity: ActivityKind
    }

    private struct NormalizedSegment {
        let activity: ActivityKind
        let start: Date
        let end: Date
    }

    private enum Outcome {
        case notReady
        case unchanged
        case reconciled(Int)
        case alreadyReconciled(Int)
    }

    private enum ReconcileError: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let message): return message
            }
        }
    }

    @Published private(set) var status = ""

    private let healthStore = HKHealthStore()
    private let defaults = UserDefaults.standard
    private let pendingPlansKey = "tracker.autoHealth.pendingPlans.v1"
    private let segmentedKey = "com.rzbck.watchsensorlab.healthkit_segmented"
    private let managedKey = "com.rzbck.watchsensorlab.managed"
    private let sessionKey = "com.rzbck.watchsensorlab.session_id"
    private let segmentIndexKey = "com.rzbck.watchsensorlab.healthkit_segment_index"
    private let segmentCountKey = "com.rzbck.watchsensorlab.healthkit_segment_count"
    private let segmentActivityKey = "com.rzbck.watchsensorlab.segment_activity"
    private let masterActivityKey = "com.rzbck.watchsensorlab.master_activity"
    private let algorithmKey = "com.rzbck.watchsensorlab.algorithm_version"
    private let buildKey = "com.rzbck.watchsensorlab.build_sha"

    private var cancellables = Set<AnyCancellable>()
    private var bound = false
    private var lastSnapshot: Snapshot?
    private var activePlan: Plan?
    private var pendingPlans: [Plan] = []
    private var reconciliationTask: Task<Void, Never>?

    private init() {
        pendingPlans = loadPendingPlans()
    }

    func bind(to model: SensorModel) {
        guard !bound else { return }
        bound = true
        requestHealthAccess()

        let observe: () -> Void = { [weak self, weak model] in
            guard let self, let model else { return }
            self.observe(model)
        }

        model.$phase.receive(on: DispatchQueue.main).sink { _ in observe() }.store(in: &cancellables)
        model.$sessionID.receive(on: DispatchQueue.main).sink { _ in observe() }.store(in: &cancellables)
        model.$selectedActivity.receive(on: DispatchQueue.main).sink { _ in observe() }.store(in: &cancellables)
        model.$effectiveActivity.receive(on: DispatchQueue.main).sink { _ in observe() }.store(in: &cancellables)

        if !pendingPlans.isEmpty {
            schedulePendingReconciliation()
        }
    }

    private func requestHealthAccess() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var readTypes: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                readTypes.insert(type)
            }
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if !success, let error {
                    self.status = "Santé Auto: \(error.localizedDescription)"
                }
            }
        }
    }

    private func observe(_ model: SensorModel) {
        let snapshot = Snapshot(
            phase: model.phase,
            sessionID: model.sessionID,
            selectedActivity: model.selectedActivity,
            effectiveActivity: model.effectiveActivity
        )
        guard snapshot != lastSnapshot else { return }
        let previous = lastSnapshot
        lastSnapshot = snapshot
        let now = Date()

        if snapshot.selectedActivity.isAutomatic,
           (snapshot.phase == .active || snapshot.phase == .paused),
           !snapshot.sessionID.isEmpty {
            if activePlan?.sessionID != snapshot.sessionID {
                activePlan = Plan(
                    sessionID: snapshot.sessionID,
                    segments: [Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)],
                    stoppedAt: nil,
                    routeExpected: false
                )
            } else if snapshot.phase == .active,
                      previous?.effectiveActivity != snapshot.effectiveActivity,
                      activePlan?.segments.last?.activity != snapshot.effectiveActivity {
                closeCurrentSegment(at: now)
                activePlan?.segments.append(
                    Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)
                )
            }
            return
        }

        if snapshot.phase == .ready, var plan = activePlan {
            closeCurrentSegment(at: now)
            plan = activePlan ?? plan
            plan.stoppedAt = now
            plan.routeExpected = model.route.count > 1
            activePlan = nil
            enqueue(plan)
        }
    }

    private func closeCurrentSegment(at date: Date) {
        guard var plan = activePlan, !plan.segments.isEmpty else { return }
        let index = plan.segments.index(before: plan.segments.endIndex)
        if plan.segments[index].endedAt == nil {
            plan.segments[index].endedAt = max(date, plan.segments[index].startedAt)
        }
        activePlan = plan
    }

    private func enqueue(_ plan: Plan) {
        guard plan.segments.count > 0 else { return }
        if let existing = pendingPlans.firstIndex(where: { $0.sessionID == plan.sessionID }) {
            pendingPlans[existing] = plan
        } else {
            pendingPlans.append(plan)
        }
        persistPendingPlans()
        schedulePendingReconciliation()
    }

    private func schedulePendingReconciliation() {
        guard reconciliationTask == nil else { return }
        reconciliationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                DispatchQueue.main.async { [weak self] in self?.reconciliationTask = nil }
            }

            while !Task.isCancelled {
                guard let plan = self.pendingPlans.first else { return }
                var resolved = false

                for _ in 0..<15 where !Task.isCancelled {
                    do {
                        let outcome = try await self.reconcile(plan)
                        switch outcome {
                        case .notReady:
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            continue
                        case .unchanged:
                            self.finish(plan: plan, message: "Santé Auto: activité unique conservée")
                            resolved = true
                        case .reconciled(let count):
                            self.finish(plan: plan, message: "Santé Auto: \(count) segments correctement typés")
                            resolved = true
                        case .alreadyReconciled(let count):
                            self.finish(plan: plan, message: "Santé Auto: \(count) segments déjà réconciliés")
                            resolved = true
                        }
                    } catch {
                        self.emit(
                            event: "health_auto_reconcile_failed",
                            sessionID: plan.sessionID,
                            payload: ["message": error.localizedDescription]
                        )
                        DispatchQueue.main.async { [weak self] in
                            self?.status = "Santé Auto conservée: \(error.localizedDescription)"
                        }
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        continue
                    }
                    if resolved { break }
                }

                if !resolved {
                    DispatchQueue.main.async { [weak self] in
                        self?.status = "Santé Auto: conteneur original conservé (réconciliation différée)"
                    }
                    return
                }
            }
        }
    }

    private func finish(plan: Plan, message: String) {
        pendingPlans.removeAll { $0.sessionID == plan.sessionID }
        persistPendingPlans()
        emit(event: "health_auto_reconcile_completed", sessionID: plan.sessionID, payload: ["status": message])
        DispatchQueue.main.async { [weak self] in self?.status = message }
    }

    private func reconcile(_ plan: Plan) async throws -> Outcome {
        let workouts = try await sessionWorkouts(sessionID: plan.sessionID)
        let segmented = workouts.filter { ($0.metadata?[segmentedKey] as? Bool) == true }
        let originals = workouts.filter { ($0.metadata?[segmentedKey] as? Bool) != true }

        guard let original = closestOriginal(in: originals, to: plan) else {
            if segmented.count >= 2 {
                return .alreadyReconciled(segmented.count)
            }
            return .notReady
        }

        let segments = normalizedSegments(plan: plan, original: original)
        guard Set(segments.map { $0.activity.rawValue }).count > 1 else {
            return .unchanged
        }

        let sessionRoutes = try await sessionRouteObjects(sessionID: plan.sessionID)
        let abandonedRoutes = sessionRoutes.filter { ($0.metadata?[segmentedKey] as? Bool) == true }
        if !segmented.isEmpty || !abandonedRoutes.isEmpty {
            try await deleteObjects(abandonedRoutes + segmented)
        }

        let originalRoutes = sessionRoutes.filter { ($0.metadata?[segmentedKey] as? Bool) != true }
        if plan.routeExpected && originalRoutes.isEmpty {
            return .notReady
        }

        var routeLocations: [CLLocation] = []
        for route in originalRoutes {
            routeLocations.append(contentsOf: try await loadLocations(for: route))
        }
        routeLocations.sort { $0.timestamp < $1.timestamp }
        if plan.routeExpected && routeLocations.count < 2 {
            return .notReady
        }

        let associatedSamples = try await associatedQuantitySamples(for: original)
        let events = original.workoutEvents ?? []
        var createdWorkouts: [HKWorkout] = []
        var createdRoutes: [HKWorkoutRoute] = []

        do {
            for (index, segment) in segments.enumerated() {
                let isLast = index == segments.index(before: segments.endIndex)
                let samples = associatedSamples.filter {
                    sample($0, belongsTo: segment, includeEnd: isLast)
                }
                let segmentEvents = events.filter {
                    event($0, belongsTo: segment, includeEnd: isLast)
                }
                let locations = routeLocations.filter {
                    instant($0.timestamp, belongsTo: segment, includeEnd: isLast)
                }

                let result = try await createSegmentWorkout(
                    segment: segment,
                    index: index,
                    count: segments.count,
                    sessionID: plan.sessionID,
                    original: original,
                    samples: samples,
                    events: segmentEvents,
                    locations: locations
                )
                createdWorkouts.append(result.workout)
                if let route = result.route { createdRoutes.append(route) }
            }
        } catch {
            try? await deleteObjects(createdRoutes + createdWorkouts)
            throw error
        }

        do {
            try await deleteObjects([original])
        } catch {
            try? await deleteObjects(createdRoutes + createdWorkouts)
            throw ReconcileError.operation("remplacement prêt mais conteneur original impossible à supprimer")
        }

        if !originalRoutes.isEmpty {
            try? await deleteObjects(originalRoutes)
        }

        emit(
            event: "health_auto_reconciled",
            sessionID: plan.sessionID,
            payload: [
                "segment_count": segments.count,
                "activities": segments.map { $0.activity.rawValue }.joined(separator: ","),
                "sample_count": associatedSamples.count,
                "route_point_count": routeLocations.count,
            ]
        )
        return .reconciled(segments.count)
    }

    private func closestOriginal(in workouts: [HKWorkout], to plan: Plan) -> HKWorkout? {
        guard let expected = plan.segments.first?.startedAt else { return workouts.first }
        return workouts.min {
            abs($0.startDate.timeIntervalSince(expected)) < abs($1.startDate.timeIntervalSince(expected))
        }
    }

    private func normalizedSegments(plan: Plan, original: HKWorkout) -> [NormalizedSegment] {
        var raw = plan.segments
        if raw.isEmpty { return [] }

        // Merge duplicate adjacent activity entries before applying HealthKit's exact workout bounds.
        var merged: [Segment] = []
        for segment in raw {
            if !merged.isEmpty, merged[merged.count - 1].activity == segment.activity {
                merged[merged.count - 1].endedAt = segment.endedAt
            } else {
                merged.append(segment)
            }
        }
        raw = merged

        if raw.count == 1 {
            return [NormalizedSegment(activity: raw[0].activity, start: original.startDate, end: original.endDate)]
        }

        var boundaries: [Date] = [original.startDate]
        for index in 1..<raw.count {
            let observed = raw[index].startedAt
            let minimum = boundaries[index - 1].addingTimeInterval(0.25)
            let maximum = original.endDate.addingTimeInterval(-0.25)
            boundaries.append(min(max(observed, minimum), maximum))
        }
        boundaries.append(original.endDate)

        var result: [NormalizedSegment] = []
        for index in raw.indices {
            let start = boundaries[index]
            let end = max(boundaries[index + 1], start.addingTimeInterval(0.05))
            result.append(NormalizedSegment(activity: raw[index].activity, start: start, end: min(end, original.endDate)))
        }
        return result.filter { $0.end > $0.start }
    }

    private func sessionWorkouts(sessionID: String) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: sessionKey,
            operatorType: .equalTo,
            value: sessionID
        )
        let samples = try await querySamples(type: HKObjectType.workoutType(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkout }
    }

    private func sessionRouteObjects(sessionID: String) async throws -> [HKWorkoutRoute] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: sessionKey,
            operatorType: .equalTo,
            value: sessionID
        )
        let samples = try await querySamples(type: HKSeriesType.workoutRoute(), predicate: predicate)
        return samples.compactMap { $0 as? HKWorkoutRoute }
    }

    private func associatedQuantitySamples(for workout: HKWorkout) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        var samples: [HKSample] = []
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            samples.append(contentsOf: try await querySamples(type: type, predicate: predicate))
        }
        return samples.sorted { $0.startDate < $1.startDate }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate?) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
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

    private func loadLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var result: [CLLocation] = []
            var finished = false
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                guard !finished else { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                if let locations { result.append(contentsOf: locations) }
                if done {
                    finished = true
                    continuation.resume(returning: result)
                }
            }
            healthStore.execute(query)
        }
    }

    private func createSegmentWorkout(
        segment: NormalizedSegment,
        index: Int,
        count: Int,
        sessionID: String,
        original: HKWorkout,
        samples: [HKSample],
        events: [HKWorkoutEvent],
        locations: [CLLocation]
    ) async throws -> (workout: HKWorkout, route: HKWorkoutRoute?) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = segment.activity.healthKitType
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: original.device
        )
        let routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder

        try await beginCollection(builder, start: segment.start)
        try await addMetadata([
            managedKey: true,
            sessionKey: sessionID,
            segmentedKey: true,
            segmentIndexKey: index,
            segmentCountKey: count,
            segmentActivityKey: segment.activity.rawValue,
            masterActivityKey: ActivityKind.automatic.rawValue,
            algorithmKey: "tracker-v4-20260910",
            buildKey: BuildInfo.gitSHA,
        ], to: builder)

        if !samples.isEmpty { try await addSamples(samples, to: builder) }
        if !events.isEmpty { try await addEvents(events, to: builder) }
        if let routeBuilder, locations.count >= 2 {
            try await insertRoute(locations, into: routeBuilder)
        }

        try await endCollection(builder, end: segment.end)
        guard let workout = try await finishWorkout(builder) else {
            throw ReconcileError.operation("HealthKit n’a pas retourné le segment sauvegardé")
        }

        guard let routeBuilder, locations.count >= 2 else { return (workout, nil) }
        let route = try await finishRoute(
            routeBuilder,
            workout: workout,
            metadata: [
                managedKey: true,
                sessionKey: sessionID,
                segmentedKey: true,
                segmentIndexKey: index,
                segmentCountKey: count,
                segmentActivityKey: segment.activity.rawValue,
            ]
        )
        return (workout, route)
    }

    private func beginCollection(_ builder: HKWorkoutBuilder, start: Date) async throws {
        try await checkedOperation { completion in builder.beginCollection(withStart: start, completion: completion) }
    }

    private func endCollection(_ builder: HKWorkoutBuilder, end: Date) async throws {
        try await checkedOperation { completion in builder.endCollection(withEnd: end, completion: completion) }
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await checkedOperation { completion in builder.addMetadata(metadata, completion: completion) }
    }

    private func addSamples(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await checkedOperation { completion in builder.add(samples, completion: completion) }
    }

    private func addEvents(_ events: [HKWorkoutEvent], to builder: HKWorkoutBuilder) async throws {
        try await checkedOperation { completion in builder.addWorkoutEvents(events, completion: completion) }
    }

    private func insertRoute(_ locations: [CLLocation], into builder: HKWorkoutRouteBuilder) async throws {
        var offset = 0
        while offset < locations.count {
            let end = min(offset + 250, locations.count)
            let chunk = Array(locations[offset..<end])
            try await checkedOperation { completion in builder.insertRouteData(chunk, completion: completion) }
            offset = end
        }
    }

    private func finishWorkout(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: workout)
                }
            }
        }
    }

    private func finishRoute(
        _ builder: HKWorkoutRouteBuilder,
        workout: HKWorkout,
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute? {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishRoute(with: workout, metadata: metadata) { route, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: route)
                }
            }
        }
    }

    private func checkedOperation(
        _ operation: (@escaping (Bool, Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            operation { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? ReconcileError.operation("opération HealthKit refusée"))
                }
            }
        }
    }

    private func deleteObjects(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await checkedOperation { completion in healthStore.delete(objects, withCompletion: completion) }
    }

    private func sample(_ sample: HKSample, belongsTo segment: NormalizedSegment, includeEnd: Bool) -> Bool {
        sample.startDate >= segment.start
            && sample.endDate <= segment.end
            && (includeEnd || sample.endDate < segment.end)
    }

    private func event(_ event: HKWorkoutEvent, belongsTo segment: NormalizedSegment, includeEnd: Bool) -> Bool {
        event.dateInterval.start >= segment.start
            && event.dateInterval.end <= segment.end
            && (includeEnd || event.dateInterval.end < segment.end)
    }

    private func instant(_ date: Date, belongsTo segment: NormalizedSegment, includeEnd: Bool) -> Bool {
        date >= segment.start && (includeEnd ? date <= segment.end : date < segment.end)
    }

    private func persistPendingPlans() {
        guard let data = try? JSONEncoder().encode(pendingPlans) else { return }
        defaults.set(data, forKey: pendingPlansKey)
    }

    private func loadPendingPlans() -> [Plan] {
        guard let data = defaults.data(forKey: pendingPlansKey),
              let plans = try? JSONDecoder().decode([Plan].self, from: data) else { return [] }
        return plans
    }

    private func emit(event: String, sessionID: String, payload: [String: Any]) {
        guard WCSession.isSupported(), !sessionID.isEmpty else { return }
        var body = payload
        body["name"] = event
        body["session_id"] = sessionID
        body["timestamp"] = Date().timeIntervalSince1970
        let packet: [String: Any] = [
            "type": "sensor_sample",
            "source": "watch",
            "kind": "event",
            "timestamp": Date().timeIntervalSince1970,
            "payload": body,
        ]
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        session.transferUserInfo(packet)
    }
}
