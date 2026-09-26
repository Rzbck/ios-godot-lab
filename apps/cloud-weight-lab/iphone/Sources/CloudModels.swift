import Foundation
import CoreGraphics

enum CloudKind: String, CaseIterable {
    case cumulus = "Cumulus"
    case stratocumulus = "Stratocumulus"
    case stratus = "Stratus"
    case cirrus = "Cirrus"
    case unknown = "Nuage"

    var altitudeMeters: ClosedRange<Double> {
        switch self {
        case .cumulus: return 800...2_500
        case .stratocumulus: return 600...2_000
        case .stratus: return 200...1_200
        case .cirrus: return 6_000...12_000
        case .unknown: return 800...4_000
        }
    }

    var waterContentGramsPerCubicMeter: ClosedRange<Double> {
        switch self {
        case .cumulus: return 0.20...1.00
        case .stratocumulus: return 0.15...0.60
        case .stratus: return 0.10...0.50
        case .cirrus: return 0.01...0.08
        case .unknown: return 0.05...0.80
        }
    }

    var depthRatio: ClosedRange<Double> {
        switch self {
        case .cumulus: return 0.50...1.30
        case .stratocumulus: return 0.25...0.70
        case .stratus: return 0.08...0.25
        case .cirrus: return 0.05...0.20
        case .unknown: return 0.20...0.80
        }
    }
}

struct CloudFrameAnalysis: Equatable {
    let timestamp: Date
    let kind: CloudKind
    let confidence: Double
    let coverage: Double
    let bounds: CGRect
    let averageBrightness: Double
    let averageSaturation: Double
    let fieldOfViewDegrees: Double
}

struct CloudMassEstimate: Equatable {
    let lowKilograms: Double
    let midpointKilograms: Double
    let highKilograms: Double
    let estimatedWidthMeters: Double
    let estimatedHeightMeters: Double
    let confidence: Double
}

extension Double {
    func clamped(_ range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
