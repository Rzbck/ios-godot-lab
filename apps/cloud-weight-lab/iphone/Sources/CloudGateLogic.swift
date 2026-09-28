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

    // V8/V11 used 0.52 as the UCloudNet geometry threshold and produced the
    // detailed contours the field tests preferred. Never let adaptive scene
    // logic lower the geometry below this floor: weak probability pixels were
    // bridging separate cloud cells into full-frame blobs.
    private let detailCloudThreshold = 0.52
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
                    cloudLowThreshold: detailCloudThreshold,
                    cloudHighThreshold: lowLight
                        ? strongCloudThresholdLowLight
                        : strongCloudThresholdDay,
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
            guard cloud >= detailCloudThreshold else { continue }

            let blocker = blockerProbabilities[index]
            guard blocker < blockerThreshold else { continue }

            let sky = skyProbabilities[index]
            let strictAccepted = sky >= strictSkyThreshold

            // Twilight/low-light fallback stays available, but only for a
            // genuinely strong UCloudNet response. This preserves evening
            // operation without allowing weak 0.42-0.51 bridges to glue
            // separate cloud structures together.
            let relaxedAccepted = isSkySceneActive
                && sky >= relaxedSkyThreshold
                && cloud >= strongCloudThreshold
            let strongFallback = isSkySceneActive
                && cloud >= strongCloudThreshold
                && blocker < 0.30

            guard strictAccepted || relaxedAccepted || strongFallback else { continue }

            mask[index] = true
            if !strictAccepted {
                fallbackAccepted += 1
            }
        }

        // Deliberately make the seed topology identical to the accepted mask.
        // CloudStructureAnalyzer then keeps one label per connected component
        // instead of regrowing every weak bridge around a few strong seeds.
        let seedMask = mask

        let mode: String
        if !isSkySceneActive {
            mode = enterCandidate ? "arming" : "no_sky"
        } else if strictSkyCoverage >= minimumStrictSceneCoverage {
            mode = "strict_detail"
        } else if relaxedSkyCoverage >= maximumRelaxedExitCoverage {
            mode = "semantic_fallback_detail"
        } else {
            mode = "hysteresis_hold_detail"
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
                cloudLowThreshold: detailCloudThreshold,
                cloudHighThreshold: strongCloudThreshold,
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
