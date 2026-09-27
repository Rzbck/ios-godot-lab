import AVFoundation
import Foundation

struct SceneSanityResult: Equatable {
    let meanLuminance: Double
    let darkFraction: Double
    let rejected: Bool
}

enum SceneSanityGate {
    private static let minimumMeanLuminance = 0.08
    private static let maximumDarkFraction = 0.72

    static func evaluate(sampleBuffer: CMSampleBuffer) -> SceneSanityResult {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return SceneSanityResult(meanLuminance: 0, darkFraction: 1, rejected: true)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return SceneSanityResult(meanLuminance: 0, darkFraction: 1, rejected: true)
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let stepX = max(1, width / 64)
        let stepY = max(1, height / 64)

        var luminanceSum = 0.0
        var darkSamples = 0
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

                luminanceSum += luminance
                if luminance < 0.08 {
                    darkSamples += 1
                }
                sampleCount += 1
                x += stepX
            }
            y += stepY
        }

        guard sampleCount > 0 else {
            return SceneSanityResult(meanLuminance: 0, darkFraction: 1, rejected: true)
        }

        let meanLuminance = luminanceSum / Double(sampleCount)
        let darkFraction = Double(darkSamples) / Double(sampleCount)
        return SceneSanityResult(
            meanLuminance: meanLuminance,
            darkFraction: darkFraction,
            rejected: shouldReject(meanLuminance: meanLuminance, darkFraction: darkFraction)
        )
    }

    static func shouldReject(meanLuminance: Double, darkFraction: Double) -> Bool {
        meanLuminance < minimumMeanLuminance && darkFraction > maximumDarkFraction
    }
}
