import CoreGraphics
import Foundation

final class CloudOverlayStabilizer {
    private var history: [[UInt8]] = []
    private var width = 0
    private var height = 0
    private var lastOutput: CGImage?
    private var missingFrames = 0

    private let historyLimit = 3
    private let resetChangePercent = 18.0

    func reset() {
        history.removeAll(keepingCapacity: true)
        width = 0
        height = 0
        lastOutput = nil
        missingFrames = 0
    }

    func update(_ image: CGImage?) -> CGImage? {
        guard let image else {
            missingFrames += 1
            if missingFrames <= 1 {
                return lastOutput
            }
            reset()
            return nil
        }

        missingFrames = 0
        guard let current = alphaMask(from: image) else {
            reset()
            return image
        }

        if width != image.width || height != image.height {
            history.removeAll(keepingCapacity: true)
            width = image.width
            height = image.height
        }

        if let previous = history.last,
           changePercent(previous, current) > resetChangePercent {
            history.removeAll(keepingCapacity: true)
        }

        history.append(current)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }

        let displayMask: [UInt8]
        if history.count < historyLimit {
            displayMask = current
        } else {
            displayMask = majorityMask(history)
        }

        let output = makeOverlay(mask: displayMask, width: width, height: height)
        lastOutput = output ?? image
        return lastOutput
    }

    private func alphaMask(from image: CGImage) -> [UInt8]? {
        guard image.bitsPerPixel >= 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let alphaOffset = min(3, bytesPerPixel - 1)
        var mask = [UInt8](repeating: 0, count: image.width * image.height)

        for y in 0..<image.height {
            let row = y * image.bytesPerRow
            for x in 0..<image.width {
                let offset = row + x * bytesPerPixel + alphaOffset
                mask[y * image.width + x] = bytes[offset] > 0 ? 1 : 0
            }
        }
        return mask
    }

    private func changePercent(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !rhs.isEmpty else { return 100 }
        var changed = 0
        for index in rhs.indices where lhs[index] != rhs[index] {
            changed += 1
        }
        return Double(changed) / Double(rhs.count) * 100
    }

    private func majorityMask(_ masks: [[UInt8]]) -> [UInt8] {
        guard let first = masks.first else { return [] }
        var result = [UInt8](repeating: 0, count: first.count)
        let required = masks.count / 2 + 1

        for index in first.indices {
            var votes = 0
            for mask in masks where mask[index] != 0 {
                votes += 1
            }
            result[index] = votes >= required ? 1 : 0
        }
        return result
    }

    private func makeOverlay(mask: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, mask.count == width * height else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        func isCloud(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return mask[y * width + x] != 0
        }

        for y in 0..<height {
            for x in 0..<width where isCloud(x, y) {
                let boundary =
                    !isCloud(x - 1, y)
                    || !isCloud(x + 1, y)
                    || !isCloud(x, y - 1)
                    || !isCloud(x, y + 1)
                let offset = (y * width + x) * 4
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
}
