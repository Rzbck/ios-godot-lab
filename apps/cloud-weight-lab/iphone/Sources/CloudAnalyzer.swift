import AVFoundation
import CoreGraphics
import CoreImage
import CoreML
import Foundation
import ImageIO

final class CloudAnalyzer {
    private struct Component {
        let label: Int
        let pixels: [Int]
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        let centroidX: Double
        let centroidY: Double
        let meanProbability: Double

        var area: Int { pixels.count }
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let targetWidth = 304
    private let targetHeight = 544
    private let probabilityThreshold = 0.52
    private let model: MLModel?

    let loadError: String?

    var isReady: Bool { model != nil }

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        guard let url = Bundle.main.url(
            forResource: "CloudSegmentation",
            withExtension: "mlmodelc"
        ) else {
            model = nil
            loadError = "Modèle UCloudNet absent du bundle"
            return
        }

        do {
            model = try MLModel(contentsOf: url, configuration: configuration)
            loadError = nil
        } catch {
            model = nil
            loadError = "Impossible de charger UCloudNet : \(error.localizedDescription)"
        }
    }

    func analyze(
        sampleBuffer: CMSampleBuffer,
        fieldOfViewDegrees: Double
    ) -> CloudFrameAnalysis? {
        guard let model,
              let cameraBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let inputBuffer = makeModelInput(from: cameraBuffer) else {
            return nil
        }

        let provider: MLDictionaryFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [
                "image": MLFeatureValue(pixelBuffer: inputBuffer)
            ])
        } catch {
            return nil
        }

        let prediction: MLFeatureProvider
        do {
            prediction = try model.prediction(from: provider)
        } catch {
            return nil
        }

        guard let probabilities = prediction
            .featureValue(for: "cloud_probability")?
            .multiArrayValue,
              let probabilityMap = probabilityValues(from: probabilities) else {
            return nil
        }

        var mask = probabilityMap.map { $0 >= probabilityThreshold }
        mask = cleanup(mask: mask, width: targetWidth, height: targetHeight)

        let extraction = connectedComponents(
            mask: mask,
            probabilities: probabilityMap,
            width: targetWidth,
            height: targetHeight
        )

        let minimumArea = max(120, Int(Double(targetWidth * targetHeight) * 0.0015))
        let accepted = extraction.components
            .filter { $0.area >= minimumArea }
            .sorted { $0.area > $1.area }
            .prefix(8)

        guard !accepted.isEmpty else {
            return CloudFrameAnalysis(
                timestamp: Date(),
                observations: [],
                totalCoverage: 0,
                overlayImage: nil,
                engine: .ucloudNetCoreML,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
        }

        let acceptedArray = Array(accepted)
        let observations = acceptedArray.enumerated().map { index, component in
            observation(
                id: index,
                component: component,
                inputBuffer: inputBuffer,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
        }

        let acceptedLabels = Set(acceptedArray.map(\.label))
        let acceptedPixels = acceptedArray.reduce(0) { $0 + $1.area }
        let coverage = Double(acceptedPixels) / Double(targetWidth * targetHeight)

        return CloudFrameAnalysis(
            timestamp: Date(),
            observations: observations,
            totalCoverage: coverage,
            overlayImage: makeOverlayImage(
                labels: extraction.labels,
                acceptedLabels: acceptedLabels,
                width: targetWidth,
                height: targetHeight
            ),
            engine: .ucloudNetCoreML,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    private func makeModelInput(from pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            targetWidth,
            targetHeight,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        let input = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        let sx = CGFloat(targetWidth) / input.extent.width
        let sy = CGFloat(targetHeight) / input.extent.height
        let scaled = input.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        context.render(
            scaled,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return destination
    }

    private func probabilityValues(from array: MLMultiArray) -> [Double]? {
        let shape = array.shape.map { Int(truncating: $0) }
        let strides = array.strides.map { Int(truncating: $0) }

        guard shape.count == 4,
              shape[0] == 1,
              shape[1] == 1,
              shape[2] == targetHeight,
              shape[3] == targetWidth else {
            return nil
        }

        var values = [Double](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            for x in 0..<targetWidth {
                let sourceIndex = y * strides[2] + x * strides[3]
                values[y * targetWidth + x] = scalarValue(
                    array: array,
                    index: sourceIndex
                )
            }
        }
        return values
    }

    private func scalarValue(array: MLMultiArray, index: Int) -> Double {
        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            return Double(pointer[index])
        case .float32:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            return Double(pointer[index])
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            return pointer[index]
        case .int32:
            let pointer = array.dataPointer.bindMemory(to: Int32.self, capacity: array.count)
            return Double(pointer[index])
        @unknown default:
            return 0
        }
    }

    private func cleanup(mask: [Bool], width: Int, height: Int) -> [Bool] {
        var output = mask
        guard width > 2, height > 2 else { return output }

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                var count = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if mask[(y + dy) * width + (x + dx)] {
                            count += 1
                        }
                    }
                }

                let index = y * width + x
                if mask[index] {
                    output[index] = count >= 3
                } else if count >= 7 {
                    output[index] = true
                }
            }
        }
        return output
    }

    private func connectedComponents(
        mask: [Bool],
        probabilities: [Double],
        width: Int,
        height: Int
    ) -> (components: [Component], labels: [Int]) {
        var labels = [Int](repeating: -1, count: width * height)
        var components: [Component] = []
        var queue = [Int]()
        queue.reserveCapacity(width * height / 4)

        let neighborOffsets = [
            (-1, -1), (0, -1), (1, -1),
            (-1, 0),            (1, 0),
            (-1, 1),  (0, 1),  (1, 1)
        ]

        for start in 0..<mask.count where mask[start] && labels[start] == -1 {
            let label = components.count
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            labels[start] = label

            var cursor = 0
            var pixels: [Int] = []
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var sumX = 0.0
            var sumY = 0.0
            var probabilitySum = 0.0

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                pixels.append(index)

                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                sumX += Double(x)
                sumY += Double(y)
                probabilitySum += probabilities[index]

                for (dx, dy) in neighborOffsets {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    guard mask[next], labels[next] == -1 else { continue }
                    labels[next] = label
                    queue.append(next)
                }
            }

            let count = max(1, pixels.count)
            components.append(
                Component(
                    label: label,
                    pixels: pixels,
                    minX: minX,
                    minY: minY,
                    maxX: maxX,
                    maxY: maxY,
                    centroidX: sumX / Double(count),
                    centroidY: sumY / Double(count),
                    meanProbability: probabilitySum / Double(count)
                )
            )
        }

        return (components, labels)
    }

    private func observation(
        id: Int,
        component: Component,
        inputBuffer: CVPixelBuffer,
        fieldOfViewDegrees: Double
    ) -> CloudObservation {
        let width = Double(component.maxX - component.minX + 1) / Double(targetWidth)
        let height = Double(component.maxY - component.minY + 1) / Double(targetHeight)
        let bounds = CGRect(
            x: Double(component.minX) / Double(targetWidth),
            y: Double(component.minY) / Double(targetHeight),
            width: width,
            height: height
        )
        let coverage = Double(component.area) / Double(targetWidth * targetHeight)
        let color = colorStatistics(
            pixels: component.pixels,
            pixelBuffer: inputBuffer
        )
        let fill = (
            coverage / max(width * height, 0.0001)
        ).clamped(0...1)
        let confidence = (
            0.30
            + component.meanProbability * 0.52
            + fill * 0.14
        ).clamped(0.05...0.97)

        return CloudObservation(
            id: id,
            kind: Self.classify(
                coverage: coverage,
                aspectRatio: width / max(height, 0.01),
                brightness: color.brightness,
                saturation: color.saturation
            ),
            confidence: confidence,
            coverage: coverage,
            bounds: bounds,
            centroid: CGPoint(
                x: component.centroidX / Double(targetWidth),
                y: component.centroidY / Double(targetHeight)
            ),
            averageBrightness: color.brightness,
            averageSaturation: color.saturation,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    private func colorStatistics(
        pixels: [Int],
        pixelBuffer: CVPixelBuffer
    ) -> (brightness: Double, saturation: Double) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return (0.65, 0.18)
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var brightnessSum = 0.0
        var saturationSum = 0.0

        for index in pixels {
            let x = index % targetWidth
            let y = index / targetWidth
            let offset = y * rowBytes + x * 4

            let blue = Double(bytes[offset]) / 255.0
            let green = Double(bytes[offset + 1]) / 255.0
            let red = Double(bytes[offset + 2]) / 255.0
            let maximum = max(red, max(green, blue))
            let minimum = min(red, min(green, blue))
            let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

            brightnessSum += maximum
            saturationSum += saturation
        }

        let count = Double(max(1, pixels.count))
        return (brightnessSum / count, saturationSum / count)
    }

    private func makeOverlayImage(
        labels: [Int],
        acceptedLabels: Set<Int>,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard !acceptedLabels.isEmpty else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        func isAccepted(_ x: Int, _ y: Int, label: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return labels[y * width + x] == label
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let label = labels[pixel]
                guard acceptedLabels.contains(label) else { continue }

                let boundary =
                    !isAccepted(x - 1, y, label: label)
                    || !isAccepted(x + 1, y, label: label)
                    || !isAccepted(x, y - 1, label: label)
                    || !isAccepted(x, y + 1, label: label)

                let offset = pixel * 4
                rgba[offset] = 110
                rgba[offset + 1] = 225
                rgba[offset + 2] = 255
                rgba[offset + 3] = boundary ? 235 : 44
            }
        }

        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
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
        if coverage < 0.12
            && aspectRatio > 2.0
            && brightness > 0.66
            && saturation < 0.25 {
            return .cirrus
        }
        if coverage < 0.30 && aspectRatio < 1.9 {
            return .cumulus
        }
        if coverage < 0.72 {
            return .stratocumulus
        }
        return .unknown
    }
}
