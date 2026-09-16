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


    private struct HistoricalRepairResult {
        let alreadyCorrect: Bool
        let replacementUUID: String
        let sourceWorkoutCount: Int
        let sampleCount: Int
        let routePointCount: Int
    }

    private struct HistoricalRestoreResult {
        let alreadyRestored: Bool
        let replacementUUID: String
        let sampleCount: Int
        let routePointCount: Int
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
    @Published private(set) var historicalRepairSessionID = ""
    @Published private(set) var historicalRepairInProgress = false

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
    private let manualCorrectionKey =
        "com.rzbck.watchsensorlab.manual_activity_correction"
    private let correctionTargetKey =
        "com.rzbck.watchsensorlab.correction_target_activity"
    private let correctionSourceUUIDsKey =
        "com.rzbck.watchsensorlab.correction_source_workouts"
    private let correctionWorkoutUUIDKey =
        "com.rzbck.watchsensorlab.correction_workout_uuid"

    private let rawRestoreKey =
        "com.rzbck.watchsensorlab.raw_restoration"

    private let rawRestoreSchemaKey =
        "com.rzbck.watchsensorlab.raw_restoration_schema"

    private let rawRestoreSourceKey =
        "com.rzbck.watchsensorlab.raw_restoration_source"

    private var cancellables = Set<AnyCancellable>()
    private var bound = false
    private var lastSnapshot: Snapshot?
    private var activePlan: Plan?
    private var pendingPlans: [Plan] = []
    private var reconciliationTask: Task<Void, Never>?
    private var historicalRepairTask: Task<Void, Never>?
    private var historicalRestoreTask: Task<Void, Never>?

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

    func repairHistoricalActivity(
        sessionID: String,
        targetActivity: ActivityKind
    ) {
        guard !sessionID.isEmpty, !targetActivity.isAutomatic else {
            return
        }

        guard historicalRepairTask == nil else {
            DispatchQueue.main.async {
                self.status = "Une correction Santé est déjà en cours"
            }
            return
        }

        historicalRepairSessionID = sessionID
        historicalRepairInProgress = true

        requestHealthAccess()

        DispatchQueue.main.async {
            self.status =
                "Correction Santé · \(targetActivity.label)…"
        }

        emit(
            event: "health_manual_correction_started",
            sessionID: sessionID,
            payload: [
                "target_activity": targetActivity.rawValue,
            ]
        )

        historicalRepairTask = Task { [weak self] in
            guard let self else { return }

            defer {
                self.historicalRepairTask = nil

                DispatchQueue.main.async {
                    self.historicalRepairInProgress = false
                }
            }

            do {
                let result =
                    try await self.repairHistoricalActivityTransaction(
                        sessionID: sessionID,
                        targetActivity: targetActivity
                    )

                await MainActor.run {
                    // La représentation locale Watch ne change
                    // qu'après la relecture/vérification HealthKit.
                    WatchRecentHistoryStore.shared
                        .applyConfirmedActivity(
                            sessionID: sessionID,
                            activity: targetActivity
                        )

                    self.status =
                        result.alreadyCorrect
                            ? "Santé déjà correcte · \(targetActivity.label)"
                            : "Santé corrigée · \(targetActivity.label)"
                }

                self.emit(
                    event: "health_manual_correction_completed",
                    sessionID: sessionID,
                    payload: [
                        "target_activity":
                            targetActivity.rawValue,
                        "already_correct":
                            result.alreadyCorrect,
                        "source_workout_count":
                            result.sourceWorkoutCount,
                        "sample_count":
                            result.sampleCount,
                        "route_point_count":
                            result.routePointCount,
                        "replacement_uuid":
                            result.replacementUUID,
                    ]
                )
            } catch {
                let remainingManaged =
                    (
                        (
                            try? await self.sessionWorkouts(
                                sessionID: sessionID
                            )
                        ) ?? []
                    ).filter {
                        ($0.metadata?[self.managedKey] as? Bool)
                            == true
                    }

                let originalPreserved =
                    remainingManaged.contains {
                        (
                            $0.metadata?[
                                self.manualCorrectionKey
                            ] as? Bool
                        ) != true
                    }

                await MainActor.run {
                    self.status =
                        originalPreserved
                            ? "Correction annulée · original conservé"
                            : "Correction échouée · source Santé absente"
                }

                self.emit(
                    event: "health_manual_correction_failed",
                    sessionID: sessionID,
                    payload: [
                        "target_activity":
                            targetActivity.rawValue,
                        "message":
                            error.localizedDescription,
                        "original_preserved":
                            originalPreserved,
                    ]
                )
            }
        }
    }


    func reportRestorePacketFailure(
        sessionID: String,
        targetActivity: String,
        message: String
    ) {
        status =
            "Restauration refusée · \(message)"

        emit(
            event:
                "health_raw_restore_failed",
            sessionID:
                sessionID,
            payload: [
                "target_activity":
                    targetActivity,
                "message":
                    message,
            ]
        )
    }

    func restoreHistoricalActivity(
        from payload:
            TrackerHealthRestorePayload
    ) {
        guard
            payload.schema
                == TrackerHealthRestorePayload
                    .currentSchema,
            !payload.sessionID.isEmpty,
            let targetActivity =
                ActivityKind(
                    rawValue:
                        payload.targetActivity
                ),
            !targetActivity.isAutomatic
        else {
            reportRestorePacketFailure(
                sessionID:
                    payload.sessionID,
                targetActivity:
                    payload.targetActivity,
                message:
                    "paquet de restauration invalide"
            )
            return
        }

        guard
            historicalRepairTask == nil,
            historicalRestoreTask == nil
        else {
            reportRestorePacketFailure(
                sessionID:
                    payload.sessionID,
                targetActivity:
                    payload.targetActivity,
                message:
                    "une mutation Santé est déjà en cours"
            )
            return
        }

        historicalRepairSessionID =
            payload.sessionID

        historicalRepairInProgress =
            true

        requestHealthAccess()

        status =
            "Restauration Santé · \(targetActivity.label)…"

        emit(
            event:
                "health_raw_restore_started",
            sessionID:
                payload.sessionID,
            payload: [
                "target_activity":
                    targetActivity.rawValue,
                "heart_rate_count":
                    payload.heartRates.count,
                "route_point_count":
                    payload.locations.count,
                "pause_count":
                    payload.pauses.count,
                "pause_provenance":
                    payload.pauseProvenance,
            ]
        )

        historicalRestoreTask =
            Task { [weak self] in
                guard let self else {
                    return
                }

                defer {
                    self.historicalRestoreTask =
                        nil

                    DispatchQueue.main.async {
                        self.historicalRepairInProgress =
                            false
                    }
                }

                do {
                    let result =
                        try await self
                            .restoreHistoricalActivityTransaction(
                                payload:
                                    payload,
                                targetActivity:
                                    targetActivity
                            )

                    await MainActor.run {
                        WatchRecentHistoryStore
                            .shared
                            .applyConfirmedActivity(
                                sessionID:
                                    payload.sessionID,
                                activity:
                                    targetActivity
                            )

                        self.status =
                            result.alreadyRestored
                                ? "Santé déjà restaurée · \(targetActivity.label)"
                                : "Santé restaurée · \(targetActivity.label)"
                    }

                    self.emit(
                        event:
                            "health_raw_restore_completed",
                        sessionID:
                            payload.sessionID,
                        payload: [
                            "target_activity":
                                targetActivity.rawValue,
                            "already_restored":
                                result.alreadyRestored,
                            "sample_count":
                                result.sampleCount,
                            "route_point_count":
                                result.routePointCount,
                            "replacement_uuid":
                                result.replacementUUID,
                        ]
                    )
                } catch {
                    await MainActor.run {
                        self.status =
                            "Restauration échouée · \(error.localizedDescription)"
                    }

                    self.emit(
                        event:
                            "health_raw_restore_failed",
                        sessionID:
                            payload.sessionID,
                        payload: [
                            "target_activity":
                                targetActivity.rawValue,
                            "message":
                                error.localizedDescription,
                        ]
                    )
                }
            }
    }

    private func restoreHistoricalActivityTransaction(
        payload: TrackerHealthRestorePayload,
        targetActivity: ActivityKind
    ) async throws -> HistoricalRestoreResult {
        let start =
            Date(
                timeIntervalSince1970:
                    payload.startedAt
            )

        let end =
            Date(
                timeIntervalSince1970:
                    payload.endedAt
            )

        guard
            end > start,
            payload.activeDuration > 0,
            payload.distanceMeters > 0
        else {
            throw ReconcileError.operation(
                "données temporelles Tracker invalides"
            )
        }

        let existing =
            (
                try await sessionWorkouts(
                    sessionID:
                        payload.sessionID
                )
            ).filter {
                (
                    $0.metadata?[
                        managedKey
                    ] as? Bool
                ) == true
            }

        if let restored =
            existing.first(
                where: {
                    (
                        $0.metadata?[
                            rawRestoreKey
                        ] as? Bool
                    ) == true
                    && $0.workoutActivityType
                        == targetActivity
                            .healthKitType
                }
            ) {

            let routeObjects =
                try await sessionRouteObjects(
                    sessionID:
                        payload.sessionID
                )

            let restoreRoute =
                routeObjects.first(
                    where: {
                        (
                            $0.metadata?[
                                rawRestoreKey
                            ] as? Bool
                        ) == true
                    }
                )

            try await verifyRawRestoration(
                payload:
                    payload,
                targetActivity:
                    targetActivity,
                workoutUUID:
                    restored.uuid,
                routeUUID:
                    restoreRoute?.uuid
            )

            let restoredSamples =
                try await associatedQuantitySamples(
                    for: restored
                )

            var restoredRoutePointCount = 0

            if let restoreRoute {
                restoredRoutePointCount =
                    try await loadLocations(
                        for: restoreRoute
                    ).count
            }

            return HistoricalRestoreResult(
                alreadyRestored: true,
                replacementUUID:
                    restored.uuid.uuidString,
                sampleCount:
                    restoredSamples.count,
                routePointCount:
                    restoredRoutePointCount
            )
        }

        guard existing.isEmpty else {
            throw ReconcileError.operation(
                "un workout Tracker existe déjà ; utiliser la correction normale"
            )
        }

        let samples =
            try makeRawRestoreSamples(
                payload:
                    payload,
                activity:
                    targetActivity
            )

        let events =
            makeRawRestoreEvents(
                payload:
                    payload
            )

        let locations =
            makeRawRestoreLocations(
                payload:
                    payload
            )

        let configuration =
            HKWorkoutConfiguration()

        configuration.activityType =
            targetActivity.healthKitType

        configuration.locationType =
            locations.count >= 2
                ? .outdoor
                : .unknown

        let builder =
            HKWorkoutBuilder(
                healthStore:
                    healthStore,
                configuration:
                    configuration,
                device:
                    nil
            )

        let routeBuilder =
            builder.seriesBuilder(
                for:
                    HKSeriesType
                        .workoutRoute()
            ) as? HKWorkoutRouteBuilder

        var createdWorkout:
            HKWorkout?

        var createdRoute:
            HKWorkoutRoute?

        do {
            try await beginCollection(
                builder,
                start:
                    start
            )

            try await addMetadata(
                [
                    managedKey:
                        true,
                    sessionKey:
                        payload.sessionID,
                    manualCorrectionKey:
                        true,
                    rawRestoreKey:
                        true,
                    rawRestoreSchemaKey:
                        payload.schema,
                    rawRestoreSourceKey:
                        "tracker_raw_v1",
                    correctionTargetKey:
                        targetActivity.rawValue,
                    masterActivityKey:
                        targetActivity.rawValue,
                    algorithmKey:
                        payload.sourceAlgorithmVersion
                        ?? "tracker-raw-restore-v1",
                    buildKey:
                        BuildInfo.gitSHA,
                    "com.rzbck.watchsensorlab.raw_active_duration":
                        payload.activeDuration,
                    "com.rzbck.watchsensorlab.raw_distance_m":
                        payload.distanceMeters,
                    "com.rzbck.watchsensorlab.raw_pause_provenance":
                        payload.pauseProvenance,
                ],
                to:
                    builder
            )

            if !samples.isEmpty {
                try await addPreparedSamples(
                    samples,
                    to:
                        builder
                )
            }

            if !events.isEmpty {
                try await addEvents(
                    events,
                    to:
                        builder
                )
            }

            if let routeBuilder,
               locations.count >= 2 {

                try await insertRoute(
                    locations,
                    into:
                        routeBuilder
                )
            }

            try await endCollection(
                builder,
                end:
                    end
            )

            guard
                let workout =
                    try await finishWorkout(
                        builder
                    )
            else {
                throw ReconcileError.operation(
                    "HealthKit n’a pas retourné le workout restauré"
                )
            }

            createdWorkout =
                workout

            if let routeBuilder,
               locations.count >= 2 {

                createdRoute =
                    try await finishRoute(
                        routeBuilder,
                        workout:
                            workout,
                        metadata: [
                            managedKey:
                                true,
                            sessionKey:
                                payload.sessionID,
                            rawRestoreKey:
                                true,
                            rawRestoreSchemaKey:
                                payload.schema,
                            correctionWorkoutUUIDKey:
                                workout.uuid
                                    .uuidString,
                        ]
                    )
            }

            // Première relecture.
            try await verifyRawRestoration(
                payload:
                    payload,
                targetActivity:
                    targetActivity,
                workoutUUID:
                    workout.uuid,
                routeUUID:
                    createdRoute?.uuid
            )

            // Deuxième relecture différée :
            // un callback de création ne constitue pas
            // une preuve de durabilité.
            try await Task.sleep(
                nanoseconds:
                    700_000_000
            )

            try await verifyRawRestoration(
                payload:
                    payload,
                targetActivity:
                    targetActivity,
                workoutUUID:
                    workout.uuid,
                routeUUID:
                    createdRoute?.uuid
            )

            return HistoricalRestoreResult(
                alreadyRestored:
                    false,
                replacementUUID:
                    workout.uuid.uuidString,
                sampleCount:
                    samples.count,
                routePointCount:
                    locations.count
            )
        } catch {
            // Restauration : aucune source existante
            // n'est supprimée. Le rollback porte
            // exclusivement sur les objets créés ici.
            var createdObjects:
                [HKObject] = []

            if let createdRoute {
                createdObjects.append(
                    createdRoute
                )
            }

            if let createdWorkout {
                createdObjects.append(
                    createdWorkout
                )
            }

            try? await deleteObjects(
                createdObjects
            )

            throw error
        }
    }

    private func makeRawRestoreSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) throws -> [HKSample] {
        var samples:
            [HKSample] = []

        guard
            let heartRateType =
                HKQuantityType
                    .quantityType(
                        forIdentifier:
                            .heartRate
                    )
        else {
            throw ReconcileError.operation(
                "type HealthKit fréquence cardiaque indisponible"
            )
        }

        let heartRateUnit =
            HKUnit(
                from:
                    "count/min"
            )

        for point in payload.heartRates {
            guard
                point.bpm > 0,
                point.bpm < 260,
                point.timestamp
                    >= payload.startedAt,
                point.timestamp
                    <= payload.endedAt
            else {
                continue
            }

            let date =
                Date(
                    timeIntervalSince1970:
                        point.timestamp
                )

            samples.append(
                HKQuantitySample(
                    type:
                        heartRateType,
                    quantity:
                        HKQuantity(
                            unit:
                                heartRateUnit,
                            doubleValue:
                                point.bpm
                        ),
                    start:
                        date,
                    end:
                        date,
                    metadata: [
                        rawRestoreKey:
                            true,
                        sessionKey:
                            payload.sessionID,
                    ]
                )
            )
        }

        let start =
            Date(
                timeIntervalSince1970:
                    payload.startedAt
            )

        let end =
            Date(
                timeIntervalSince1970:
                    payload.endedAt
            )

        if let energy =
            payload.activeEnergyKcal,
           energy > 0,
           let energyType =
                HKQuantityType
                    .quantityType(
                        forIdentifier:
                            .activeEnergyBurned
                    ) {

            samples.append(
                HKQuantitySample(
                    type:
                        energyType,
                    quantity:
                        HKQuantity(
                            unit:
                                .kilocalorie(),
                            doubleValue:
                                energy
                        ),
                    start:
                        start,
                    end:
                        end,
                    metadata: [
                        rawRestoreKey:
                            true,
                        sessionKey:
                            payload.sessionID,
                    ]
                )
            )
        }

        if payload.distanceMeters > 0,
           let identifier =
                restoreDistanceIdentifier(
                    for:
                        activity
                ),
           let distanceType =
                HKQuantityType
                    .quantityType(
                        forIdentifier:
                            identifier
                    ) {

            samples.append(
                HKQuantitySample(
                    type:
                        distanceType,
                    quantity:
                        HKQuantity(
                            unit:
                                .meter(),
                            doubleValue:
                                payload.distanceMeters
                        ),
                    start:
                        start,
                    end:
                        end,
                    metadata: [
                        rawRestoreKey:
                            true,
                        sessionKey:
                            payload.sessionID,
                    ]
                )
            )
        }

        guard !samples.isEmpty else {
            throw ReconcileError.operation(
                "aucun sample brut restaurable"
            )
        }

        return samples
    }

    private func restoreDistanceIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling:
            return .distanceCycling

        case .swimming,
             .waterFitness,
             .waterPolo:
            return .distanceSwimming

        case .walking,
             .running,
             .hiking,
             .trackAndField:
            return .distanceWalkingRunning

        default:
            return nil
        }
    }

    private func makeRawRestoreEvents(
        payload: TrackerHealthRestorePayload
    ) -> [HKWorkoutEvent] {
        var result:
            [HKWorkoutEvent] = []

        for pause in payload.pauses.sorted(
            by: {
                $0.startedAt
                    < $1.startedAt
            }
        ) {
            guard
                pause.startedAt
                    >= payload.startedAt,
                pause.startedAt
                    < payload.endedAt,
                pause.endedAt
                    > pause.startedAt,
                pause.endedAt
                    <= payload.endedAt
            else {
                continue
            }

            let pauseDate =
                Date(
                    timeIntervalSince1970:
                        pause.startedAt
                )

            result.append(
                HKWorkoutEvent(
                    type:
                        .pause,
                    dateInterval:
                        DateInterval(
                            start:
                                pauseDate,
                            duration:
                                0
                        ),
                    metadata: [
                        rawRestoreKey:
                            true
                    ]
                )
            )

            // Si la pause se termine exactement avec
            // la séance, aucun resume artificiel.
            if pause.endedAt
                < payload.endedAt - 0.05 {

                let resumeDate =
                    Date(
                        timeIntervalSince1970:
                            pause.endedAt
                    )

                result.append(
                    HKWorkoutEvent(
                        type:
                            .resume,
                        dateInterval:
                            DateInterval(
                                start:
                                    resumeDate,
                                duration:
                                    0
                            ),
                        metadata: [
                            rawRestoreKey:
                                true
                        ]
                    )
                )
            }
        }

        return result
    }

    private func makeRawRestoreLocations(
        payload: TrackerHealthRestorePayload
    ) -> [CLLocation] {
        payload.locations
            .filter {
                $0.timestamp
                    >= payload.startedAt
                && $0.timestamp
                    <= payload.endedAt
                && $0.horizontalAccuracyMeters
                    >= 0
                && $0.horizontalAccuracyMeters
                    <= 50
                && (-90...90)
                    .contains(
                        $0.latitude
                    )
                && (-180...180)
                    .contains(
                        $0.longitude
                    )
            }
            .sorted {
                $0.timestamp
                    < $1.timestamp
            }
            .map {
                CLLocation(
                    coordinate:
                        CLLocationCoordinate2D(
                            latitude:
                                $0.latitude,
                            longitude:
                                $0.longitude
                        ),
                    altitude:
                        $0.altitudeMeters,
                    horizontalAccuracy:
                        $0.horizontalAccuracyMeters,
                    verticalAccuracy:
                        $0.verticalAccuracyMeters,
                    course:
                        -1,
                    speed:
                        $0.speedMps ?? -1,
                    timestamp:
                        Date(
                            timeIntervalSince1970:
                                $0.timestamp
                        )
                )
            }
    }

    private func verifyRawRestoration(
        payload: TrackerHealthRestorePayload,
        targetActivity: ActivityKind,
        workoutUUID: UUID,
        routeUUID: UUID?
    ) async throws {
        let workouts =
            try await sessionWorkouts(
                sessionID:
                    payload.sessionID
            )

        guard
            let workout =
                workouts.first(
                    where: {
                        $0.uuid
                            == workoutUUID
                    }
                ),
            workout.workoutActivityType
                == targetActivity
                    .healthKitType,
            (
                workout.metadata?[
                    managedKey
                ] as? Bool
            ) == true,
            (
                workout.metadata?[
                    rawRestoreKey
                ] as? Bool
            ) == true,
            abs(
                workout.startDate
                    .timeIntervalSince1970
                    - payload.startedAt
            ) <= 1,
            abs(
                workout.endDate
                    .timeIntervalSince1970
                    - payload.endedAt
            ) <= 1
        else {
            throw ReconcileError.operation(
                "le workout restauré n’a pas passé la relecture HealthKit"
            )
        }

        let samples =
            try await associatedQuantitySamples(
                for:
                    workout
            )

        let minimumSampleCount =
            payload.heartRates.count
            + (
                payload.activeEnergyKcal
                    .map { $0 > 0 ? 1 : 0 }
                ?? 0
            )
            + (
                restoreDistanceIdentifier(
                    for:
                        targetActivity
                ) == nil
                    ? 0
                    : 1
            )

        guard
            samples.count
                >= minimumSampleCount
        else {
            throw ReconcileError.operation(
                "des samples restaurés manquent après relecture"
            )
        }

        if restoreDistanceIdentifier(
            for:
                targetActivity
        ) != nil,
           payload.distanceMeters > 1 {

            let restoredDistance =
                distanceMeters(
                    in:
                        [workout]
                )

            let tolerance =
                max(
                    15,
                    payload.distanceMeters
                        * 0.04
                )

            guard
                abs(
                    restoredDistance
                        - payload.distanceMeters
                ) <= tolerance
            else {
                throw ReconcileError.operation(
                    "distance restaurée incohérente"
                )
            }
        }

        let durationTolerance =
            max(
                20,
                payload.activeDuration
                    * 0.04
            )

        guard
            abs(
                workout.duration
                    - payload.activeDuration
            ) <= durationTolerance
        else {
            throw ReconcileError.operation(
                "durée active restaurée incohérente"
            )
        }

        if payload.locations.count >= 2 {
            guard let routeUUID else {
                throw ReconcileError.operation(
                    "parcours restauré absent"
                )
            }

            let routes =
                try await sessionRouteObjects(
                    sessionID:
                        payload.sessionID
                )

            guard
                let route =
                    routes.first(
                        where: {
                            $0.uuid
                                == routeUUID
                            && (
                                $0.metadata?[
                                    rawRestoreKey
                                ] as? Bool
                            ) == true
                        }
                    )
            else {
                throw ReconcileError.operation(
                    "parcours restauré introuvable après relecture"
                )
            }

            let restoredLocations =
                try await loadLocations(
                    for:
                        route
                )

            guard
                restoredLocations.count
                    >= payload.locations.count
            else {
                throw ReconcileError.operation(
                    "points GPS restaurés incomplets"
                )
            }
        }
    }

    private func addPreparedSamples(
        _ samples: [HKSample],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checkedOperation {
            completion in

            builder.add(
                samples,
                completion:
                    completion
            )
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
        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]

        // Les remplacements et restaurations créent leurs propres
        // quantity samples : ils doivent donc être explicitement
        // autorisés en écriture.
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type =
                HKQuantityType.quantityType(
                    forIdentifier: identifier
                ) {
                shareTypes.insert(type)
            }
        }

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
            if !segmented.isEmpty {
                return .alreadyReconciled(segmented.count)
            }
            return .notReady
        }

        let segments = normalizedSegments(plan: plan, original: original)
        guard !segments.isEmpty else { return .notReady }

        let uniqueActivities = Set(
            segments.map { $0.activity.rawValue }
        )

        let originalActivity = ActivityKind(
            healthKitType: original.workoutActivityType
        )

        // Une séance Auto peut être mono-sport tout en ayant été lancée
        // avec le type provisoire "walking". Dans ce cas elle doit quand
        // même être reconstruite avec son vrai type.
        if uniqueActivities.count == 1,
           let onlyActivity = segments.first?.activity,
           originalActivity == onlyActivity {
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

        let postDeleteAutoWorkouts =
            try await sessionWorkouts(
                sessionID: plan.sessionID
            )

        let durableWorkoutIDs =
            Set(postDeleteAutoWorkouts.map { $0.uuid })

        let expectedWorkoutIDs =
            Set(createdWorkouts.map { $0.uuid })

        guard
            expectedWorkoutIDs.isSubset(
                of: durableWorkoutIDs
            )
        else {
            throw ReconcileError.operation(
                "un segment reconstruit n’a pas survécu à la suppression du conteneur original"
            )
        }

        if !createdRoutes.isEmpty {
            let postDeleteAutoRoutes =
                try await sessionRouteObjects(
                    sessionID: plan.sessionID
                )

            let durableRouteIDs =
                Set(postDeleteAutoRoutes.map { $0.uuid })

            let expectedRouteIDs =
                Set(createdRoutes.map { $0.uuid })

            guard
                expectedRouteIDs.isSubset(
                    of: durableRouteIDs
                )
            else {
                throw ReconcileError.operation(
                    "un parcours reconstruit n’a pas survécu à la suppression du parcours original"
                )
            }
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

        // Auto démarre historiquement avec walking comme valeur
        // provisoire. Un court segment initial avant la première vraie
        // classification ne représente pas forcément une vraie marche.
        if raw.count >= 2,
           raw[0].activity == .walking,
           raw[1].activity != .walking,
           let firstEnd = raw[0].endedAt,
           firstEnd.timeIntervalSince(raw[0].startedAt) <= 45 {
            raw.removeFirst()
        }

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

    private func repairHistoricalActivityTransaction(
        sessionID: String,
        targetActivity: ActivityKind
    ) async throws -> HistoricalRepairResult {

        let queriedWorkouts =
            try await sessionWorkouts(sessionID: sessionID)

        let sourceWorkouts = queriedWorkouts.filter {
            ($0.metadata?[managedKey] as? Bool) == true
        }

        guard !sourceWorkouts.isEmpty else {
            throw ReconcileError.operation(
                "aucun workout Watch Tracker correspondant à cette session"
            )
        }

        // Idempotence : une demande dupliquée ne recrée rien.
        if sourceWorkouts.count == 1,
           let current = sourceWorkouts.first,
           current.workoutActivityType == targetActivity.healthKitType,
           (current.metadata?[manualCorrectionKey] as? Bool) == true {

            return HistoricalRepairResult(
                alreadyCorrect: true,
                replacementUUID: current.uuid.uuidString,
                sourceWorkoutCount: 1,
                sampleCount:
                    try await associatedQuantitySamples(for: current).count,
                routePointCount:
                    try await routePointCount(
                        sessionID: sessionID,
                        correctionOnly: true
                    )
            )
        }

        let allRoutes =
            try await sessionRouteObjects(sessionID: sessionID)

        let sourceRoutes = allRoutes.filter {
            ($0.metadata?[managedKey] as? Bool) == true
        }

        var routeLocations: [CLLocation] = []

        for route in sourceRoutes {
            routeLocations.append(
                contentsOf: try await loadLocations(for: route)
            )
        }

        routeLocations.sort {
            $0.timestamp < $1.timestamp
        }

        // Déduplique les points si la session avait déjà été segmentée.
        var deduplicatedLocations: [CLLocation] = []
        var lastLocationKey = ""

        for location in routeLocations {
            let key = String(
                format: "%.3f|%.6f|%.6f",
                location.timestamp.timeIntervalSince1970,
                location.coordinate.latitude,
                location.coordinate.longitude
            )

            if key != lastLocationKey {
                deduplicatedLocations.append(location)
                lastLocationKey = key
            }
        }

        routeLocations = deduplicatedLocations

        var samplesByUUID: [UUID: HKSample] = [:]

        for workout in sourceWorkouts {
            let samples =
                try await associatedQuantitySamples(for: workout)

            for sample in samples {
                samplesByUUID[sample.uuid] = sample
            }
        }

        let sourceSamples =
            samplesByUUID.values.sorted {
                $0.startDate < $1.startDate
            }

        let sourceEvents =
            sourceWorkouts
                .flatMap { $0.workoutEvents ?? [] }
                .sorted {
                    $0.dateInterval.start
                        < $1.dateInterval.start
                }

        guard
            let start =
                sourceWorkouts.map(\.startDate).min(),
            let end =
                sourceWorkouts.map(\.endDate).max(),
            end > start,
            let sourceDevice =
                sourceWorkouts.first
        else {
            throw ReconcileError.operation(
                "bornes temporelles HealthKit invalides"
            )
        }

        let sourceDistance =
            distanceMeters(in: sourceWorkouts)

        let created =
            try await createHistoricalCorrectionWorkout(
                activity: targetActivity,
                start: start,
                end: end,
                sessionID: sessionID,
                source: sourceDevice,
                sourceWorkouts: sourceWorkouts,
                samples: sourceSamples,
                events: sourceEvents,
                locations: routeLocations
            )

        let replacementObjects: [HKObject] =
            [created.route, created.workout]
                .compactMap { $0 }

        do {
            // RELECTURE HealthKit : on ne fait pas confiance au seul callback.
            let verifiedWorkouts =
                try await sessionWorkouts(sessionID: sessionID)

            guard
                let verified = verifiedWorkouts.first(
                    where: {
                        $0.uuid == created.workout.uuid
                    }
                ),
                verified.workoutActivityType
                    == targetActivity.healthKitType,
                (verified.metadata?[manualCorrectionKey] as? Bool)
                    == true,
                abs(
                    verified.startDate
                        .timeIntervalSince(start)
                ) <= 1,
                abs(
                    verified.endDate
                        .timeIntervalSince(end)
                ) <= 1
            else {
                throw ReconcileError.operation(
                    "le workout de remplacement n’a pas passé la relecture HealthKit"
                )
            }

            let verifiedSamples =
                try await associatedQuantitySamples(
                    for: verified
                )

            guard
                verifiedSamples.count
                    >= sourceSamples.count
            else {
                throw ReconcileError.operation(
                    "des samples associés manquent sur le remplacement"
                )
            }

            if routeLocations.count >= 2 {
                let verifiedRoutes =
                    try await sessionRouteObjects(
                        sessionID: sessionID
                    )

                guard
                    let createdRoute = created.route,
                    verifiedRoutes.contains(
                        where: {
                            $0.uuid == createdRoute.uuid
                                && (
                                    $0.metadata?[
                                        manualCorrectionKey
                                    ] as? Bool
                                ) == true
                        }
                    )
                else {
                    throw ReconcileError.operation(
                        "la route reconstruite n’a pas passé la vérification"
                    )
                }
            }

            if sourceDistance > 1 {
                let replacementDistance =
                    distanceMeters(in: [verified])

                let tolerance =
                    max(
                        10,
                        sourceDistance * 0.03
                    )

                guard
                    abs(
                        replacementDistance
                            - sourceDistance
                    ) <= tolerance
                else {
                    throw ReconcileError.operation(
                        "distance du remplacement incohérente"
                    )
                }
            }
        } catch {
            // Aucune suppression de l'original :
            // on retire uniquement le remplacement inachevé.
            try? await deleteObjects(replacementObjects)
            throw error
        }

        // SEULEMENT APRÈS CRÉATION + RELECTURE + VÉRIFICATION.
        do {
            try await deleteObjects(sourceWorkouts)
        } catch {
            // Le workout original existe toujours :
            // rollback du nouveau.
            try? await deleteObjects(replacementObjects)

            throw ReconcileError.operation(
                "ancien workout impossible à supprimer ; original conservé"
            )
        }

        // Les routes sources ne sont supprimées qu'après le remplacement.
        // Si HealthKit les a déjà retirées avec le workout, l'erreur est ignorée.
        if !sourceRoutes.isEmpty {
            try? await deleteObjects(sourceRoutes)
        }

        // RELECTURE FINALE APRÈS SUPPRESSION.
        //
        // La première vérification prouve seulement que le remplacement
        // existait AVANT la suppression de la source. On doit maintenant
        // prouver qu'il a survécu à cette suppression.
        var postDeleteWorkouts: [HKWorkout] = []

        for attempt in 0..<4 {
            postDeleteWorkouts =
                try await sessionWorkouts(
                    sessionID: sessionID
                )

            if postDeleteWorkouts.contains(
                where: {
                    $0.uuid == created.workout.uuid
                }
            ) {
                break
            }

            if attempt < 3 {
                try await Task.sleep(
                    nanoseconds: 350_000_000
                )
            }
        }

        guard
            let durableReplacement =
                postDeleteWorkouts.first(
                    where: {
                        $0.uuid == created.workout.uuid
                    }
                ),
            durableReplacement.workoutActivityType
                == targetActivity.healthKitType,
            (
                durableReplacement.metadata?[
                    manualCorrectionKey
                ] as? Bool
            ) == true
        else {
            throw ReconcileError.operation(
                "le remplacement n’existe plus après suppression de la source"
            )
        }

        let sourceUUIDs =
            Set(sourceWorkouts.map { $0.uuid })

        guard
            !postDeleteWorkouts.contains(
                where: {
                    sourceUUIDs.contains($0.uuid)
                }
            )
        else {
            throw ReconcileError.operation(
                "une source HealthKit subsiste après la suppression"
            )
        }

        let postDeleteSamples =
            try await associatedQuantitySamples(
                for: durableReplacement
            )

        guard
            postDeleteSamples.count
                >= sourceSamples.count
        else {
            throw ReconcileError.operation(
                "les samples du remplacement ne sont pas durables après suppression"
            )
        }

        if routeLocations.count >= 2 {
            let postDeleteRoutes =
                try await sessionRouteObjects(
                    sessionID: sessionID
                )

            guard
                let expectedRoute = created.route,
                postDeleteRoutes.contains(
                    where: {
                        $0.uuid == expectedRoute.uuid
                            && (
                                $0.metadata?[
                                    manualCorrectionKey
                                ] as? Bool
                            ) == true
                    }
                )
            else {
                throw ReconcileError.operation(
                    "la route corrigée n’est plus présente après suppression"
                )
            }
        }

        return HistoricalRepairResult(
            alreadyCorrect: false,
            replacementUUID:
                created.workout.uuid.uuidString,
            sourceWorkoutCount:
                sourceWorkouts.count,
            sampleCount:
                sourceSamples.count,
            routePointCount:
                routeLocations.count
        )
    }

    private func createHistoricalCorrectionWorkout(
        activity: ActivityKind,
        start: Date,
        end: Date,
        sessionID: String,
        source: HKWorkout,
        sourceWorkouts: [HKWorkout],
        samples: [HKSample],
        events: [HKWorkoutEvent],
        locations: [CLLocation]
    ) async throws
        -> (
            workout: HKWorkout,
            route: HKWorkoutRoute?
        ) {

        let configuration =
            HKWorkoutConfiguration()

        configuration.activityType =
            activity.healthKitType

        configuration.locationType =
            locations.count >= 2
                ? .outdoor
                : .unknown

        let builder =
            HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: configuration,
                device: source.device
            )

        let routeBuilder =
            builder.seriesBuilder(
                for: HKSeriesType.workoutRoute()
            ) as? HKWorkoutRouteBuilder

        try await beginCollection(
            builder,
            start: start
        )

        try await addMetadata(
            [
                managedKey: true,
                sessionKey: sessionID,
                segmentedKey: true,
                manualCorrectionKey: true,
                correctionTargetKey:
                    activity.rawValue,
                correctionSourceUUIDsKey:
                    sourceWorkouts
                        .map { $0.uuid.uuidString }
                        .joined(separator: ","),
                segmentIndexKey: 0,
                segmentCountKey: 1,
                segmentActivityKey:
                    activity.rawValue,
                masterActivityKey:
                    activity.rawValue,
                algorithmKey:
                    "tracker-v4-20260910",
                buildKey:
                    BuildInfo.gitSHA,
            ],
            to: builder
        )

        if !samples.isEmpty {
            try await addSamples(
                samples,
                to: builder
            )
        }

        if !events.isEmpty {
            try await addEvents(
                events,
                to: builder
            )
        }

        if let routeBuilder,
           locations.count >= 2 {

            try await insertRoute(
                locations,
                into: routeBuilder
            )
        }

        try await endCollection(
            builder,
            end: end
        )

        guard
            let workout =
                try await finishWorkout(builder)
        else {
            throw ReconcileError.operation(
                "HealthKit n’a pas retourné le workout corrigé"
            )
        }

        guard
            let routeBuilder,
            locations.count >= 2
        else {
            return (workout, nil)
        }

        do {
            let route =
                try await finishRoute(
                    routeBuilder,
                    workout: workout,
                    metadata: [
                        managedKey: true,
                        sessionKey: sessionID,
                        segmentedKey: true,
                        manualCorrectionKey: true,
                        correctionTargetKey:
                            activity.rawValue,
                        correctionWorkoutUUIDKey:
                            workout.uuid.uuidString,
                    ]
                )

            return (workout, route)
        } catch {
            // Le workout venait d'être créé mais la route a échoué.
            // On retire ce remplacement et on garde l'original.
            try? await deleteObjects([workout])
            throw error
        }
    }

    private func distanceMeters(
        in workouts: [HKWorkout]
    ) -> Double {

        let identifiers: [
            HKQuantityTypeIdentifier
        ] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]

        return workouts.reduce(0) {
            partial, workout in

            partial
                + identifiers.reduce(0) {
                    subtotal, identifier in

                    guard
                        let type =
                            HKQuantityType
                                .quantityType(
                                    forIdentifier:
                                        identifier
                                ),
                        let quantity =
                            workout
                                .statistics(for: type)?
                                .sumQuantity()
                    else {
                        return subtotal
                    }

                    return subtotal
                        + quantity.doubleValue(
                            for: HKUnit.meter()
                        )
                }
        }
    }

    private func routePointCount(
        sessionID: String,
        correctionOnly: Bool
    ) async throws -> Int {

        let routes =
            try await sessionRouteObjects(
                sessionID: sessionID
            )

        var count = 0

        for route in routes {
            if correctionOnly,
               (route.metadata?[manualCorrectionKey]
                    as? Bool) != true {
                continue
            }

            count +=
                try await loadLocations(
                    for: route
                ).count
        }

        return count
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

    private func addSamples(
        _ samples: [HKSample],
        to builder: HKWorkoutBuilder
    ) async throws {
        let independentSamples =
            try cloneQuantitySamples(samples)

        try await checkedOperation { completion in
            builder.add(
                independentSamples,
                completion: completion
            )
        }
    }

    private func cloneQuantitySamples(
        _ samples: [HKSample]
    ) throws -> [HKSample] {
        try samples.map { sample in
            guard
                let quantitySample =
                    sample as? HKQuantitySample
            else {
                throw ReconcileError.operation(
                    "sample HealthKit non quantitatif impossible à cloner"
                )
            }

            return HKQuantitySample(
                type: quantitySample.quantityType,
                quantity: quantitySample.quantity,
                start: quantitySample.startDate,
                end: quantitySample.endDate,
                metadata: [
                    "com.rzbck.watchsensorlab.reconstructed_sample":
                        true,
                    "com.rzbck.watchsensorlab.source_sample_uuid":
                        quantitySample.uuid.uuidString,
                ]
            )
        }
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

        if session.isReachable {
            session.sendMessage(
                packet,
                replyHandler: nil,
                errorHandler: nil
            )
        } else {
            session.transferUserInfo(packet)
        }
    }
}
