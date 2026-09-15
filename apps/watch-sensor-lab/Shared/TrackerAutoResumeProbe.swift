import Foundation

/// Pure, platform-neutral filter for movement observed while the authoritative
/// workout is auto-paused. It never owns route/distance state: production only
/// uses the resulting speed as evidence that an auto-paused workout should
/// resume.
struct TrackerAutoResumeProbe: Equatable {
    private(set) var filteredSpeedMps: Double = 0
    private(set) var lastSampleTimestamp: TimeInterval?
    private(set) var consecutiveMovingSamples = 0

    mutating func reset() {
        filteredSpeedMps = 0
        lastSampleTimestamp = nil
        consecutiveMovingSamples = 0
    }

    @discardableResult
    mutating func observe(
        sampleTimestamp: TimeInterval,
        now: TimeInterval,
        horizontalAccuracy: Double,
        nativeSpeedMps: Double,
        derivedSpeedMps: Double,
        plausibleMaxSpeedMps: Double,
        speedAccuracyMps: Double = -1
    ) -> Double? {
        guard horizontalAccuracy >= 0, horizontalAccuracy <= 35 else { return nil }
        guard speedAccuracyMps < 0 || speedAccuracyMps <= 3 else { return nil }
        guard abs(now - sampleTimestamp) <= 10 else { return nil }
        guard plausibleMaxSpeedMps > 0 else { return nil }
        if let lastSampleTimestamp, sampleTimestamp <= lastSampleTimestamp { return nil }

        // A pair of fixes separated by a long silence is not a coherent
        // movement observation. Treat the later fix as a new first sample.
        if let lastSampleTimestamp, sampleTimestamp - lastSampleTimestamp > 8 {
            filteredSpeedMps = 0
            consecutiveMovingSamples = 0
        }

        let rawSpeed = nativeSpeedMps >= 0 ? nativeSpeedMps : derivedSpeedMps
        guard rawSpeed.isFinite, rawSpeed >= 0 else { return nil }
        guard rawSpeed <= plausibleMaxSpeedMps * 1.35 else { return nil }

        let clipped = min(rawSpeed, plausibleMaxSpeedMps)
        if clipped < 0.20 {
            filteredSpeedMps = 0
            consecutiveMovingSamples = 0
        } else if filteredSpeedMps == 0 {
            filteredSpeedMps = clipped
            consecutiveMovingSamples = 1
        } else {
            // Fast attack so a rider restarting from a traffic light is not
            // trapped in pause, with enough smoothing to reject one noisy fix.
            filteredSpeedMps = filteredSpeedMps * 0.35 + clipped * 0.65
            consecutiveMovingSamples += 1
        }

        self.lastSampleTimestamp = sampleTimestamp
        return filteredSpeedMps
    }

    func recentSpeedMps(
        now: TimeInterval,
        maxAge: TimeInterval = 5
    ) -> Double {
        guard
            let lastSampleTimestamp,
            now >= lastSampleTimestamp,
            now - lastSampleTimestamp <= maxAge
        else {
            return 0
        }
        return filteredSpeedMps
    }

    /// One location callback is not sufficient to wake an auto-paused
    /// workout. The speed must come from at least two recent, plausible fixes.
    func confirmedRecentSpeedMps(
        now: TimeInterval,
        maxAge: TimeInterval = 5
    ) -> Double {
        guard consecutiveMovingSamples >= 2 else { return 0 }
        return recentSpeedMps(now: now, maxAge: maxAge)
    }
}
