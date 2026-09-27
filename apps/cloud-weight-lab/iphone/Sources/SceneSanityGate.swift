import AVFoundation
import Foundation

struct SceneSanityResult: Equatable {
    let meanLuminance: Double
    let meanSaturation: Double
    let darkFraction: Double
    let brightFraction: Double
    let clippedFraction: Double
    let neutralHighlightFraction: Double
    let rejected: Bool
}

enum SceneSanityGate {
    // V12 only rejects an almost-black image. Dusk/night is allowed through so
    // the semantic sky + cloud stack can decide instead of being hard-killed.
    private static let minimumMeanLuminance = 0.025
    private static let maximumDarkFraction = 0.92

    static func evaluate(sampleBuffer: CMSampleBuffer) -> SceneSanityResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return rejectedResult()
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return rejectedResult()
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)

        var luminanceSum = 0.0
        var saturationSum = 0.0
        var darkSamples = 0
        var brightSamples = 0
        var clippedSamples = 0
        var neutralHighlightSamples = 0
        var sampleCount = 0

        var y = stepY / 2
        while y < height {
            var x = stepX / 2
            while x < width {
                let offset = y * rowBytes + x * 4
                let blue = Double(bytes[offset]) / 255.0
                let green = Double(bytes[offset + 1]) / 255.0
                let red = Double(bytes[offset + 2]) / 255.0
                let luminance = red * 0.2126 + green * 0.7152 + blue * 0.0722
                let maximumChannel = max(red, green, blue)
                let minimumChannel = min(red, green, blue)
                let saturation = maximumChannel > 0
                    ? (maximumChannel - minimumChannel) / maximumChannel
                    : 0

                luminanceSum += luminance
                saturationSum += saturation
                if luminance < 0.08 { darkSamples += 1 }
                if luminance > 0.88 { brightSamples += 1 }
                if maximumChannel >= 0.985 { clippedSamples += 1 }
                if luminance > 0.82 && maximumChannel - minimumChannel < 0.10 {
                    neutralHighlightSamples += 1
                }
                sampleCount += 1
                x += stepX
            }
            y += stepY
        }

        guard sampleCount > 0 else { return rejectedResult() }

        let denominator = Double(sampleCount)
        let meanLuminance = luminanceSum / denominator
        let meanSaturation = saturationSum / denominator
        let darkFraction = Double(darkSamples) / denominator
        let brightFraction = Double(brightSamples) / denominator
        let clippedFraction = Double(clippedSamples) / denominator
        let neutralHighlightFraction = Double(neutralHighlightSamples) / denominator
        return SceneSanityResult(
            meanLuminance: meanLuminance,
            meanSaturation: meanSaturation,
            darkFraction: darkFraction,
            brightFraction: brightFraction,
            clippedFraction: clippedFraction,
            neutralHighlightFraction: neutralHighlightFraction,
            rejected: shouldReject(meanLuminance: meanLuminance, darkFraction: darkFraction)
        )
    }

    static func shouldReject(meanLuminance: Double, darkFraction: Double) -> Bool {
        meanLuminance < minimumMeanLuminance && darkFraction > maximumDarkFraction
    }

    private static func rejectedResult() -> SceneSanityResult {
        SceneSanityResult(
            meanLuminance: 0,
            meanSaturation: 0,
            darkFraction: 1,
            brightFraction: 0,
            clippedFraction: 0,
            neutralHighlightFraction: 0,
            rejected: true
        )
    }
}
