import CoreGraphics
import CoreVideo
import Foundation

struct CloudStructureRegion: Equatable {
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
    let highConfidenceFraction: Double
    let meanBrightness: Double
    let brightnessStdDev: Double
    let meanSaturation: Double
    let saturationStdDev: Double
    let fillRatio: Double
    let boundaryRatio: Double
    let compactness: Double
    let edgeTouchCount: Int
    let frameCoverage: Double
    let parentCoverage: Double
    let parentWasSplit: Bool

    var pixelWidth: Int { maxX - minX + 1 }
    var pixelHeight: Int { maxY - minY + 1 }
}

struct CloudStructureExtraction {
    let labels: [Int]
    let regions: [CloudStructureRegion]
}

enum CloudStructureAnalyzer {
    private struct ParentComponent {
        var area = 0
        var hasSeed = false
    }

    private struct SeedComponent {
        let label: Int
        let parentLabel: Int
        let area: Int
        let centroidX: Double
        let centroidY: Double
    }

    private struct Accumulator {
        var area = 0
        var minX: Int
        var minY: Int
        var maxX = 0
        var maxY = 0
        var sumX = 0.0
        var sumY = 0.0
        var probabilitySum = 0.0
        var probabilitySquareSum = 0.0
        var highConfidencePixels = 0
        var brightnessSum = 0.0
        var brightnessSquareSum = 0.0
        var saturationSum = 0.0
        var saturationSquareSum = 0.0
        var boundaryEdges = 0
        var touchesLeft = false
        var touchesRight = false
        var touchesTop = false
        var touchesBottom = false

        init(width: Int, height: Int) {
            minX = width
            minY = height
        }
    }

    static func extract(
        candidateMask: [Bool],
        seedMask: [Bool],
        probabilities: [Double],
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> CloudStructureExtraction {
        let count = width * height
        guard width > 0,
              height > 0,
              candidateMask.count == count,
              seedMask.count == count,
              probabilities.count == count else {
            return CloudStructureExtraction(
                labels: [Int](repeating: -1, count: max(0, count)),
                regions: []
            )
        }

        let parents = parentComponents(
            candidateMask: candidateMask,
            seedMask: seedMask,
            width: width,
            height: height
        )

        guard !parents.components.isEmpty else {
            return CloudStructureExtraction(
                labels: [Int](repeating: -1, count: count),
                regions: []
            )
        }

        let seeds = seedComponents(
            seedMask: seedMask,
            parentLabels: parents.labels,
            validParents: parents.components.map(\.hasSeed),
            width: width,
            height: height
        )

        let final = buildFinalLabels(
            parentLabels: parents.labels,
            parents: parents.components,
            seedLabels: seeds.labels,
            seeds: seeds.components,
            width: width,
            height: height
        )

        let regions = summarize(
            labels: final.labels,
            labelParents: final.labelParents,
            parentSplit: final.parentSplit,
            parents: parents.components,
            seedMask: seedMask,
            probabilities: probabilities,
            pixelBuffer: pixelBuffer,
            width: width,
            height: height
        )

        return CloudStructureExtraction(labels: final.labels, regions: regions)
    }

    static func classify(_ region: CloudStructureRegion) -> CloudKind {
        let aspectRatio = Double(region.pixelWidth) / Double(max(1, region.pixelHeight))
        let normalizedWidth = min(1.0, Double(region.pixelWidth) * region.frameCoverage / max(region.frameCoverage, 0.000_001) / Double(max(1, region.area)) * Double(region.area) / Double(max(1, region.pixelHeight)))

        // Derive normalized width directly from fill/coverage when possible:
        // coverage / fill = normalized bounding-box area.
        let normalizedBoxArea = region.frameCoverage / max(region.fillRatio, 0.000_1)
        let normalizedHeight = sqrt(max(0.000_1, normalizedBoxArea / max(aspectRatio, 0.01)))
        let boxWidth = min(1.0, normalizedHeight * aspectRatio)

        // WMO morphology translated into inexpensive image cues:
        // - Cirrus: narrow/fibrous/low-fill elements.
        // - Cumulus: isolated compact heaps with a defined outline.
        // - Stratocumulus: broad layer with visible cells/texture/rolls.
        // - Stratus: broad comparatively uniform sheet/layer.
        let wispy = region.frameCoverage <= 0.18
            && aspectRatio >= 2.0
            && region.fillRatio <= 0.62
            && region.meanBrightness >= 0.56
            && region.meanSaturation <= 0.30
            && (region.compactness <= 0.34 || region.boundaryRatio >= 1.35)

        if wispy {
            return .cirrus
        }

        let layerLike = region.parentCoverage >= 0.46
            || region.frameCoverage >= 0.42
            || (boxWidth >= 0.78 && region.edgeTouchCount >= 2)
            || (boxWidth >= 0.70 && aspectRatio >= 2.0 && region.fillRatio >= 0.48)

        let textureScore = region.brightnessStdDev * 1.7
            + region.probabilityStdDev * 1.35
            + max(0, region.boundaryRatio - 1.0) * 0.13

        let cellularLayer = textureScore >= 0.24
            || region.boundaryRatio >= 1.42
            || (region.parentWasSplit && region.parentCoverage >= 0.30)

        if layerLike {
            return cellularLayer ? .stratocumulus : .stratus
        }

        let compactHeap = region.frameCoverage <= 0.34
            && aspectRatio >= 0.42
            && aspectRatio <= 1.95
            && region.fillRatio >= 0.40
            && region.compactness >= 0.12

        if compactHeap {
            return .cumulus
        }

        if boxWidth >= 0.48
            && (cellularLayer || aspectRatio >= 1.7) {
            return .stratocumulus
        }

        return .unknown
    }

    static func classificationConfidence(
        _ region: CloudStructureRegion,
        kind: CloudKind
    ) -> Double {
        switch kind {
        case .cirrus:
            return (
                0.48
                + min(0.22, max(0, region.boundaryRatio - 1.0) * 0.16)
                + min(0.16, max(0, 0.65 - region.fillRatio) * 0.35)
            ).clamped(0.35...0.88)

        case .cumulus:
            return (
                0.50
                + region.fillRatio * 0.18
                + region.compactness * 0.22
            ).clamped(0.38...0.90)

        case .stratocumulus:
            return (
                0.48
                + min(0.18, region.parentCoverage * 0.18)
                + min(0.18, region.brightnessStdDev * 1.3)
                + min(0.12, region.probabilityStdDev)
            ).clamped(0.38...0.90)

        case .stratus:
            let uniformity = max(0, 1 - region.brightnessStdDev * 4.0)
            return (
                0.48
                + min(0.20, region.parentCoverage * 0.20)
                + uniformity * 0.16
            ).clamped(0.38...0.90)

        case .unknown:
            return 0.40
        }
    }

    private static func parentComponents(
        candidateMask: [Bool],
        seedMask: [Bool],
        width: Int,
        height: Int
    ) -> (labels: [Int], components: [ParentComponent]) {
        let count = width * height
        var labels = [Int](repeating: -1, count: count)
        var components: [ParentComponent] = []
        var queue = [Int]()
        queue.reserveCapacity(max(256, count / 8))

        for start in 0..<count where candidateMask[start] && labels[start] == -1 {
            let label = components.count
            labels[start] = label
            queue.removeAll(keepingCapacity: true)
            queue.append(start)

            var cursor = 0
            var component = ParentComponent()

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                component.area += 1
                component.hasSeed = component.hasSeed || seedMask[index]

                let x = index % width
                let y = index / width

                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        if nx == x && ny == y { continue }
                        let next = ny * width + nx
                        guard candidateMask[next], labels[next] == -1 else { continue }
                        labels[next] = label
                        queue.append(next)
                    }
                }
            }

            components.append(component)
        }

        return (labels, components)
    }

    private static func seedComponents(
        seedMask: [Bool],
        parentLabels: [Int],
        validParents: [Bool],
        width: Int,
        height: Int
    ) -> (labels: [Int], components: [SeedComponent]) {
        let count = width * height
        var labels = [Int](repeating: -1, count: count)
        var components: [SeedComponent] = []
        var queue = [Int]()
        queue.reserveCapacity(max(128, count / 16))

        for start in 0..<count where seedMask[start] && labels[start] == -1 {
            let parentLabel = parentLabels[start]
            guard parentLabel >= 0,
                  parentLabel < validParents.count,
                  validParents[parentLabel] else {
                continue
            }

            let label = components.count
            labels[start] = label
            queue.removeAll(keepingCapacity: true)
            queue.append(start)

            var cursor = 0
            var area = 0
            var sumX = 0.0
            var sumY = 0.0

            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                area += 1

                let x = index % width
                let y = index / width
                sumX += Double(x)
                sumY += Double(y)

                for ny in max(0, y - 1)...min(height - 1, y + 1) {
                    for nx in max(0, x - 1)...min(width - 1, x + 1) {
                        if nx == x && ny == y { continue }
                        let next = ny * width + nx
                        guard seedMask[next],
                              parentLabels[next] == parentLabel,
                              labels[next] == -1 else {
                            continue
                        }
                        labels[next] = label
                        queue.append(next)
                    }
                }
            }

            components.append(
                SeedComponent(
                    label: label,
                    parentLabel: parentLabel,
                    area: area,
                    centroidX: sumX / Double(max(1, area)),
                    centroidY: sumY / Double(max(1, area))
                )
            )
        }

        return (labels, components)
    }

    private static func buildFinalLabels(
        parentLabels: [Int],
        parents: [ParentComponent],
        seedLabels: [Int],
        seeds: [SeedComponent],
        width: Int,
        height: Int
    ) -> (
        labels: [Int],
        labelParents: [Int],
        parentSplit: [Bool]
    ) {
        let count = width * height
        let frameArea = Double(max(1, count))
        let minimumSeedArea = max(24, Int(frameArea * 0.000_25))
        var seedsByParent = [[SeedComponent]](repeating: [], count: parents.count)

        for seed in seeds where seed.area >= minimumSeedArea {
            seedsByParent[seed.parentLabel].append(seed)
        }

        var selectedSeedLabelsByParent = [[Int]](repeating: [], count: parents.count)
        var parentSplit = [Bool](repeating: false, count: parents.count)

        for parentIndex in parents.indices where parents[parentIndex].hasSeed {
            let parentCoverage = Double(parents[parentIndex].area) / frameArea
            let sorted = seedsByParent[parentIndex].sorted { $0.area > $1.area }
            guard parentCoverage >= 0.08, sorted.count >= 2 else { continue }

            var selected: [SeedComponent] = []
            for seed in sorted {
                guard selected.count < 6 else { break }

                let separated = selected.allSatisfy { existing in
                    let dx = (seed.centroidX - existing.centroidX) / Double(width)
                    let dy = (seed.centroidY - existing.centroidY) / Double(height)
                    return sqrt(dx * dx + dy * dy) >= 0.065
                }

                if separated {
                    selected.append(seed)
                }
            }

            guard selected.count >= 2 else { continue }

            let secondSeedFraction = Double(selected[1].area)
                / Double(max(1, parents[parentIndex].area))
            guard secondSeedFraction >= 0.010 else { continue }

            parentSplit[parentIndex] = true
            selectedSeedLabelsByParent[parentIndex] = selected.map(\.label)
        }

        var finalLabels = [Int](repeating: -1, count: count)
        var labelParents: [Int] = []
        var defaultLabelByParent = [Int](repeating: -1, count: parents.count)
        var seedToFinal: [Int: Int] = [:]
        var nextFinalLabel = 0

        for parentIndex in parents.indices where parents[parentIndex].hasSeed {
            if parentSplit[parentIndex] {
                for seedLabel in selectedSeedLabelsByParent[parentIndex] {
                    seedToFinal[seedLabel] = nextFinalLabel
                    labelParents.append(parentIndex)
                    nextFinalLabel += 1
                }
            } else {
                defaultLabelByParent[parentIndex] = nextFinalLabel
                labelParents.append(parentIndex)
                nextFinalLabel += 1
            }
        }

        for index in 0..<count {
            let parent = parentLabels[index]
            guard parent >= 0, parent < parents.count, parents[parent].hasSeed else { continue }
            if !parentSplit[parent] {
                finalLabels[index] = defaultLabelByParent[parent]
            }
        }

        var queue = [Int]()
        queue.reserveCapacity(max(256, count / 4))

        for index in 0..<count {
            let parent = parentLabels[index]
            guard parent >= 0,
                  parent < parents.count,
                  parentSplit[parent] else {
                continue
            }

            let seedLabel = seedLabels[index]
            guard let finalLabel = seedToFinal[seedLabel] else { continue }
            finalLabels[index] = finalLabel
            queue.append(index)
        }

        var cursor = 0
        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1

            let label = finalLabels[index]
            let parent = parentLabels[index]
            let x = index % width
            let y = index / width

            for ny in max(0, y - 1)...min(height - 1, y + 1) {
                for nx in max(0, x - 1)...min(width - 1, x + 1) {
                    if nx == x && ny == y { continue }
                    let next = ny * width + nx
                    guard parentLabels[next] == parent,
                          finalLabels[next] == -1 else {
                        continue
                    }
                    finalLabels[next] = label
                    queue.append(next)
                }
            }
        }

        return (finalLabels, labelParents, parentSplit)
    }

    private static func summarize(
        labels: [Int],
        labelParents: [Int],
        parentSplit: [Bool],
        parents: [ParentComponent],
        seedMask: [Bool],
        probabilities: [Double],
        pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int
    ) -> [CloudStructureRegion] {
        guard !labelParents.isEmpty else { return [] }

        var accumulators = labelParents.map { _ in
            Accumulator(width: width, height: height)
        }

        let canReadPixels = CVPixelBufferGetWidth(pixelBuffer) == width
            && CVPixelBufferGetHeight(pixelBuffer) == height
        if canReadPixels {
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        }
        defer {
            if canReadPixels {
                CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            }
        }

        let base = canReadPixels
            ? CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self)
            : nil
        let rowBytes = canReadPixels ? CVPixelBufferGetBytesPerRow(pixelBuffer) : 0
        let frameArea = Double(max(1, width * height))

        for index in labels.indices {
            let label = labels[index]
            guard label >= 0, label < accumulators.count else { continue }

            let x = index % width
            let y = index / width
            var accumulator = accumulators[label]
            accumulator.area += 1
            accumulator.minX = min(accumulator.minX, x)
            accumulator.minY = min(accumulator.minY, y)
            accumulator.maxX = max(accumulator.maxX, x)
            accumulator.maxY = max(accumulator.maxY, y)
            accumulator.sumX += Double(x)
            accumulator.sumY += Double(y)

            let probability = probabilities[index]
            accumulator.probabilitySum += probability
            accumulator.probabilitySquareSum += probability * probability
            if seedMask[index] {
                accumulator.highConfidencePixels += 1
            }

            if let base {
                let offset = y * rowBytes + x * 4
                let blue = Double(base[offset]) / 255.0
                let green = Double(base[offset + 1]) / 255.0
                let red = Double(base[offset + 2]) / 255.0
                let maximum = max(red, max(green, blue))
                let minimum = min(red, min(green, blue))
                let saturation = maximum > 0 ? (maximum - minimum) / maximum : 0

                accumulator.brightnessSum += maximum
                accumulator.brightnessSquareSum += maximum * maximum
                accumulator.saturationSum += saturation
                accumulator.saturationSquareSum += saturation * saturation
            }

            if x == 0 { accumulator.touchesLeft = true }
            if x == width - 1 { accumulator.touchesRight = true }
            if y == 0 { accumulator.touchesTop = true }
            if y == height - 1 { accumulator.touchesBottom = true }

            let left = x > 0 ? labels[index - 1] : -1
            let right = x + 1 < width ? labels[index + 1] : -1
            let top = y > 0 ? labels[index - width] : -1
            let bottom = y + 1 < height ? labels[index + width] : -1
            if left != label { accumulator.boundaryEdges += 1 }
            if right != label { accumulator.boundaryEdges += 1 }
            if top != label { accumulator.boundaryEdges += 1 }
            if bottom != label { accumulator.boundaryEdges += 1 }

            accumulators[label] = accumulator
        }

        return accumulators.enumerated().compactMap { label, accumulator in
            guard accumulator.area > 0 else { return nil }

            let count = Double(accumulator.area)
            let boxWidth = accumulator.maxX - accumulator.minX + 1
            let boxHeight = accumulator.maxY - accumulator.minY + 1
            let boxArea = Double(max(1, boxWidth * boxHeight))
            let meanProbability = accumulator.probabilitySum / count
            let probabilityVariance = max(
                0,
                accumulator.probabilitySquareSum / count - meanProbability * meanProbability
            )
            let meanBrightness = base == nil ? 0.65 : accumulator.brightnessSum / count
            let brightnessVariance = base == nil ? 0 : max(
                0,
                accumulator.brightnessSquareSum / count - meanBrightness * meanBrightness
            )
            let meanSaturation = base == nil ? 0.18 : accumulator.saturationSum / count
            let saturationVariance = base == nil ? 0 : max(
                0,
                accumulator.saturationSquareSum / count - meanSaturation * meanSaturation
            )
            let perimeter = Double(max(1, accumulator.boundaryEdges))
            let boxPerimeter = Double(max(1, 2 * (boxWidth + boxHeight)))
            let compactness = (4.0 * Double.pi * count / (perimeter * perimeter)).clamped(0...1)
            let edgeTouchCount = [
                accumulator.touchesLeft,
                accumulator.touchesRight,
                accumulator.touchesTop,
                accumulator.touchesBottom
            ].filter { $0 }.count

            let parent = labelParents[label]
            let parentCoverage = parent >= 0 && parent < parents.count
                ? Double(parents[parent].area) / frameArea
                : Double(accumulator.area) / frameArea

            return CloudStructureRegion(
                label: label,
                area: accumulator.area,
                minX: accumulator.minX,
                minY: accumulator.minY,
                maxX: accumulator.maxX,
                maxY: accumulator.maxY,
                centroidX: accumulator.sumX / count,
                centroidY: accumulator.sumY / count,
                meanProbability: meanProbability,
                probabilityStdDev: sqrt(probabilityVariance),
                highConfidenceFraction: Double(accumulator.highConfidencePixels) / count,
                meanBrightness: meanBrightness,
                brightnessStdDev: sqrt(brightnessVariance),
                meanSaturation: meanSaturation,
                saturationStdDev: sqrt(saturationVariance),
                fillRatio: (count / boxArea).clamped(0...1),
                boundaryRatio: max(1.0, perimeter / boxPerimeter),
                compactness: compactness,
                edgeTouchCount: edgeTouchCount,
                frameCoverage: count / frameArea,
                parentCoverage: parentCoverage,
                parentWasSplit: parent >= 0 && parent < parentSplit.count
                    ? parentSplit[parent]
                    : false
            )
        }
    }
}
