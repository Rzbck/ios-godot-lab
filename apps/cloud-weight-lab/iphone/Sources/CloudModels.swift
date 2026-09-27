import CoreGraphics
import Foundation

enum CloudKind: String, CaseIterable {
    case cumulus = "Cumulus"
    case stratocumulus = "Stratocumulus"
    case stratus = "Stratus"
    case cirrus = "Cirrus"
    case unknown = "Nuage"

    // Representative height above observer, not a measured cloud-base height.
    // Ranges are intentionally broad because a single RGB frame cannot recover distance.
    var altitudeMeters: ClosedRange<Double> {
        switch self {
        case .cumulus: return 500...3_000
        case .stratocumulus: return 400...2_500
        case .stratus: return 100...1_500
        case .cirrus: return 5_000...13_000
        case .unknown: return 300...6_000
        }
    }

    // Condensed liquid/ice water content prior, in g/m3.
    var waterContentGramsPerCubicMeter: ClosedRange<Double> {
        switch self {
        case .cumulus: return 0.20...2.50
        case .stratocumulus: return 0.10...1.00
        case .stratus: return 0.05...0.50
        case .cirrus: return 0.005...0.12
        case .unknown: return 0.03...1.20
        }
    }

    // Line-of-sight cloud depth relative to the square root of projected area.
    var depthRatio: ClosedRange<Double> {
        switch self {
        case .cumulus: return 0.35...1.20
        case .stratocumulus: return 0.15...0.60
        case .stratus: return 0.05...0.18
        case .cirrus: return 0.05...0.25
        case .unknown: return 0.10...0.80
        }
    }
}

enum SegmentationEngine: String {
    case ucloudNetCoreML = "UCLOUDNET · CORE ML"
}

struct CloudObservation: Equatable, Identifiable {
    let id: Int
    let kind: CloudKind
    let confidence: Double
    let coverage: Double
    let bounds: CGRect
    let centroid: CGPoint
    let averageBrightness: Double
    let averageSaturation: Double
    let fieldOfViewDegrees: Double
}

struct CloudFrameAnalysis {
    let timestamp: Date
    let observations: [CloudObservation]
    let totalCoverage: Double
    let overlayImage: CGImage?
    let engine: SegmentationEngine
    let fieldOfViewDegrees: Double
}

struct CloudMassEstimate: Equatable {
    let lowKilograms: Double
    let midpointKilograms: Double
    let highKilograms: Double
    let estimatedWidthMeters: Double
    let estimatedHeightMeters: Double
    let estimatedDepthMeters: Double
    let estimatedDistanceMeters: Double
    let projectedAreaSquareMeters: Double
    let estimatedVolumeCubicMeters: Double
    let angularWidthDegrees: Double
    let angularHeightDegrees: Double
    let centerElevationDegrees: Double
    let confidence: Double
}

struct CloudDetection: Equatable, Identifiable {
    let observation: CloudObservation
    let estimate: CloudMassEstimate

    var id: Int { observation.id }
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
