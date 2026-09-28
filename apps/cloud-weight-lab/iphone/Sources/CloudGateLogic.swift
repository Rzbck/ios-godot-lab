import Foundation

struct CloudGateMetrics: Equatable {
    let strictSkyCoveragePercent: Double
    let relaxedSkyCoveragePercent: Double
    let blockerCoveragePercent: Double
    let treeCoveragePercent: Double
    let buildingCoveragePercent: Double
    let personCoveragePercent: Double
    let plantCoveragePercent: Double
    let wallCoveragePercent: Double
    let semanticFallbackCoveragePercent: Double
    let cloudLowThreshold: Double
    let cloudHighThreshold: Double
    let skySceneActive: Bool
    let mode: String
}

struct CloudSemanticClassCoverage: Equatable {
    let treePercent: Double
    let buildingPercent: Double
    let personPercent: Double
    let plantPercent: Double
    let wallPercent: Double

    static let zero = CloudSemanticClassCoverage(
        treePercent: 0,
        buildingPercent: 0,
        personPercent: 0,
        plantPercent: 0,
        wallPercent: 0
    )
}

final class CloudSemanticGate {
    private let strictSkyThreshold = 0.55
    private let relaxedSkyThresholdDay = 0.20
    private let relaxedSkyThresholdLowLight = 0.12
    private let blockerThreshold = 0.48
    private let strongCloudThresholdDay = 0.68
    private let strongCloudThresholdLowLight = 0.62

    private let minimumStrictSceneCoverage = 0.05
    private let minimumRelaxedSceneCoverage = 0.12
    private let maximumRelaxedExitCoverage = 0.03
    private let maximumStrictExitCoverage = 0.01
    private let maximumBlockerSceneCoverage = 0.70
    private let enterFrames = 2
    private let exitFrames = 18

    private(set) var isSkySceneActive = false
    private var enterStreak = 0
    private var exitStreak = 0

    func reset() {
        isSkySceneActive = false
        enterStreak = 0
        exitStreak = 0
    }

    func makeMask(
        cloudProbabilities: [Double],
        skyProbabilities: [Double],
        blockerProbabilities: [Double],
        classCoverage: CloudSemanticClassCoverage,
        lowLight: Bool
    ) -> (mask: [Bool], seedMask: [Bool], metrics: CloudGateMetrics) {
        let count = cloudProbabilities.count
        guard count > 0,
              skyProbabilities.count == count,
              blockerProbabilities.count == count else {
            return (
                [],
                [],
                CloudGateMetrics(
                    strictSkyCoveragePercent: 0,
                    relaxedSkyCoveragePercent: 0,
                    blockerCoveragePercent: 0,
                    treeCoveragePercent: 0,
                    buildingCoveragePercent: 0,
                    personCoveragePercent: 0,
                    plantCoveragePercent: 0,
                    wallCoveragePercent: 0,
                    semanticFallbackCoveragePercent: 0,
                    cloudLowThreshold: lowLight ? 0.46 : 0.50,
                    cloudHighThreshold: lowLight ? 0.60 : 0.64,
                    skySceneActive: false,
                    mode: "invalid"
                )
            )
        }

        let relaxedSkyThreshold = lowLight ? relaxedSkyThresholdLowLight : relaxedSkyThresholdDay
        let strongCloudThreshold = lowLight ? strongCloudThresholdLowLight : strongCloudThresholdDay

        let strictSkyCoverage = fraction(skyProbabilities) { $0 >= strictSkyThreshold }
        let relaxedSkyCoverage = fraction(skyProbabilities) { $0 >= relaxedSkyThreshold }
        let blockerCoverage = fraction(blockerProbabilities) { $0 >= blockerThreshold }

        let enterCandidate = blockerCoverage < 0.45 && (
            strictSkyCoverage >= minimumStrictSceneCoverage
            || relaxedSkyCoverage >= minimumRelaxedSceneCoverage
        )

        if !isSkySceneActive {
            if enterCandidate {
                enterStreak += 1
                if enterStreak >= enterFrames {
                    isSkySceneActive = true
                    enterStreak = 0
                    exitStreak = 0
                }
            } else {
                enterStreak = 0
            }
        } else {
            let exitCandidate = (
                strictSkyCoverage < maximumStrictExitCoverage
                && relaxedSkyCoverage < maximumRelaxedExitCoverage
            ) || blockerCoverage > maximumBlockerSceneCoverage

            if exitCandidate {
                exitStreak += 1
                if exitStreak >= exitFrames {
                    isSkySceneActive = false
                    exitStreak = 0
                    enterStreak = 0
                }
            } else {
                exitStreak = 0
            }
        }

        let thresholds = adaptiveCloudThresholds(
            cloudProbabilities: cloudProbabilities,
            skyProbabilities: skyProbabilities,
            blockerProbabilities: blockerProbabilities,
            relaxedSkyThreshold: relaxedSkyThreshold,
            lowLight: lowLight
        )

        var fallbackAccepted = 0
        var mask = [Bool](repeating: false, count: count)
        var seedMask = [Bool](repeating: false, count: count)

        for index in 0..<count {
            let cloud = cloudProbabilities[index]
            guard cloud >= thresholds.low else { continue }

            let blocker = blockerProbabilities[index]
            guard blocker < blockerThreshold else { continue }

            let sky = skyProbabilities[index]
            let strictAccepted = sky >= strictSkyThreshold
            let relaxedAccepted = isSkySceneActive && sky >= relaxedSkyThreshold
            let strongFallback = isSkySceneActive
                && cloud >= strongCloudThreshold
                && blocker < 0.30

            guard strictAccepted || relaxedAccepted || strongFallback else { continue }

            mask[index] = true

            if !strictAccepted {
                fallbackAccepted += 1
            }

            if cloud >= thresholds.high || strongFallback {
                seedMask[index] = true
            }
        }

        let mode: String
        if !isSkySceneActive {
            mode = enterCandidate ? "arming" : "no_sky"
        } else if strictSkyCoverage >= minimumStrictSceneCoverage {
            mode = "strict"
        } else if relaxedSkyCoverage >= maximumRelaxedExitCoverage {
            mode = "semantic_fallback"
        } else {
            mode = "hysteresis_hold"
        }

        return (
            mask,
            seedMask,
            CloudGateMetrics(
                strictSkyCoveragePercent: strictSkyCoverage * 100,
                relaxedSkyCoveragePercent: relaxedSkyCoverage * 100,
                blockerCoveragePercent: blockerCoverage * 100,
                treeCoveragePercent: classCoverage.treePercent,
                buildingCoveragePercent: classCoverage.buildingPercent,
                personCoveragePercent: classCoverage.personPercent,
                plantCoveragePercent: classCoverage.plantPercent,
                wallCoveragePercent: classCoverage.wallPercent,
                semanticFallbackCoveragePercent: Double(fallbackAccepted) / Double(count) * 100,
                cloudLowThreshold: thresholds.low,
                cloudHighThreshold: thresholds.high,
                skySceneActive: isSkySceneActive,
                mode: mode
            )
        )
    }

    private func adaptiveCloudThresholds(
        cloudProbabilities: [Double],
        skyProbabilities: [Double],
        blockerProbabilities: [Double],
        relaxedSkyThreshold: Double,
        lowLight: Bool
    ) -> (low: Double, high: Double) {
        let bins = 48
        var histogram = [Int](repeating: 0, count: bins)
        var sampleCount = 0

        for index in cloudProbabilities.indices {
            guard blockerProbabilities[index] < blockerThreshold else { continue }

            let sky = skyProbabilities[index]
            guard sky >= relaxedSkyThreshold || isSkySceneActive else { continue }

            let value = cloudProbabilities[index].clamped(0...1)
            let bin = min(bins - 1, Int(value * Double(bins)))
            histogram[bin] += 1
            sampleCount += 1
        }

        let baseLow = lowLight ? 0.46 : 0.50
        let lowRange = lowLight ? 0.42...0.55 : 0.46...0.57

        guard sampleCount >= max(32, cloudProbabilities.count / 100) else {
            let low = baseLow
            return (low, lowLight ? 0.60 : 0.64)
        }

        func quantile(_ fraction: Double) -> Double {
            let target = max(1, Int(Double(sampleCount) * fraction))
            var cumulative = 0
            for bin in histogram.indices {
                cumulative += histogram[bin]
                if cumulative >= target {
                    return (Double(bin) + 0.5) / Double(bins)
                }
            }
            return 1
        }

        let q25 = quantile(0.25)
        let q50 = quantile(0.50)
        let q75 = quantile(0.75)
        let spread = max(0.02, q75 - q25)

        // UCloudNet is trained for both day and night scenes. Keep its full
        // probability distribution instead of collapsing every scene at one
        // hard threshold. The adjustment is deliberately bounded so semantic
        // blockers remain the primary false-positive protection.
        let medianAdjustment = (q50 - 0.50) * 0.10
        let spreadAdjustment = (0.16 - spread).clamped(-0.10...0.10) * 0.10
        let low = (baseLow + medianAdjustment + spreadAdjustment).clamped(lowRange)

        // A high-confidence seed threshold drives hysteresis / region growth.
        // Clear scenes stay conservative; overcast scenes keep weak cloud edges
        // as long as they connect back to a strong UCloudNet core.
        let minimumHigh = low + (lowLight ? 0.10 : 0.11)
        let maximumHigh = lowLight ? 0.76 : 0.80
        let high = max(minimumHigh, q75 - 0.04)
            .clamped(minimumHigh...maximumHigh)

        return (low, high)
    }

    private func fraction(_ values: [Double], predicate: (Double) -> Bool) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = values.reduce(0) { $0 + (predicate($1) ? 1 : 0) }
        return Double(count) / Double(values.count)
    }
}
