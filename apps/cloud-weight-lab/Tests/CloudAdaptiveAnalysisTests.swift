import XCTest
@testable import CloudWeightLab

final class CloudAdaptiveAnalysisTests: XCTestCase {
    func testDetailGateDoesNotRegrowWeakProbabilityBridges() {
        let gate = CloudSemanticGate()
        let count = 200
        let sky = Array(repeating: 0.85, count: count)
        let blocker = Array(repeating: 0.02, count: count)

        var cloud = Array(repeating: 0.20, count: count)
        for index in 40..<80 {
            cloud[index] = 0.88
        }
        for index in 80..<120 {
            cloud[index] = 0.50
        }
        for index in 120..<160 {
            cloud[index] = 0.88
        }

        let result = gate.makeMask(
            cloudProbabilities: cloud,
            skyProbabilities: sky,
            blockerProbabilities: blocker,
            classCoverage: .zero,
            lowLight: false
        )

        XCTAssertEqual(result.metrics.cloudLowThreshold, 0.52, accuracy: 0.0001)
        XCTAssertEqual(result.mask, result.seedMask)
        XCTAssertEqual(result.mask.filter { $0 }.count, 80)
        XCTAssertTrue(result.mask[80..<120].allSatisfy { !$0 })
    }

    func testAdaptiveGateDoesNotAcceptCloudProbabilityWithoutSkyEvidence() {
        let gate = CloudSemanticGate()
        let count = 160
        let result = gate.makeMask(
            cloudProbabilities: Array(repeating: 0.95, count: count),
            skyProbabilities: Array(repeating: 0.01, count: count),
            blockerProbabilities: Array(repeating: 0.05, count: count),
            classCoverage: .zero,
            lowLight: false
        )

        XCTAssertTrue(result.mask.allSatisfy { !$0 })
        XCTAssertTrue(result.seedMask.allSatisfy { !$0 })
    }

    func testBroadUniformLayerClassifiesAsStratus() {
        let region = makeRegion(
            width: 0.95,
            height: 0.76,
            frameCoverage: 0.66,
            parentCoverage: 0.66,
            fill: 0.91,
            boundaryRatio: 1.04,
            compactness: 0.72,
            brightnessStdDev: 0.025,
            probabilityStdDev: 0.030,
            edgeTouchCount: 3,
            split: false
        )

        XCTAssertEqual(CloudStructureAnalyzer.classify(region), .stratus)
    }

    func testTexturedBroadLayerClassifiesAsStratocumulus() {
        let region = makeRegion(
            width: 0.94,
            height: 0.72,
            frameCoverage: 0.58,
            parentCoverage: 0.72,
            fill: 0.78,
            boundaryRatio: 1.55,
            compactness: 0.34,
            brightnessStdDev: 0.12,
            probabilityStdDev: 0.10,
            edgeTouchCount: 2,
            split: true
        )

        XCTAssertEqual(CloudStructureAnalyzer.classify(region), .stratocumulus)
    }

    func testCompactIsolatedHeapClassifiesAsCumulus() {
        let region = makeRegion(
            width: 0.25,
            height: 0.22,
            frameCoverage: 0.040,
            parentCoverage: 0.040,
            fill: 0.73,
            boundaryRatio: 1.15,
            compactness: 0.63,
            brightnessStdDev: 0.07,
            probabilityStdDev: 0.06,
            edgeTouchCount: 0,
            split: false
        )

        XCTAssertEqual(CloudStructureAnalyzer.classify(region), .cumulus)
    }

    func testThinFibrousRegionClassifiesAsCirrus() {
        let region = makeRegion(
            width: 0.54,
            height: 0.10,
            frameCoverage: 0.024,
            parentCoverage: 0.024,
            fill: 0.44,
            boundaryRatio: 1.62,
            compactness: 0.24,
            brightnessStdDev: 0.08,
            probabilityStdDev: 0.08,
            edgeTouchCount: 0,
            split: false,
            brightness: 0.78,
            saturation: 0.12
        )

        XCTAssertEqual(CloudStructureAnalyzer.classify(region), .cirrus)
    }

    func testMorphologyIsIndependentOfPortraitLandscapePixelAspect() {
        let portrait = makeRegion(
            width: 0.72,
            height: 0.20,
            frameCoverage: 0.10,
            parentCoverage: 0.10,
            fill: 0.56,
            boundaryRatio: 1.50,
            compactness: 0.28,
            brightnessStdDev: 0.08,
            probabilityStdDev: 0.07,
            edgeTouchCount: 0,
            split: false,
            brightness: 0.76,
            saturation: 0.12
        )
        let landscape = makeRegion(
            width: 0.72,
            height: 0.20,
            frameCoverage: 0.10,
            parentCoverage: 0.10,
            fill: 0.56,
            boundaryRatio: 1.50,
            compactness: 0.28,
            brightnessStdDev: 0.08,
            probabilityStdDev: 0.07,
            edgeTouchCount: 0,
            split: false,
            brightness: 0.76,
            saturation: 0.12
        )

        XCTAssertEqual(
            CloudStructureAnalyzer.classify(portrait),
            CloudStructureAnalyzer.classify(landscape)
        )
    }

    private func makeRegion(
        width: Double,
        height: Double,
        frameCoverage: Double,
        parentCoverage: Double,
        fill: Double,
        boundaryRatio: Double,
        compactness: Double,
        brightnessStdDev: Double,
        probabilityStdDev: Double,
        edgeTouchCount: Int,
        split: Bool,
        brightness: Double = 0.68,
        saturation: Double = 0.16
    ) -> CloudStructureRegion {
        let frameWidth = 1_000
        let frameHeight = 1_000
        let pixelWidth = max(1, Int(width * Double(frameWidth)))
        let pixelHeight = max(1, Int(height * Double(frameHeight)))
        let area = max(1, Int(frameCoverage * Double(frameWidth * frameHeight)))

        return CloudStructureRegion(
            label: 0,
            area: area,
            minX: 0,
            minY: 0,
            maxX: pixelWidth - 1,
            maxY: pixelHeight - 1,
            centroidX: Double(pixelWidth) * 0.5,
            centroidY: Double(pixelHeight) * 0.5,
            normalizedWidth: width,
            normalizedHeight: height,
            meanProbability: 0.78,
            probabilityStdDev: probabilityStdDev,
            highConfidenceFraction: 0.58,
            meanBrightness: brightness,
            brightnessStdDev: brightnessStdDev,
            meanSaturation: saturation,
            saturationStdDev: 0.04,
            fillRatio: fill,
            boundaryRatio: boundaryRatio,
            compactness: compactness,
            edgeTouchCount: edgeTouchCount,
            frameCoverage: frameCoverage,
            parentCoverage: parentCoverage,
            parentWasSplit: split
        )
    }
}
