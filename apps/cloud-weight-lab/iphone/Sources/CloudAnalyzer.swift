import AVFoundation
import CoreImage
import CoreGraphics
import Foundation
import ImageIO

final class CloudAnalyzer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let targetWidth = 160
    private let targetHeight = 120

    func analyze(sampleBuffer: CMSampleBuffer, fieldOfViewDegrees: Double) -> CloudFrameAnalysis? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }

        // AVCapture camera buffers are landscape-native. Rotate a cheap analysis copy
        // to portrait so normalized coordinates map naturally to the portrait preview.
        let input = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let scaleX = CGFloat(targetWidth) / input.extent.width
        let scaleY = CGFloat(targetHeight) / input.extent.height
        let image = input.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        var pixels = [UInt8](repeating: 0, count: targetWidth * targetHeight * 4)
        context.render(
            image,
            toBitmap: &pixels,
            rowBytes: targetWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            format: .RGBA8,
            colorSpace: colorSpace
        )

        var cloudCount = 0
        var brightnessSum = 0.0
        var saturationSum = 0.0
        var minX = targetWidth
        var minY = targetHeight
        var maxX = -1
        var maxY = -1

        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let index = (y * targetWidth + x) * 4
                let red = Double(pixels[index]) / 255.0
                let green = Double(pixels[index + 1]) / 255.0
                let blue = Double(pixels[index + 2]) / 255.0

                let maximum = max(red, max(green, blue))
                let minimum = min(red, min(green, blue))
                let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
                let brightness = maximum
                let channelSpread = max(abs(red - green), max(abs(green - blue), abs(red - blue)))
                let blueDominance = blue - max(red, green)

                let brightNeutral = brightness > 0.62 && saturation < 0.38 && blueDominance < 0.16
                let greyCloud = brightness > 0.30 && channelSpread < 0.18 && blueDominance < 0.12
                let cloudLike = brightNeutral || greyCloud

                if cloudLike {
                    cloudCount += 1
                    brightnessSum += brightness
                    saturationSum += saturation
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        let total = targetWidth * targetHeight
        let coverage = Double(cloudCount) / Double(total)
        guard cloudCount > 0, coverage >= 0.012, maxX >= minX, maxY >= minY else {
            return nil
        }

        let width = Double(maxX - minX + 1) / Double(targetWidth)
        let height = Double(maxY - minY + 1) / Double(targetHeight)
        let x = Double(minX) / Double(targetWidth)
        let y = 1.0 - (Double(maxY + 1) / Double(targetHeight))
        let bounds = CGRect(x: x, y: y, width: width, height: height)

        let averageBrightness = brightnessSum / Double(cloudCount)
        let averageSaturation = saturationSum / Double(cloudCount)
        let area = max(width * height, 0.001)
        let density = min(1.0, coverage / area)
        let confidence = (
            0.24
            + min(0.24, coverage * 1.4)
            + density * 0.27
            + (1.0 - averageSaturation).clamped(0...1) * 0.20
        ).clamped(0.05...0.93)

        let kind = Self.classify(
            coverage: coverage,
            aspectRatio: width / max(height, 0.01),
            brightness: averageBrightness,
            saturation: averageSaturation
        )

        return CloudFrameAnalysis(
            timestamp: Date(),
            kind: kind,
            confidence: confidence,
            coverage: coverage,
            bounds: bounds,
            averageBrightness: averageBrightness,
            averageSaturation: averageSaturation,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    static func classify(
        coverage: Double,
        aspectRatio: Double,
        brightness: Double,
        saturation: Double
    ) -> CloudKind {
        if coverage > 0.72 {
            return .stratus
        }
        if coverage < 0.18 && aspectRatio > 1.8 && brightness > 0.68 && saturation < 0.24 {
            return .cirrus
        }
        if coverage < 0.48 && aspectRatio < 1.8 {
            return .cumulus
        }
        if coverage < 0.72 {
            return .stratocumulus
        }
        return .unknown
    }
}
