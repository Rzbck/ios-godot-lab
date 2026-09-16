import Foundation
import HealthKit

/// Read-only inspection of workouts temporally surrounding one Tracker session.
///
/// This deliberately queries every HealthKit workout source so a workout started
/// later with Apple's Workout app can serve as an exact temporal boundary.
/// It never writes or deletes HealthKit objects.
@MainActor
struct NearbyHealthKitWorkoutDiagnostic {
    private static let recentSentinel = "__recent__"

    func inspect(sessionID: String) async throws -> [String: Any] {
        let recovery = HistoricalHealthKitRepairV4Coordinator.shared

        if sessionID == Self.recentSentinel {
            return try await inspectRecent(hours: 12, recovery: recovery)
        }

        let workoutType = HKObjectType.workoutType()

        let targetPredicate = HKQuery.predicateForObjects(
            withMetadataKey: recovery.sessionKey,
            allowedValues: [sessionID]
        )
        let targetSamples = try await recovery.querySamples(
            type: workoutType,
            predicate: targetPredicate
        )
        let targets = targetSamples.compactMap { $0 as? HKWorkout }
            .sorted { $0.startDate < $1.startDate }

        guard let target = targets.first else {
            return [
                "session_id": sessionID,
                "target_found": false,
                "target_uuid": NSNull(),
                "target_start_timestamp": NSNull(),
                "target_start_iso": NSNull(),
                "window_start_iso": NSNull(),
                "window_end_iso": NSNull(),
                "workout_count": 0,
                "workouts": [],
            ]
        }

        let beforeSeconds: TimeInterval = 5 * 60
        let afterSeconds: TimeInterval = 90 * 60
        let windowStart = target.startDate.addingTimeInterval(-beforeSeconds)
        let windowEnd = target.startDate.addingTimeInterval(afterSeconds)

        let timePredicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: windowEnd,
            options: [.strictStartDate]
        )

        let samples = try await recovery.querySamples(
            type: workoutType,
            predicate: timePredicate
        )

        let workouts = samples.compactMap { $0 as? HKWorkout }
            .sorted { $0.startDate < $1.startDate }

        return [
            "session_id": sessionID,
            "target_found": true,
            "target_uuid": target.uuid.uuidString,
            "target_start_timestamp": target.startDate.timeIntervalSince1970,
            "target_start_iso": iso(target.startDate),
            "window_start_iso": iso(windowStart),
            "window_end_iso": iso(windowEnd),
            "workout_count": workouts.count,
            "workouts": workouts.map {
                workoutSnapshot(
                    $0,
                    targetStart: target.startDate,
                    sessionID: sessionID,
                    recovery: recovery
                )
            },
        ]
    }

    private func inspectRecent(
        hours: Double,
        recovery: HistoricalHealthKitRepairV4Coordinator
    ) async throws -> [String: Any] {
        let windowEnd = Date()
        let windowStart = windowEnd.addingTimeInterval(-max(1, hours) * 3600)
        let workoutType = HKObjectType.workoutType()
        let timePredicate = HKQuery.predicateForSamples(
            withStart: windowStart,
            end: windowEnd,
            options: [.strictStartDate]
        )
        let samples = try await recovery.querySamples(
            type: workoutType,
            predicate: timePredicate
        )
        let workouts = samples.compactMap { $0 as? HKWorkout }
            .sorted { $0.startDate < $1.startDate }

        return [
            "session_id": Self.recentSentinel,
            "target_found": false,
            "target_uuid": NSNull(),
            "target_start_timestamp": NSNull(),
            "target_start_iso": NSNull(),
            "window_start_iso": iso(windowStart),
            "window_end_iso": iso(windowEnd),
            "workout_count": workouts.count,
            "workouts": workouts.map {
                workoutSnapshot(
                    $0,
                    targetStart: windowStart,
                    sessionID: "",
                    recovery: recovery
                )
            },
        ]
    }

    private func workoutSnapshot(
        _ workout: HKWorkout,
        targetStart: Date,
        sessionID: String,
        recovery: HistoricalHealthKitRepairV4Coordinator
    ) -> [String: Any] {
        let source = workout.sourceRevision
        let activity = ActivityKind(
            healthKitType: workout.workoutActivityType
        ) ?? .other

        let metadataSessionID =
            workout.metadata?[recovery.sessionKey] as? String

        return [
            "uuid": workout.uuid.uuidString,
            "activity": activity.rawValue,
            "activity_raw": workout.workoutActivityType.rawValue,
            "start_timestamp": workout.startDate.timeIntervalSince1970,
            "end_timestamp": workout.endDate.timeIntervalSince1970,
            "start_iso": iso(workout.startDate),
            "end_iso": iso(workout.endDate),
            "duration_s": workout.duration,
            "wall_duration_s": workout.endDate.timeIntervalSince(workout.startDate),
            "seconds_from_target_start":
                workout.startDate.timeIntervalSince(targetStart),
            "distance_m": nullableDouble(
                recovery.workoutDistanceMeters(
                    workout,
                    activity: activity
                )
            ),
            "source_name": source.source.name,
            "source_bundle": source.source.bundleIdentifier,
            "source_version": nullableString(source.version),
            "source_product_type": nullableString(source.productType),
            "tracker_session_id": nullableString(metadataSessionID),
            "is_target_session": !sessionID.isEmpty && metadataSessionID == sessionID,
            "source_matches_installed_bundle":
                source.source.bundleIdentifier == Bundle.main.bundleIdentifier,
            "device_name": nullableString(workout.device?.name),
            "device_model": nullableString(workout.device?.model),
            "device_hardware_version":
                nullableString(workout.device?.hardwareVersion),
        ]
    }

    private func nullableString(_ value: String?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func nullableDouble(_ value: Double?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
