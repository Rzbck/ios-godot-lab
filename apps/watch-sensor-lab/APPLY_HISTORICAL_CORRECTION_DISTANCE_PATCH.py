#!/usr/bin/env python3
"""Build-time safety patch for historical activity-type correction.

The normal Watch-owned correction path must not clone a walking/running distance
sample into a cycling workout. When Tracker's synchronized recent-history digest
is available and agrees with the saved HealthKit route geometry, that Tracker
summary distance is the scalar authority. Existing distance quantity samples are
removed and replaced with one quantity sample whose HealthKit type matches the
requested target activity.

The patch is intentionally deterministic and idempotent because both the iPhone
and Watch Xcode projects may invoke it during one CI checkout.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
TARGET = ROOT / "watch/Sources/WatchAutoHealthReconciler.swift"
MARKER = "com.rzbck.watchsensorlab.correction_distance_source"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def replace_n(text: str, old: str, new: str, expected: int, label: str) -> str:
    count = text.count(old)
    if count != expected:
        raise SystemExit(f"{label}: expected {expected} matches, got {count}")
    return text.replace(old, new)


text = TARGET.read_text(encoding="utf-8")

if MARKER in text:
    required = [
        "historicalCorrectionDistanceAuthority(",
        "makeHistoricalCorrectionSamples(",
        "verifyHistoricalCorrectionDistanceSamples(",
        "correction_distance_m",
    ]
    missing = [value for value in required if value not in text]
    if missing:
        raise SystemExit(f"historical correction distance patch incomplete: {missing}")
    print("HISTORICAL CORRECTION DISTANCE PATCH: already applied")
    raise SystemExit(0)

old_create_call = '''        let sourceDistance =
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
'''
new_create_call = '''        let sourceDistance =
            distanceMeters(in: sourceWorkouts)

        let distanceAuthority =
            try await historicalCorrectionDistanceAuthority(
                sessionID: sessionID,
                sourceDistance: sourceDistance,
                routeLocations: routeLocations
            )

        let correctionSamples =
            try makeHistoricalCorrectionSamples(
                sourceSamples,
                targetActivity: targetActivity,
                distanceMeters: distanceAuthority.meters,
                start: start,
                end: end,
                sessionID: sessionID
            )

        let created =
            try await createHistoricalCorrectionWorkout(
                activity: targetActivity,
                start: start,
                end: end,
                sessionID: sessionID,
                source: sourceDevice,
                sourceWorkouts: sourceWorkouts,
                samples: correctionSamples,
                events: sourceEvents,
                locations: routeLocations,
                authoritativeDistanceMeters: distanceAuthority.meters,
                distanceAuthoritySource: distanceAuthority.source
            )
'''
text = replace_once(text, old_create_call, new_create_call, "correction authority + samples")

text = replace_n(
    text,
    '''            guard
                verifiedSamples.count
                    >= sourceSamples.count
            else {''',
    '''            guard
                verifiedSamples.count
                    >= correctionSamples.count
            else {''',
    1,
    "pre-delete sample count",
)

old_distance_verify = '''            if sourceDistance > 1 {
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
'''
new_distance_verify = '''            try verifyHistoricalCorrectionDistanceSamples(
                verifiedSamples,
                targetActivity: targetActivity
            )

            if distanceAuthority.meters > 1 {
                let replacementDistance =
                    distanceMeters(in: [verified])

                let tolerance =
                    max(
                        10,
                        distanceAuthority.meters * 0.03
                    )

                guard
                    abs(
                        replacementDistance
                            - distanceAuthority.meters
                    ) <= tolerance
                else {
                    throw ReconcileError.operation(
                        "distance du remplacement incohérente"
                    )
                }
            }
'''
text = replace_once(text, old_distance_verify, new_distance_verify, "pre-delete distance verification")

text = replace_once(
    text,
    '''        guard
            postDeleteSamples.count
                >= sourceSamples.count
        else {''',
    '''        guard
            postDeleteSamples.count
                >= correctionSamples.count
        else {''',
    "post-delete sample count",
)

text = replace_once(
    text,
    '''        if routeLocations.count >= 2 {
            let postDeleteRoutes =''',
    '''        try verifyHistoricalCorrectionDistanceSamples(
            postDeleteSamples,
            targetActivity: targetActivity
        )

        if distanceAuthority.meters > 1 {
            let durableDistance = distanceMeters(in: [durableReplacement])
            let tolerance = max(10, distanceAuthority.meters * 0.03)
            guard abs(durableDistance - distanceAuthority.meters) <= tolerance else {
                throw ReconcileError.operation(
                    "distance corrigée non durable après suppression"
                )
            }
        }

        if routeLocations.count >= 2 {
            let postDeleteRoutes =''',
    "post-delete distance verification",
)

text = replace_once(
    text,
    '''            sampleCount:
                sourceSamples.count,
            routePointCount:''',
    '''            sampleCount:
                correctionSamples.count,
            routePointCount:''',
    "result sample count",
)

helper_marker = '''    private func createHistoricalCorrectionWorkout(
'''
helpers = '''    private func historicalCorrectionDistanceAuthority(
        sessionID: String,
        sourceDistance: Double,
        routeLocations: [CLLocation]
    ) async throws -> (meters: Double, source: String) {
        let recentHistoryDistance = await MainActor.run {
            WatchRecentHistoryStore.shared.activities
                .first(where: { $0.sessionID == sessionID })?
                .distanceMeters
        }

        guard let trackerDistance = recentHistoryDistance,
              trackerDistance > 1 else {
            guard sourceDistance > 1 else {
                throw ReconcileError.operation(
                    "aucune distance fiable disponible pour la correction"
                )
            }
            return (sourceDistance, "healthkit_source")
        }

        if routeLocations.count >= 2 {
            let routeGeometry = routeGeometryMeters(routeLocations)
            let tolerance = max(300, trackerDistance * 0.15)
            guard routeGeometry > 1,
                  abs(routeGeometry - trackerDistance) <= tolerance else {
                throw ReconcileError.operation(
                    "distance Tracker incompatible avec la route HealthKit ; original conservé"
                )
            }
            return (trackerDistance, "tracker_recent_history_route_validated")
        }

        if sourceDistance > 1 {
            let tolerance = max(50, trackerDistance * 0.05)
            guard abs(sourceDistance - trackerDistance) <= tolerance else {
                throw ReconcileError.operation(
                    "distance Tracker non vérifiable sans parcours ; original conservé"
                )
            }
        }

        return (trackerDistance, "tracker_recent_history")
    }

    private func routeGeometryMeters(_ locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<locations.count {
            total += locations[index].distance(from: locations[index - 1])
        }
        return total
    }

    private func makeHistoricalCorrectionSamples(
        _ samples: [HKSample],
        targetActivity: ActivityKind,
        distanceMeters: Double,
        start: Date,
        end: Date,
        sessionID: String
    ) throws -> [HKSample] {
        let distanceTypeIDs = Set([
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
            HKQuantityTypeIdentifier.distanceCycling.rawValue,
            HKQuantityTypeIdentifier.distanceSwimming.rawValue,
        ])

        var result = samples.filter { sample in
            guard let quantitySample = sample as? HKQuantitySample else {
                return true
            }
            return !distanceTypeIDs.contains(quantitySample.quantityType.identifier)
        }

        guard distanceMeters > 1 else { return result }
        guard let identifier = restoreDistanceIdentifier(for: targetActivity),
              let distanceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw ReconcileError.operation(
                "type de distance HealthKit cible indisponible"
            )
        }

        result.append(
            HKQuantitySample(
                type: distanceType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                start: start,
                end: end,
                metadata: [
                    "com.rzbck.watchsensorlab.reconstructed_sample": true,
                    "com.rzbck.watchsensorlab.correction_distance_authority": true,
                    sessionKey: sessionID,
                ]
            )
        )
        return result
    }

    private func verifyHistoricalCorrectionDistanceSamples(
        _ samples: [HKSample],
        targetActivity: ActivityKind
    ) throws {
        guard let expected = restoreDistanceIdentifier(for: targetActivity) else {
            return
        }

        let allDistanceIDs = Set([
            HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
            HKQuantityTypeIdentifier.distanceCycling.rawValue,
            HKQuantityTypeIdentifier.distanceSwimming.rawValue,
        ])
        let presentDistanceIDs = Set(
            samples.compactMap { sample -> String? in
                guard let quantitySample = sample as? HKQuantitySample else {
                    return nil
                }
                let identifier = quantitySample.quantityType.identifier
                return allDistanceIDs.contains(identifier) ? identifier : nil
            }
        )

        guard presentDistanceIDs == Set([expected.rawValue]) else {
            throw ReconcileError.operation(
                "le remplacement contient un type de distance incompatible avec l’activité cible"
            )
        }
    }

'''
text = replace_once(text, helper_marker, helpers + helper_marker, "historical correction helpers")

text = replace_once(
    text,
    '''        samples: [HKSample],
        events: [HKWorkoutEvent],
        locations: [CLLocation]
    ) async throws''',
    '''        samples: [HKSample],
        events: [HKWorkoutEvent],
        locations: [CLLocation],
        authoritativeDistanceMeters: Double,
        distanceAuthoritySource: String
    ) async throws''',
    "correction workout signature",
)

text = replace_once(
    text,
    '''                buildKey:
                    BuildInfo.gitSHA,
            ],''',
    '''                buildKey:
                    BuildInfo.gitSHA,
                "com.rzbck.watchsensorlab.correction_distance_m":
                    authoritativeDistanceMeters,
                "com.rzbck.watchsensorlab.correction_distance_source":
                    distanceAuthoritySource,
            ],''',
    "correction distance metadata",
)

# Final invariants. These fail the build instead of silently compiling an unsafe
# correction path if upstream source shape changes.
for required in [
    MARKER,
    "historicalCorrectionDistanceAuthority(",
    "makeHistoricalCorrectionSamples(",
    "verifyHistoricalCorrectionDistanceSamples(",
    "tracker_recent_history_route_validated",
    "distanceCycling.rawValue",
]:
    if required not in text:
        raise SystemExit(f"historical correction distance invariant missing: {required}")

TARGET.write_text(text, encoding="utf-8")
print("HISTORICAL CORRECTION DISTANCE PATCH: OK")
