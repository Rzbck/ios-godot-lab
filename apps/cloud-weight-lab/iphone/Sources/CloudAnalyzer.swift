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

final class CloudAnalyzer {
    private struct Component {
        let label: Int
        let area: Int
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
        let centroidX: Double
        let centroidY: Double
        let meanProbability: Double
        let probabilityStdDev: Double
    }

    private struct Seed {
        let pixels: [Int]
        let centroidX: Double
        let centroidY: Double
    }

    private struct ColorFeatures {
        let brightness: Double
        let saturation: Double
        let brightnessStdDev: Double
    }

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

    // SegFormer remains asynchronous. Small semantic-cache changes are now
    // damped on the semantic queue; large changes are applied immediately so
    // camera motion does not smear old blockers over the new frame.
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

        guard let cloudProbabilityMap = cloudResult?.values else { return nil }

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

        var mask = cleanup(mask: gated.mask, width: targetWidth, height: targetHeight)
        if mask.isEmpty {
            mask = [Bool](repeating: false, count: targetWidth * targetHeight)
        }

        let baseExtraction = connectedComponents(
            mask: mask,
            probabilities: cloudProbabilityMap,
            width: targetWidth,
            height: targetHeight
        )

        let maximumSplitRegions: Int
        switch thermal {
        case .nominal: maximumSplitRegions = 6
        case .fair: maximumSplitRegions = 4
        default: maximumSplitRegions = 2
        }

        let extraction = refineDenseComponents(
            baseExtraction,
            probabilities: cloudProbabilityMap,
            width: targetWidth,
            height: targetHeight,
            maximumSplitRegions: maximumSplitRegions
        )

        let minimumArea = max(120, Int(Double(targetWidth * targetHeight) * 0.0015))
        let acceptedArray = Array(
            extraction.components
                .filter { $0.area >= minimumArea }
                .sorted { $0.area > $1.area }
                .prefix(8)
        )

        guard !acceptedArray.isEmpty else {
            return emptyAnalysis(fieldOfViewDegrees: fieldOfViewDegrees)
        }

        let colorFeatures = colorStatistics(
            components: acceptedArray,
            labels: extraction.labels,
            pixelBuffer: cloudInputBuffer,
            width: targetWidth,
            height: targetHeight
        )

        let observations = acceptedArray.enumerated().map { index, component in
            observation(
                id: index,
                component: component,
                color: colorFeatures[component.label] ?? ColorFeatures(
                    brightness: 0.65,
                    saturation: 0.18,
                    brightnessStdDev: 0.05
                ),
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
        let previousFrame = geometryMatches ? semanticCache : nil
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

            let stabilizedMaps = Self.stabilizedSemanticTransition(
                previous: previousFrame,
                newSky: rawSky,
                newBlocker: rawBlocker
            )

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
                sky: stabilizedMaps.sky,
                blocker: stabilizedMaps.blocker,
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

    private static func stabilizedSemanticTransition(
        previous: CachedSemanticFrame?,
        newSky: [Double],
        newBlocker: [Double]
    ) -> (sky: [Double], blocker: [Double]) {
        guard let previous,
              previous.sky.count == newSky.count,
              previous.blocker.count == newBlocker.count,
              !newSky.isEmpty else {
            return (newSky, newBlocker)
        }

        let skyDelta = sampledMeanAbsoluteDifference(previous.sky, newSky)
        let blockerDelta = sampledMeanAbsoluteDifference(previous.blocker, newBlocker)
        let topologyDelta = (skyDelta + blockerDelta) * 0.5

        // Large changes usually mean camera/scene motion: apply immediately.
        guard topologyDelta < 0.11 else {
            return (newSky, newBlocker)
        }

        let alpha = topologyDelta < 0.045 ? 0.58 : 0.78
        var sky = [Double](repeating: 0, count: newSky.count)
        var blocker = [Double](repeating: 0, count: newBlocker.count)

        for index in newSky.indices {
            sky[index] = previous.sky[index] + (newSky[index] - previous.sky[index]) * alpha
            let blended = previous.blocker[index]
                + (newBlocker[index] - previous.blocker[index]) * alpha
            // New blockers appear almost immediately; disappearing blockers
            // decay over a refresh instead of creating a topology flash.
            blocker[index] = max(blended, newBlocker[index] * 0.92)
        }
        return (sky, blocker)
    }

    private static func sampledMeanAbsoluteDifference(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return 1 }
        let sampleStride = max(1, lhs.count / 4_096)
        var index = 0
        var sum = 0.0
        var count = 0
        while index < lhs.count {
            sum += abs(lhs[index] - rhs[index])
            count += 1
            index += sampleStride
        }
        return sum / Double(max(1, count))
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

    private func cleanup(mask: [Bool], width: Int, height: Int) -> [Bool] {
        var output = mask
        guard mask.count == width * height, width > 2, height > 2 else { return output }

        // Cardinal-only cleanup avoids the diagonal bridges that made dense
        // cloud fields collapse into one huge 8-connected component.
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let index = y * width + x
                let cardinalCount = (mask[index - 1] ? 1 : 0)
                    + (mask[index + 1] ? 1 : 0)
                    + (mask[index - width] ? 1 : 0)
                    + (mask[index + width] ? 1 : 0)

                if mask[index] {
                    output[index] = cardinalCount >= 1
                } else {
                    // Fill only a true one-pixel hole, never a diagonal gap.
                    output[index] = cardinalCount == 4
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
        var queue: [Int] = []
        queue.reserveCapacity(width * height / 4)
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]

        for start in 0..<mask.count where mask[start] && labels[start] == -1 {
            let label = components.count
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            labels[start] = label

            var cursor = 0
            var area = 0
            var minX = width
            var minY = height
            var maxX = 0
            var maxY = 0
            var sumX = 0.0
            var sumY = 0.0
            var probabilitySum = 0.0
            var probabilitySquareSum = 0.0

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                area += 1

                let x = index % width
                let y = index / width
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                sumX += Double(x)
                sumY += Double(y)

                let probability = probabilities[index]
                probabilitySum += probability
                probabilitySquareSum += probability * probability

                for (dx, dy) in offsets {
                    let nx = x + dx
                    let ny = y + dy
                    guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                    let next = ny * width + nx
                    guard mask[next], labels[next] == -1 else { continue }
                    labels[next] = label
                    queue.append(next)
                }
            }

            let count = Double(max(1, area))
            let mean = probabilitySum / count
            let variance = max(0, probabilitySquareSum / count - mean * mean)
            components.append(
                Component(
                    label: label,
                    area: area,
                    minX: minX,
                    minY: minY,
                    maxX: maxX,
                    maxY: maxY,
                    centroidX: sumX / count,
                    centroidY: sumY / count,
                    meanProbability: mean,
                    probabilityStdDev: sqrt(variance)
                )
            )
        }

        return (components, labels)
    }

    static func shouldSplitDenseComponent(
        coverage: Double,
        probabilityStdDev: Double
    ) -> Bool {
        coverage >= 0.20 && probabilityStdDev >= 0.055
    }

    private func refineDenseComponents(
        _ extraction: (components: [Component], labels: [Int]),
        probabilities: [Double],
        width: Int,
        height: Int,
        maximumSplitRegions: Int
    ) -> (components: [Component], labels: [Int]) {
        guard maximumSplitRegions >= 2 else { return extraction }

        let totalPixels = width * height
        let candidates = extraction.components.filter {
            Self.shouldSplitDenseComponent(
                coverage: Double($0.area) / Double(totalPixels),
                probabilityStdDev: $0.probabilityStdDev
            )
        }
        guard !candidates.isEmpty else { return extraction }

        var labels = extraction.labels
        var nextLabel = (extraction.components.map(\.label).max() ?? -1) + 1
        var didSplit = false

        for component in candidates.sorted(by: { $0.area > $1.area }) {
            let seeds = coreSeeds(
                parent: component,
                labels: labels,
                probabilities: probabilities,
                width: width,
                height: height,
                maximumSeeds: maximumSplitRegions
            )
            guard seeds.count >= 2 else { continue }

            split(
                parent: component,
                seeds: seeds,
                labels: &labels,
                width: width,
                height: height,
                nextLabel: &nextLabel
            )
            didSplit = true
        }

        guard didSplit else { return extraction }
        return componentsFromLabels(
            labels,
            probabilities: probabilities,
            width: width,
            height: height
        )
    }

    private func coreSeeds(
        parent: Component,
        labels: [Int],
        probabilities: [Double],
        width: Int,
        height: Int,
        maximumSeeds: Int
    ) -> [Seed] {
        let threshold = min(
            0.90,
            max(
                0.58,
                parent.meanProbability + max(0.035, parent.probabilityStdDev * 0.40)
            )
        )
        let minimumSeedArea = max(72, Int(Double(width * height) * 0.0012))
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        var visited = [Bool](repeating: false, count: labels.count)
        var queue: [Int] = []
        var seeds: [Seed] = []

        for y in parent.minY...parent.maxY {
            for x in parent.minX...parent.maxX {
                let start = y * width + x
                guard labels[start] == parent.label,
                      !visited[start],
                      probabilities[start] >= threshold else {
                    continue
                }

                queue.removeAll(keepingCapacity: true)
                queue.append(start)
                visited[start] = true
                var cursor = 0
                var pixels: [Int] = []
                var sumX = 0.0
                var sumY = 0.0

                while cursor < queue.count {
                    let index = queue[cursor]
                    cursor += 1
                    pixels.append(index)
                    let px = index % width
                    let py = index / width
                    sumX += Double(px)
                    sumY += Double(py)

                    for (dx, dy) in offsets {
                        let nx = px + dx
                        let ny = py + dy
                        guard nx >= parent.minX,
                              nx <= parent.maxX,
                              ny >= parent.minY,
                              ny <= parent.maxY else {
                            continue
                        }
                        let next = ny * width + nx
                        guard !visited[next],
                              labels[next] == parent.label,
                              probabilities[next] >= threshold else {
                            continue
                        }
                        visited[next] = true
                        queue.append(next)
                    }
                }

                guard pixels.count >= minimumSeedArea else { continue }
                let count = Double(pixels.count)
                seeds.append(
                    Seed(
                        pixels: pixels,
                        centroidX: sumX / count,
                        centroidY: sumY / count
                    )
                )
            }
        }

        var selected: [Seed] = []
        for seed in seeds.sorted(by: { $0.pixels.count > $1.pixels.count }) {
            let separated = selected.allSatisfy { existing in
                let dx = (seed.centroidX - existing.centroidX) / Double(width)
                let dy = (seed.centroidY - existing.centroidY) / Double(height)
                return sqrt(dx * dx + dy * dy) >= 0.065
            }
            if separated {
                selected.append(seed)
                if selected.count >= maximumSeeds { break }
            }
        }
        return selected
    }

    private func split(
        parent: Component,
        seeds: [Seed],
        labels: inout [Int],
        width: Int,
        height: Int,
        nextLabel: inout Int
    ) {
        var owner = [Int](repeating: -1, count: labels.count)
        var queue: [Int] = []
        queue.reserveCapacity(parent.area)
        var childLabels: [Int] = []

        for (seedIndex, seed) in seeds.enumerated() {
            childLabels.append(nextLabel)
            nextLabel += 1
            for pixel in seed.pixels {
                owner[pixel] = seedIndex
                queue.append(pixel)
            }
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            let seedOwner = owner[index]

            if x > 0 {
                let next = index - 1
                if labels[next] == parent.label && owner[next] == -1 {
                    owner[next] = seedOwner
                    queue.append(next)
                }
            }
            if x + 1 < width {
                let next = index + 1
                if labels[next] == parent.label && owner[next] == -1 {
                    owner[next] = seedOwner
                    queue.append(next)
                }
            }
            if y > 0 {
                let next = index - width
                if labels[next] == parent.label && owner[next] == -1 {
                    owner[next] = seedOwner
                    queue.append(next)
                }
            }
            if y + 1 < height {
                let next = index + width
                if labels[next] == parent.label && owner[next] == -1 {
                    owner[next] = seedOwner
                    queue.append(next)
                }
            }
        }

        // Parent was cardinal-connected, therefore every parent pixel is
        // reachable from at least one seed. Rewrite only the visited region.
        for index in queue {
            let seedOwner = owner[index]
            if seedOwner >= 0 {
                labels[index] = childLabels[seedOwner]
            }
        }
    }

    private func componentsFromLabels(
        _ sourceLabels: [Int],
        probabilities: [Double],
        width: Int,
        height: Int
    ) -> (components: [Component], labels: [Int]) {
        guard let maximumLabel = sourceLabels.max(), maximumLabel >= 0 else {
            return ([], sourceLabels)
        }

        let size = maximumLabel + 1
        var area = [Int](repeating: 0, count: size)
        var minX = [Int](repeating: width, count: size)
        var minY = [Int](repeating: height, count: size)
        var maxX = [Int](repeating: 0, count: size)
        var maxY = [Int](repeating: 0, count: size)
        var sumX = [Double](repeating: 0, count: size)
        var sumY = [Double](repeating: 0, count: size)
        var probabilitySum = [Double](repeating: 0, count: size)
        var probabilitySquareSum = [Double](repeating: 0, count: size)

        for index in sourceLabels.indices {
            let label = sourceLabels[index]
            guard label >= 0 else { continue }
            let x = index % width
            let y = index / width
            let probability = probabilities[index]
            area[label] += 1
            minX[label] = min(minX[label], x)
            minY[label] = min(minY[label], y)
            maxX[label] = max(maxX[label], x)
            maxY[label] = max(maxY[label], y)
            sumX[label] += Double(x)
            sumY[label] += Double(y)
            probabilitySum[label] += probability
            probabilitySquareSum[label] += probability * probability
        }

        var remap = [Int](repeating: -1, count: size)
        var components: [Component] = []
        for oldLabel in 0..<size where area[oldLabel] > 0 {
            let count = Double(area[oldLabel])
            let mean = probabilitySum[oldLabel] / count
            let variance = max(0, probabilitySquareSum[oldLabel] / count - mean * mean)
            let newLabel = components.count
            remap[oldLabel] = newLabel
            components.append(
                Component(
                    label: newLabel,
                    area: area[oldLabel],
                    minX: minX[oldLabel],
                    minY: minY[oldLabel],
                    maxX: maxX[oldLabel],
                    maxY: maxY[oldLabel],
                    centroidX: sumX[oldLabel] / count,
                    centroidY: sumY[oldLabel] / count,
                    meanProbability: mean,
                    probabilityStdDev: sqrt(variance)
                )
            )
        }

        var labels = sourceLabels
        for index in labels.indices where labels[index] >= 0 {
            labels[index] = remap[labels[index]]
        }
        return (components, labels)
    }

    private func observation(
        id: Int,
        component: Component,
        color: ColorFeatures,
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
        let fill = (coverage / max(width * height, 0.0001)).clamped(0...1)
        let confidence = (
            0.28
                + component.meanProbability * 0.50
                + fill * 0.13
                + min(0.06, component.probabilityStdDev * 0.45)
        ).clamped(0.05...0.97)

        return CloudObservation(
            id: id,
            kind: Self.classify(
                coverage: coverage,
                aspectRatio: width / max(height, 0.01),
                brightness: color.brightness,
                saturation: color.saturation,
                fill: fill,
                probabilityStdDev: component.probabilityStdDev,
                brightnessStdDev: color.brightnessStdDev
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
        components: [Component],
        labels: [Int],
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> [Int: ColorFeatures] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [:] }
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let totalPixels = width * height
        var result: [Int: ColorFeatures] = [:]
        result.reserveCapacity(components.count)

        for component in components {
            let sampleStep = component.area > totalPixels / 10 ? 3 : 2
            var brightnessSum = 0.0
            var brightnessSquareSum = 0.0
            var saturationSum = 0.0
            var count = 0

            var y = component.minY
            while y <= component.maxY {
                var x = component.minX
                while x <= component.maxX {
                    let index = y * width + x
                    if labels[index] == component.label {
                        let offset = y * rowBytes + x * 4
                        let blue = Double(bytes[offset]) / 255.0
                        let green = Double(bytes[offset + 1]) / 255.0
                        let red = Double(bytes[offset + 2]) / 255.0
                        let maximum = max(red, max(green, blue))
                        let minimum = min(red, min(green, blue))
                        let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0
                        brightnessSum += maximum
                        brightnessSquareSum += maximum * maximum
                        saturationSum += saturation
                        count += 1
                    }
                    x += sampleStep
                }
                y += sampleStep
            }

            guard count > 0 else {
                result[component.label] = ColorFeatures(
                    brightness: 0.65,
                    saturation: 0.18,
                    brightnessStdDev: 0.05
                )
                continue
            }

            let divisor = Double(count)
            let brightness = brightnessSum / divisor
            let variance = max(0, brightnessSquareSum / divisor - brightness * brightness)
            result[component.label] = ColorFeatures(
                brightness: brightness,
                saturation: saturationSum / divisor,
                brightnessStdDev: sqrt(variance)
            )
        }
        return result
    }

    private func makeOverlayImage(
        labels: [Int],
        kindsByLabel: [Int: CloudKind],
        width: Int,
        height: Int
    ) -> CGImage? {
        guard !kindsByLabel.isEmpty else { return nil }

        var colorsByLabel: [Int: (r: UInt8, g: UInt8, b: UInt8)] = [:]
        for (label, kind) in kindsByLabel {
            colorsByLabel[label] = overlayColor(kind)
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = y * width + x
                let label = labels[pixel]
                guard let color = colorsByLabel[label] else { continue }

                let boundary = x == 0
                    || x + 1 == width
                    || y == 0
                    || y + 1 == height
                    || labels[pixel - 1] != label
                    || labels[pixel + 1] != label
                    || labels[pixel - width] != label
                    || labels[pixel + width] != label

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

    // Compatibility overload retained for existing tests/callers.
    static func classify(
        coverage: Double,
        aspectRatio: Double,
        brightness: Double,
        saturation: Double
    ) -> CloudKind {
        classify(
            coverage: coverage,
            aspectRatio: aspectRatio,
            brightness: brightness,
            saturation: saturation,
            fill: 0.60,
            probabilityStdDev: 0.05,
            brightnessStdDev: 0.08
        )
    }

    static func classify(
        coverage: Double,
        aspectRatio: Double,
        brightness: Double,
        saturation: Double,
        fill: Double,
        probabilityStdDev: Double,
        brightnessStdDev: Double
    ) -> CloudKind {
        // A frame-spanning cloud field is a layer, not one giant Cumulus.
        if coverage >= 0.52 {
            return probabilityStdDev >= 0.065 || brightnessStdDev >= 0.10
                ? .stratocumulus
                : .stratus
        }

        if coverage < 0.12
            && aspectRatio > 2.0
            && brightness > 0.66
            && saturation < 0.25
            && fill < 0.58 {
            return .cirrus
        }

        if coverage >= 0.28 {
            return .stratocumulus
        }

        if aspectRatio < 1.9 && fill >= 0.24 {
            return .cumulus
        }

        return .stratocumulus
    }
}
