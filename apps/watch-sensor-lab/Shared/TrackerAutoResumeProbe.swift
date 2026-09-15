import Foundation

/// Pure, platform-neutral filter for movement observed while the authoritative
/// workout is auto-paused. It never owns route/distance state: production only
/// uses the resulting speed as resume evidence.
struct TrackerAutoResumeProbe: Equatable {
    private(set) var filteredSpeedMps: Double = 0
    private(set) var lastSampleTimestamp: TimeInterval?
    private(set) var lastHorizontalAccuracy: Double = -1
    private(set) var lastSpeedAccuracy: Double = -1
    private(set) var lastSampleReliable = false
    private(set) var lastUsedNativeSpeed = false
    private(set) var consecutiveReliableMovementSamples = 0

    mutating func reset() {
        filteredSpeedMps = 0
        lastSampleTimestamp = nil
        lastHorizontalAccuracy = -1
        lastSpeedAccuracy = -1
        lastSampleReliable = false
        lastUsedNativeSpeed = false
        consecutiveReliableMovementSamples = 0
    }

    @discardableResult
    mutating func observe(
        sampleTimestamp: TimeInterval,
        now: TimeInterval,
        horizontalAccuracy: Double,
        nativeSpeedMps: Double,
        speedAccuracyMps: Double = 0,
        derivedSpeedMps: Double,
        plausibleMaxSpeedMps: Double
    ) -> Double? {
        if let lastSampleTimestamp, sampleTimestamp <= lastSampleTimestamp {
            return nil
        }

        lastSampleTimestamp = sampleTimestamp
        lastHorizontalAccuracy = horizontalAccuracy
        lastSpeedAccuracy = speedAccuracyMps
        lastSampleReliable = false
        lastUsedNativeSpeed = false

        guard horizontalAccuracy >= 0, horizontalAccuracy <= 25 else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }
        guard abs(now - sampleTimestamp) <= 3 else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }
        guard plausibleMaxSpeedMps > 0 else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }

        let nativeReliable: Bool
        if nativeSpeedMps >= 0, speedAccuracyMps >= 0 {
            // Apple defines speedAccuracy as ± uncertainty in m/s. Reject a
            // speed whose uncertainty is of the same order as the movement.
            let allowedUncertainty = max(0.45, nativeSpeedMps * 0.75)
            nativeReliable = speedAccuracyMps <= allowedUncertainty
        } else {
            nativeReliable = false
        }

        let derivedReliable = !nativeReliable
            && (nativeSpeedMps < 0 || speedAccuracyMps < 0)
            && horizontalAccuracy <= 8
            && derivedSpeedMps.isFinite
            && derivedSpeedMps >= 0

        let rawSpeed: Double
        if nativeReliable {
            rawSpeed = nativeSpeedMps
            lastUsedNativeSpeed = true
        } else if derivedReliable {
            rawSpeed = derivedSpeedMps
            lastUsedNativeSpeed = false
        } else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }

        guard rawSpeed.isFinite, rawSpeed >= 0 else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }
        guard rawSpeed <= plausibleMaxSpeedMps * 1.35 else {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
            return nil
        }

        lastSampleReliable = true
        let clipped = min(rawSpeed, plausibleMaxSpeedMps)

        if clipped < 0.25 {
            filteredSpeedMps = 0
            consecutiveReliableMovementSamples = 0
        } else {
            consecutiveReliableMovementSamples += 1
            if filteredSpeedMps == 0 {
                filteredSpeedMps = clipped
            } else {
                filteredSpeedMps = filteredSpeedMps * 0.40 + clipped * 0.60
            }
        }

        return filteredSpeedMps
    }

    func isFresh(
        now: TimeInterval,
        maxAge: TimeInterval = 2.5
    ) -> Bool {
        guard
            let lastSampleTimestamp,
            lastSampleReliable,
            now >= lastSampleTimestamp,
            now - lastSampleTimestamp <= maxAge
        else {
            return false
        }
        return true
    }

    func sampleAge(now: TimeInterval) -> TimeInterval {
        guard let lastSampleTimestamp, now >= lastSampleTimestamp else {
            return .infinity
        }
        return now - lastSampleTimestamp
    }

    // Kept at five seconds for diagnostic/backward-compatible callers. The
    // production resume policy separately requires isFresh(..., 2.5 s) and
    // sustained movement, so an older diagnostic read cannot wake a workout.
    func recentSpeedMps(
        now: TimeInterval,
        maxAge: TimeInterval = 5
    ) -> Double {
        guard isFresh(now: now, maxAge: maxAge) else { return 0 }
        return filteredSpeedMps
    }

    func hasSustainedMovement(
        now: TimeInterval,
        maxAge: TimeInterval = 2.5
    ) -> Bool {
        guard isFresh(now: now, maxAge: maxAge) else { return false }
        let minimumSamples = lastUsedNativeSpeed ? 2 : 3
        return consecutiveReliableMovementSamples >= minimumSamples
    }
}
