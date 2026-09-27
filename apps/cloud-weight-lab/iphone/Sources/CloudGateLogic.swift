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
    ) -> (mask: [Bool], metrics: CloudGateMetrics) {
        let count = cloudProbabilities.count
        guard count > 0,
              skyProbabilities.count == count,
              blockerProbabilities.count == count else {
            return (
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

        var fallbackAccepted = 0
        var mask = [Bool](repeating: false, count: count)
        for index in 0..<count {
            let cloud = cloudProbabilities[index]
            guard cloud >= 0.52 else { continue }

            let blocker = blockerProbabilities[index]
            guard blocker < blockerThreshold else { continue }

            let sky = skyProbabilities[index]
            if sky >= strictSkyThreshold {
                mask[index] = true
                continue
            }

            guard isSkySceneActive else { continue }

            if sky >= relaxedSkyThreshold {
                mask[index] = true
                fallbackAccepted += 1
            } else if cloud >= strongCloudThreshold && blocker < 0.30 {
                mask[index] = true
                fallbackAccepted += 1
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
                skySceneActive: isSkySceneActive,
                mode: mode
            )
        )
    }

    private func fraction(_ values: [Double], predicate: (Double) -> Bool) -> Double {
        guard !values.isEmpty else { return 0 }
        let count = values.reduce(0) { $0 + (predicate($1) ? 1 : 0) }
        return Double(count) / Double(values.count)
    }
}
