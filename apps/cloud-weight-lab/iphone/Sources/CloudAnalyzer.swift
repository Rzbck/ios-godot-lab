import AVFoundation
import CoreGraphics
import CoreImage
import CoreML
import Foundation
import ImageIO
import QuartzCore

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
    private let portraitWidth = 304
    private let portraitHeight = 544
    private let landscapeWidth = 544
    private let landscapeHeight = 304
    private let skyInputSize = 384
    private let probabilityThreshold = 0.52
    private let skyProbabilityThreshold = 0.55
    private let minimumSkyCoverage = 0.05
    private let portraitCloudModel: MLModel?
    private let landscapeCloudModel: MLModel?
    private let skyModel: MLModel?

    private var timingPreprocessingMilliseconds = 0.0
    private var timingSkyInferenceMilliseconds = 0.0
    private var timingCloudInferenceMilliseconds = 0.0
    private var timingSkyCoveragePercent = 0.0

    let loadError: String?
    private(set) var lastTiming: CloudAnalyzerTiming?

    var isReady: Bool {
        portraitCloudModel != nil && landscapeCloudModel != nil && skyModel != nil
    }

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all

        guard let portraitURL = Bundle.main.url(
            forResource: "CloudSegmentation",
            withExtension: "mlmodelc"
        ) else {
            portraitCloudModel = nil
            landscapeCloudModel = nil
            skyModel = nil
            loadError = "Modèle UCloudNet portrait absent du bundle"
            return
        }

        guard let landscapeURL = Bundle.main.url(
            forResource: "CloudSegmentationLandscape",
            withExtension: "mlmodelc"
        ) else {
            portraitCloudModel = nil
            landscapeCloudModel = nil
            skyModel = nil
            loadError = "Modèle UCloudNet paysage absent du bundle"
            return
        }

        guard let skyURL = Bundle.main.url(
            forResource: "SkySegmentation",
            withExtension: "mlmodelc"
        ) else {
            portraitCloudModel = nil
            landscapeCloudModel = nil
            skyModel = nil
            loadError = "Modèle de validation du ciel absent du bundle"
            return
        }

        do {
            let loadedPortraitCloudModel = try MLModel(
                contentsOf: portraitURL,
                configuration: configuration
            )
            let loadedLandscapeCloudModel = try MLModel(
                contentsOf: landscapeURL,
                configuration: configuration
            )
            let loadedSkyModel = try MLModel(
                contentsOf: skyURL,
                configuration: configuration
            )
            portraitCloudModel = loadedPortraitCloudModel
            landscapeCloudModel = loadedLandscapeCloudModel
            skyModel = loadedSkyModel
            loadError = nil
        } catch {
            portraitCloudModel = nil
            landscapeCloudModel = nil
            skyModel = nil
            loadError = "Impossible de charger les modèles Core ML : \(error.localizedDescription)"
        }
    }

    func analyze(
        sampleBuffer: CMSampleBuffer,
        fieldOfViewDegrees: Double
    ) -> CloudFrameAnalysis? {
        let analysisStarted = CACurrentMediaTime()
        timingPreprocessingMilliseconds = 0
        timingSkyInferenceMilliseconds = 0
        timingCloudInferenceMilliseconds = 0
        timingSkyCoveragePercent = 0
        lastTiming = nil

        defer {
            let totalMilliseconds = (CACurrentMediaTime() - analysisStarted) * 1_000
            let knownMilliseconds = timingPreprocessingMilliseconds
                + timingSkyInferenceMilliseconds
                + timingCloudInferenceMilliseconds
            lastTiming = CloudAnalyzerTiming(
                preprocessingMilliseconds: timingPreprocessingMilliseconds,
                skyInferenceMilliseconds: timingSkyInferenceMilliseconds,
                cloudInferenceMilliseconds: timingCloudInferenceMilliseconds,
                postprocessingMilliseconds: max(0, totalMilliseconds - knownMilliseconds),
                skyCoveragePercent: timingSkyCoveragePercent
            )
        }

        guard let portraitCloudModel,
              let landscapeCloudModel,
              let skyModel,
              let cameraBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let sourceWidth = CVPixelBufferGetWidth(cameraBuffer)
        let sourceHeight = CVPixelBufferGetHeight(cameraBuffer)
        let isLandscape = sourceWidth > sourceHeight
        let targetWidth = isLandscape ? landscapeWidth : portraitWidth
        let targetHeight = isLandscape ? landscapeHeight : portraitHeight
        let cloudModel = isLandscape ? landscapeCloudModel : portraitCloudModel

        guard let cloudInputBuffer = makeModelInput(
                from: cameraBuffer,
                width: targetWidth,
                height: targetHeight
              ),
              let skyInputBuffer = makeModelInput(
                from: cameraBuffer,
                width: skyInputSize,
                height: skyInputSize
              ),
              let skyInputTensor = makeRGBTensor(
                from: skyInputBuffer,
                width: skyInputSize,
                height: skyInputSize
              ),
              let skyProbabilitySquare = predictTensorProbabilityMap(
                model: skyModel,
                inputTensor: skyInputTensor,
                inputName: "image_tensor",
                outputName: "sky_probability",
                width: skyInputSize,
                height: skyInputSize
              ) else {
            return nil
        }

        let skyProbabilityMap = Self.resampleProbabilityMap(
            skyProbabilitySquare,
            sourceWidth: skyInputSize,
            sourceHeight: skyInputSize,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        let skyCoverage = Double(
            skyProbabilityMap.reduce(0) { partial, value in
                partial + (value >= skyProbabilityThreshold ? 1 : 0)
            }
        ) / Double(targetWidth * targetHeight)
        timingSkyCoveragePercent = skyCoverage * 100

        guard skyCoverage >= minimumSkyCoverage else {
            return emptyAnalysis(fieldOfViewDegrees: fieldOfViewDegrees)
        }

        guard let cloudProbabilityMap = predictImageProbabilityMap(
            model: cloudModel,
            inputBuffer: cloudInputBuffer,
            outputName: "cloud_probability",
            width: targetWidth,
            height: targetHeight
        ) else {
            return nil
        }

        var mask = Self.gatedCloudMask(
            cloudProbabilities: cloudProbabilityMap,
            skyProbabilities: skyProbabilityMap,
            cloudThreshold: probabilityThreshold,
            skyThreshold: skyProbabilityThreshold
        )
        mask = cleanup(mask: mask, width: targetWidth, height: targetHeight)

        let extraction = connectedComponents(
            mask: mask,
            probabilities: cloudProbabilityMap,
            width: targetWidth,
            height: targetHeight
        )

        let minimumArea = max(120, Int(Double(targetWidth * targetHeight) * 0.0015))
        let accepted = extraction.components
            .filter { $0.area >= minimumArea }
            .sorted { $0.area > $1.area }
            .prefix(8)

        guard !accepted.isEmpty else {
            return emptyAnalysis(fieldOfViewDegrees: fieldOfViewDegrees)
        }

        let acceptedArray = Array(accepted)
        let observations = acceptedArray.enumerated().map { index, component in
            observation(
                id: index,
                component: component,
                inputBuffer: cloudInputBuffer,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
        }

        var kindsByLabel: [Int: CloudKind] = [:]
        for (index, component) in acceptedArray.enumerated() {
            kindsByLabel[component.label] = observations[index].kind
        }

        let acceptedPixels = acceptedArray.reduce(0) { $0 + $1.area }
        let coverage = Double(acceptedPixels) / Double(targetWidth * targetHeight)

        return CloudFrameAnalysis(
            timestamp: Date(),
            observations: observations,
            totalCoverage: coverage,
            overlayImage: makeOverlayImage(
                labels: extraction.labels,
                kindsByLabel: kindsByLabel,
                width: targetWidth,
                height: targetHeight
            ),
            engine: .ucloudNetCoreML,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    private func emptyAnalysis(fieldOfViewDegrees: Double) -> CloudFrameAnalysis {
        CloudFrameAnalysis(
            timestamp: Date(),
            observations: [],
            totalCoverage: 0,
            overlayImage: nil,
            engine: .ucloudNetCoreML,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    private func predictImageProbabilityMap(
        model: MLModel,
        inputBuffer: CVPixelBuffer,
        outputName: String,
        width: Int,
        height: Int
    ) -> [Double]? {
        let started = CACurrentMediaTime()
        defer {
            timingCloudInferenceMilliseconds += (CACurrentMediaTime() - started) * 1_000
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

        guard let array = prediction.featureValue(for: outputName)?.multiArrayValue else {
            return nil
        }
        return probabilityValues(from: array, width: width, height: height)
    }

    private func predictTensorProbabilityMap(
        model: MLModel,
        inputTensor: MLMultiArray,
        inputName: String,
        outputName: String,
        width: Int,
        height: Int
    ) -> [Double]? {
        let started = CACurrentMediaTime()
        defer {
            timingSkyInferenceMilliseconds += (CACurrentMediaTime() - started) * 1_000
        }

        let provider: MLDictionaryFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [
                inputName: MLFeatureValue(multiArray: inputTensor)
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

        guard let array = prediction.featureValue(for: outputName)?.multiArrayValue else {
            return nil
        }
        return probabilityValues(from: array, width: width, height: height)
    }

    private func makeModelInput(
        from pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> CVPixelBuffer? {
        let started = CACurrentMediaTime()
        defer {
            timingPreprocessingMilliseconds += (CACurrentMediaTime() - started) * 1_000
        }

        var destination: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let sx = CGFloat(width) / input.extent.width
        let sy = CGFloat(height) / input.extent.height
        let scaled = input.transformed(by: CGAffineTransform(scaleX: sx, y: sy))

        context.render(
            scaled,
            to: destination,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return destination
    }

    private func makeRGBTensor(
        from pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> MLMultiArray? {
        let started = CACurrentMediaTime()
        defer {
            timingPreprocessingMilliseconds += (CACurrentMediaTime() - started) * 1_000
        }

        guard CVPixelBufferGetWidth(pixelBuffer) == width,
              CVPixelBufferGetHeight(pixelBuffer) == height,
              let array = try? MLMultiArray(
                shape: [1, 3, NSNumber(value: height), NSNumber(value: width)],
                dataType: .float32
              ) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let tensor = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
        let plane = width * height

        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let offset = y * rowBytes + x * 4
                tensor[pixel] = Float(bytes[offset + 2]) / 255.0
                tensor[plane + pixel] = Float(bytes[offset + 1]) / 255.0
                tensor[2 * plane + pixel] = Float(bytes[offset]) / 255.0
            }
        }
        return array
    }

    private func probabilityValues(
        from array: MLMultiArray,
        width: Int,
        height: Int
    ) -> [Double]? {
        let shape = array.shape.map { Int(truncating: $0) }
        let strides = array.strides.map { Int(truncating: $0) }

        guard shape.count == 4,
              shape[0] == 1,
              shape[1] == 1,
              shape[2] == height,
              shape[3] == width else {
            return nil
        }

        var values = [Double](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let sourceIndex = y * strides[2] + x * strides[3]
                values[y * width + x] = scalarValue(array: array, index: sourceIndex)
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
        case .int8:
            let pointer = array.dataPointer.bindMemory(to: Int8.self, capacity: array.count)
            return Double(pointer[index])
        @unknown default:
            return 0
        }
    }

    static func gatedCloudMask(
        cloudProbabilities: [Double],
        skyProbabilities: [Double],
        cloudThreshold: Double,
        skyThreshold: Double
    ) -> [Bool] {
        guard cloudProbabilities.count == skyProbabilities.count else { return [] }
        return zip(cloudProbabilities, skyProbabilities).map { cloud, sky in
            cloud >= cloudThreshold && sky >= skyThreshold
        }
    }

    static func resampleProbabilityMap(
        _ source: [Double],
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> [Double] {
        guard sourceWidth > 0,
              sourceHeight > 0,
              targetWidth > 0,
              targetHeight > 0,
              source.count == sourceWidth * sourceHeight else {
            return []
        }

        var output = [Double](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let sourceY = min(
                sourceHeight - 1,
                Int((Double(y) + 0.5) * Double(sourceHeight) / Double(targetHeight))
            )
            for x in 0..<targetWidth {
                let sourceX = min(
                    sourceWidth - 1,
                    Int((Double(x) + 0.5) * Double(sourceWidth) / Double(targetWidth))
                )
                output[y * targetWidth + x] = source[sourceY * sourceWidth + sourceX]
            }
        }
        return output
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
        targetWidth: Int,
        targetHeight: Int,
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
            pixelBuffer: inputBuffer,
            width: targetWidth
        )
        let fill = (coverage / max(width * height, 0.0001)).clamped(0...1)
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
        pixelBuffer: CVPixelBuffer,
        width: Int
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
            let x = index % width
            let y = index / width
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
        kindsByLabel: [Int: CloudKind],
        width: Int,
        height: Int
    ) -> CGImage? {
        guard !kindsByLabel.isEmpty else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        func matches(_ x: Int, _ y: Int, label: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return labels[y * width + x] == label
        }

        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let label = labels[pixel]
                guard let kind = kindsByLabel[label] else { continue }

                let boundary =
                    !matches(x - 1, y, label: label)
                    || !matches(x + 1, y, label: label)
                    || !matches(x, y - 1, label: label)
                    || !matches(x, y + 1, label: label)

                let color = overlayColor(kind)
                let offset = pixel * 4
                rgba[offset] = color.r
                rgba[offset + 1] = color.g
                rgba[offset + 2] = color.b
                rgba[offset + 3] = boundary ? 238 : 28
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

    private func overlayColor(_ kind: CloudKind) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch kind {
        case .cumulus: return (68, 210, 255)
        case .stratocumulus: return (255, 177, 72)
        case .stratus: return (190, 132, 255)
        case .cirrus: return (86, 242, 184)
        case .unknown: return (245, 245, 245)
        }
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
