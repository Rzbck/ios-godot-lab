import AVFoundation
import CoreGraphics
import CoreImage
import CoreML
import Foundation
import ImageIO
import QuartzCore

struct CloudAnalysisEnvironment: Equatable {
    let lowLight: Bool
}

final class AdaptiveCloudAnalyzer {
    private struct SkySemanticMaps {
        let sky: [Double]
        let blocker: [Double]
        let tree: [Double]
        let building: [Double]
        let person: [Double]
        let plant: [Double]
        let wall: [Double]
    }

    private struct CachedSemanticFrame {
        let sky: [Double]
        let blocker: [Double]
        let classCoverage: CloudSemanticClassCoverage
        let sourceWidth: Int
        let sourceHeight: Int
        let targetWidth: Int
        let targetHeight: Int
        let completedAt: CFTimeInterval
        let refreshMilliseconds: Double
        let generation: Int
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let portraitWidth = 304
    private let portraitHeight = 544
    private let landscapeWidth = 544
    private let landscapeHeight = 304
    private let skyInputSize = 384
    private let portraitCloudModel: MLModel?
    private let landscapeCloudModel: MLModel?
    private let skyModel: MLModel?
    private let semanticGate = CloudSemanticGate()

    private let skyInferenceQueue = DispatchQueue(
        label: "cloudweight.inference.sky",
        qos: .userInitiated
    )
    private let cloudInferenceQueue = DispatchQueue(
        label: "cloudweight.inference.cloud",
        qos: .userInitiated
    )

    private let semanticCacheLock = NSLock()
    private var semanticCache: CachedSemanticFrame?
    private var semanticRefreshInFlight = false
    private var semanticEpoch = 0
    private var semanticGeneration = 0
    private var lastReportedSemanticGeneration = 0

    private var timingPreprocessingMilliseconds = 0.0
    private var timingSkyInferenceMilliseconds = 0.0
    private var timingCloudInferenceMilliseconds = 0.0
    private var timingInferenceWallMilliseconds = 0.0
    private var timingInferenceMode = "parallel"
    private var gateMetrics: CloudGateMetrics?

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
            loadError = "Modèle de validation sémantique du ciel absent du bundle"
            return
        }

        do {
            portraitCloudModel = try MLModel(
                contentsOf: portraitURL,
                configuration: configuration
            )
            landscapeCloudModel = try MLModel(
                contentsOf: landscapeURL,
                configuration: configuration
            )
            skyModel = try MLModel(
                contentsOf: skyURL,
                configuration: configuration
            )
            loadError = nil
        } catch {
            portraitCloudModel = nil
            landscapeCloudModel = nil
            skyModel = nil
            loadError = "Impossible de charger les modèles Core ML : \(error.localizedDescription)"
        }
    }

    func resetSemanticGate() {
        semanticGate.reset()

        semanticCacheLock.lock()
        semanticEpoch += 1
        semanticCache = nil
        semanticRefreshInFlight = false
        lastReportedSemanticGeneration = 0
        semanticCacheLock.unlock()
    }

    func analyze(
        sampleBuffer: CMSampleBuffer,
        fieldOfViewDegrees: Double,
        environment: CloudAnalysisEnvironment
    ) -> CloudFrameAnalysis? {
        let analysisStarted = CACurrentMediaTime()
        timingPreprocessingMilliseconds = 0
        timingSkyInferenceMilliseconds = 0
        timingCloudInferenceMilliseconds = 0
        timingInferenceWallMilliseconds = 0
        timingInferenceMode = "parallel"
        gateMetrics = nil
        lastTiming = nil

        defer {
            let totalMilliseconds = (CACurrentMediaTime() - analysisStarted) * 1_000
            let knownMilliseconds = timingPreprocessingMilliseconds + timingInferenceWallMilliseconds
            let metrics = gateMetrics
            lastTiming = CloudAnalyzerTiming(
                preprocessingMilliseconds: timingPreprocessingMilliseconds,
                skyInferenceMilliseconds: timingSkyInferenceMilliseconds,
                cloudInferenceMilliseconds: timingCloudInferenceMilliseconds,
                inferenceWallMilliseconds: timingInferenceWallMilliseconds,
                parallelOverlapMilliseconds: timingInferenceMode == "parallel"
                    ? max(
                        0,
                        timingSkyInferenceMilliseconds
                            + timingCloudInferenceMilliseconds
                            - timingInferenceWallMilliseconds
                    )
                    : 0,
                postprocessingMilliseconds: max(0, totalMilliseconds - knownMilliseconds),
                skyCoveragePercent: metrics.map {
                    $0.skySceneActive
                        ? max(5.0, max($0.strictSkyCoveragePercent, $0.relaxedSkyCoveragePercent))
                        : $0.strictSkyCoveragePercent
                } ?? 0,
                strictSkyCoveragePercent: metrics?.strictSkyCoveragePercent ?? 0,
                relaxedSkyCoveragePercent: metrics?.relaxedSkyCoveragePercent ?? 0,
                semanticBlockerCoveragePercent: metrics?.blockerCoveragePercent ?? 0,
                semanticTreeCoveragePercent: metrics?.treeCoveragePercent ?? 0,
                semanticBuildingCoveragePercent: metrics?.buildingCoveragePercent ?? 0,
                semanticPersonCoveragePercent: metrics?.personCoveragePercent ?? 0,
                semanticPlantCoveragePercent: metrics?.plantCoveragePercent ?? 0,
                semanticWallCoveragePercent: metrics?.wallCoveragePercent ?? 0,
                semanticFallbackCoveragePercent: metrics?.semanticFallbackCoveragePercent ?? 0,
                skySceneActive: metrics?.skySceneActive ?? false,
                skyGateMode: metrics?.mode ?? "unavailable",
                inferenceMode: timingInferenceMode
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
        ) else {
            return nil
        }

        let thermal = ProcessInfo.processInfo.thermalState
        scheduleSemanticRefreshIfNeeded(
            cameraBuffer: cameraBuffer,
            skyModel: skyModel,
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            thermal: thermal
        )

        let wallStarted = CACurrentMediaTime()
        let cloudResult = cloudInferenceQueue.sync { [self] in
            predictImageProbabilityMap(
                model: cloudModel,
                inputBuffer: cloudInputBuffer,
                outputName: "cloud_probability",
                width: targetWidth,
                height: targetHeight
            )
        }

        timingInferenceWallMilliseconds = (CACurrentMediaTime() - wallStarted) * 1_000
        timingCloudInferenceMilliseconds = cloudResult?.milliseconds ?? 0

        guard let cloudProbabilityMap = cloudResult?.values else {
            return nil
        }

        let semantic = semanticSnapshot(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetWidth: targetWidth,
            targetHeight: targetHeight
        )
        timingSkyInferenceMilliseconds = semantic.reportedRefreshMilliseconds

        guard let semanticFrame = semantic.frame else {
            timingInferenceMode = "cloud_waiting_semantic"
            return emptyAnalysis(fieldOfViewDegrees: fieldOfViewDegrees)
        }

        timingInferenceMode = semantic.didReportRefresh
            ? "cloud_cached_semantic_refresh"
            : "cloud_cached_semantic"

        let gated = semanticGate.makeMask(
            cloudProbabilities: cloudProbabilityMap,
            skyProbabilities: semanticFrame.sky,
            blockerProbabilities: semanticFrame.blocker,
            classCoverage: semanticFrame.classCoverage,
            lowLight: environment.lowLight
        )
        gateMetrics = gated.metrics

        let candidateMask = cleanup(
            mask: gated.mask,
            width: targetWidth,
            height: targetHeight
        )

        let extraction = CloudStructureAnalyzer.extract(
            candidateMask: candidateMask,
            seedMask: gated.seedMask,
            probabilities: cloudProbabilityMap,
            pixelBuffer: cloudInputBuffer,
            width: targetWidth,
            height: targetHeight
        )

        let minimumArea = max(120, Int(Double(targetWidth * targetHeight) * 0.0015))
        let accepted = extraction.regions
            .filter { $0.area >= minimumArea }
            .sorted { $0.area > $1.area }
            .prefix(10)

        guard !accepted.isEmpty else {
            return emptyAnalysis(fieldOfViewDegrees: fieldOfViewDegrees)
        }

        let acceptedArray = Array(accepted)
        let observations = acceptedArray.enumerated().map { index, region in
            observation(
                id: index,
                region: region,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
        }

        var kindsByLabel: [Int: CloudKind] = [:]
        for (index, region) in acceptedArray.enumerated() {
            kindsByLabel[region.label] = observations[index].kind
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

    private func observation(
        id: Int,
        region: CloudStructureRegion,
        targetWidth: Int,
        targetHeight: Int,
        fieldOfViewDegrees: Double
    ) -> CloudObservation {
        let normalizedWidth = Double(region.pixelWidth) / Double(targetWidth)
        let normalizedHeight = Double(region.pixelHeight) / Double(targetHeight)
        let bounds = CGRect(
            x: Double(region.minX) / Double(targetWidth),
            y: Double(region.minY) / Double(targetHeight),
            width: normalizedWidth,
            height: normalizedHeight
        )
        let kind = CloudStructureAnalyzer.classify(region)
        let kindConfidence = CloudStructureAnalyzer.classificationConfidence(
            region,
            kind: kind
        )
        let confidence = (
            0.20
            + region.meanProbability * 0.48
            + region.fillRatio * 0.10
            + region.highConfidenceFraction * 0.07
            + kindConfidence * 0.15
        ).clamped(0.05...0.97)

        return CloudObservation(
            id: id,
            kind: kind,
            confidence: confidence,
            coverage: region.frameCoverage,
            bounds: bounds,
            centroid: CGPoint(
                x: region.centroidX / Double(targetWidth),
                y: region.centroidY / Double(targetHeight)
            ),
            averageBrightness: region.meanBrightness,
            averageSaturation: region.meanSaturation,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    private func predictImageProbabilityMap(
        model: MLModel,
        inputBuffer: CVPixelBuffer,
        outputName: String,
        width: Int,
        height: Int
    ) -> (values: [Double], milliseconds: Double)? {
        let started = CACurrentMediaTime()
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

        guard let array = prediction.featureValue(for: outputName)?.multiArrayValue,
              let values = probabilityValues(from: array, width: width, height: height) else {
            return nil
        }
        return (values, (CACurrentMediaTime() - started) * 1_000)
    }

    private func predictSkySemanticMaps(
        model: MLModel,
        inputTensor: MLMultiArray,
        width: Int,
        height: Int
    ) -> (maps: SkySemanticMaps, milliseconds: Double)? {
        let started = CACurrentMediaTime()
        let provider: MLDictionaryFeatureProvider
        do {
            provider = try MLDictionaryFeatureProvider(dictionary: [
                "image_tensor": MLFeatureValue(multiArray: inputTensor)
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

        func values(_ name: String) -> [Double]? {
            guard let array = prediction.featureValue(for: name)?.multiArrayValue else { return nil }
            return probabilityValues(from: array, width: width, height: height)
        }

        guard let sky = values("sky_probability"),
              let blocker = values("blocker_probability"),
              let tree = values("tree_probability"),
              let building = values("building_probability"),
              let person = values("person_probability"),
              let plant = values("plant_probability"),
              let wall = values("wall_probability") else {
            return nil
        }

        return (
            SkySemanticMaps(
                sky: sky,
                blocker: blocker,
                tree: tree,
                building: building,
                person: person,
                plant: plant,
                wall: wall
            ),
            (CACurrentMediaTime() - started) * 1_000
        )
    }

    private func semanticSnapshot(
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int
    ) -> (
        frame: CachedSemanticFrame?,
        reportedRefreshMilliseconds: Double,
        didReportRefresh: Bool
    ) {
        semanticCacheLock.lock()
        defer { semanticCacheLock.unlock() }

        guard let frame = semanticCache,
              frame.sourceWidth == sourceWidth,
              frame.sourceHeight == sourceHeight,
              frame.targetWidth == targetWidth,
              frame.targetHeight == targetHeight else {
            return (nil, 0, false)
        }

        let didReportRefresh = frame.generation != lastReportedSemanticGeneration
        if didReportRefresh {
            lastReportedSemanticGeneration = frame.generation
        }

        return (
            frame,
            didReportRefresh ? frame.refreshMilliseconds : 0,
            didReportRefresh
        )
    }

    private func scheduleSemanticRefreshIfNeeded(
        cameraBuffer: CVPixelBuffer,
        skyModel: MLModel,
        sourceWidth: Int,
        sourceHeight: Int,
        targetWidth: Int,
        targetHeight: Int,
        thermal: ProcessInfo.ThermalState
    ) {
        let now = CACurrentMediaTime()
        let refreshInterval: CFTimeInterval
        if thermal == .nominal {
            refreshInterval = 0.25
        } else if thermal == .fair {
            refreshInterval = 0.35
        } else {
            refreshInterval = 0.65
        }

        semanticCacheLock.lock()
        let geometryMatches = semanticCache.map {
            $0.sourceWidth == sourceWidth
                && $0.sourceHeight == sourceHeight
                && $0.targetWidth == targetWidth
                && $0.targetHeight == targetHeight
        } ?? false
        let age = semanticCache.map { now - $0.completedAt } ?? .infinity
        let refreshNeeded = !geometryMatches || age >= refreshInterval

        guard refreshNeeded, !semanticRefreshInFlight else {
            semanticCacheLock.unlock()
            return
        }

        semanticRefreshInFlight = true
        let epoch = semanticEpoch
        semanticCacheLock.unlock()

        guard let skyInputBuffer = makeModelInput(
            from: cameraBuffer,
            width: skyInputSize,
            height: skyInputSize
        ),
        let skyInputTensor = makeRGBTensor(
            from: skyInputBuffer,
            width: skyInputSize,
            height: skyInputSize
        ) else {
            finishSemanticRefreshFailure(epoch: epoch)
            return
        }

        let refreshStarted = CACurrentMediaTime()

        skyInferenceQueue.async { [self] in
            guard let result = predictSkySemanticMaps(
                model: skyModel,
                inputTensor: skyInputTensor,
                width: skyInputSize,
                height: skyInputSize
            ) else {
                finishSemanticRefreshFailure(epoch: epoch)
                return
            }

            let expandedBlocker = Self.maxFilterProbabilityMap(
                result.maps.blocker,
                width: skyInputSize,
                height: skyInputSize,
                radius: 1
            )

            let rawSky = Self.resampleProbabilityMap(
                result.maps.sky,
                sourceWidth: skyInputSize,
                sourceHeight: skyInputSize,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )
            let rawBlocker = Self.resampleProbabilityMap(
                expandedBlocker,
                sourceWidth: skyInputSize,
                sourceHeight: skyInputSize,
                targetWidth: targetWidth,
                targetHeight: targetHeight
            )

            semanticCacheLock.lock()
            let previous = semanticCache
            semanticCacheLock.unlock()

            let sky: [Double]
            let blocker: [Double]
            if let previous,
               previous.sourceWidth == sourceWidth,
               previous.sourceHeight == sourceHeight,
               previous.targetWidth == targetWidth,
               previous.targetHeight == targetHeight {
                let delta = Self.sampledMeanAbsoluteDifference(
                    previous.sky,
                    rawSky,
                    stride: 8
                )
                let alpha: Double
                if delta < 0.025 {
                    alpha = 0.30
                } else if delta < 0.060 {
                    alpha = 0.48
                } else if delta < 0.120 {
                    alpha = 0.70
                } else {
                    alpha = 0.94
                }

                sky = Self.blendProbabilityMaps(
                    previous.sky,
                    rawSky,
                    alpha: alpha
                )
                blocker = Self.blendProbabilityMaps(
                    previous.blocker,
                    rawBlocker,
                    alpha: max(0.76, alpha)
                )
            } else {
                sky = rawSky
                blocker = rawBlocker
            }

            let classCoverage = CloudSemanticClassCoverage(
                treePercent: Self.coveragePercent(result.maps.tree, threshold: 0.48),
                buildingPercent: Self.coveragePercent(result.maps.building, threshold: 0.48),
                personPercent: Self.coveragePercent(result.maps.person, threshold: 0.48),
                plantPercent: Self.coveragePercent(result.maps.plant, threshold: 0.48),
                wallPercent: Self.coveragePercent(result.maps.wall, threshold: 0.48)
            )

            let refreshMilliseconds = (CACurrentMediaTime() - refreshStarted) * 1_000

            semanticCacheLock.lock()
            defer { semanticCacheLock.unlock() }

            guard epoch == semanticEpoch else { return }
            semanticGeneration += 1
            semanticCache = CachedSemanticFrame(
                sky: sky,
                blocker: blocker,
                classCoverage: classCoverage,
                sourceWidth: sourceWidth,
                sourceHeight: sourceHeight,
                targetWidth: targetWidth,
                targetHeight: targetHeight,
                completedAt: CACurrentMediaTime(),
                refreshMilliseconds: refreshMilliseconds,
                generation: semanticGeneration
            )
            semanticRefreshInFlight = false
        }
    }

    private func finishSemanticRefreshFailure(epoch: Int) {
        semanticCacheLock.lock()
        defer { semanticCacheLock.unlock() }
        if epoch == semanticEpoch {
            semanticRefreshInFlight = false
        }
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

    private static func coveragePercent(_ values: [Double], threshold: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let hits = values.reduce(0) { $0 + ($1 >= threshold ? 1 : 0) }
        return Double(hits) / Double(values.count) * 100
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

    static func maxFilterProbabilityMap(
        _ source: [Double],
        width: Int,
        height: Int,
        radius: Int
    ) -> [Double] {
        guard width > 0,
              height > 0,
              source.count == width * height else {
            return []
        }
        guard radius > 0 else { return source }

        var horizontal = [Double](repeating: 0, count: source.count)
        for y in 0..<height {
            for x in 0..<width {
                let firstX = max(0, x - radius)
                let lastX = min(width - 1, x + radius)
                var value = source[y * width + firstX]
                if firstX < lastX {
                    for nx in (firstX + 1)...lastX {
                        value = max(value, source[y * width + nx])
                    }
                }
                horizontal[y * width + x] = value
            }
        }

        var output = [Double](repeating: 0, count: source.count)
        for y in 0..<height {
            let firstY = max(0, y - radius)
            let lastY = min(height - 1, y + radius)
            for x in 0..<width {
                var value = horizontal[firstY * width + x]
                if firstY < lastY {
                    for ny in (firstY + 1)...lastY {
                        value = max(value, horizontal[ny * width + x])
                    }
                }
                output[y * width + x] = value
            }
        }
        return output
    }

    private static func sampledMeanAbsoluteDifference(
        _ lhs: [Double],
        _ rhs: [Double],
        stride: Int
    ) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        let step = max(1, stride)
        var total = 0.0
        var samples = 0
        var index = 0
        while index < lhs.count {
            total += abs(lhs[index] - rhs[index])
            samples += 1
            index += step
        }
        return total / Double(max(1, samples))
    }

    private static func blendProbabilityMaps(
        _ previous: [Double],
        _ current: [Double],
        alpha: Double
    ) -> [Double] {
        guard previous.count == current.count else { return current }
        let amount = alpha.clamped(0...1)
        let inverse = 1 - amount
        var result = current
        for index in result.indices {
            result[index] = previous[index] * inverse + current[index] * amount
        }
        return result
    }

    private func cleanup(mask: [Bool], width: Int, height: Int) -> [Bool] {
        var output = mask
        guard mask.count == width * height, width > 2, height > 2 else { return output }

        // Remove isolated noise but never fill background holes here. Filling
        // holes was joining adjacent cloud cells into one huge connected blob.
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                guard mask[index] else { continue }

                var count = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if mask[(y + dy) * width + (x + dx)] {
                            count += 1
                        }
                    }
                }
                output[index] = count >= 3
            }
        }
        return output
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
}
