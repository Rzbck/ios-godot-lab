import CoreGraphics
import Foundation

final class CloudOverlayStabilizer {
    private var width = 0
    private var height = 0

    func reset() {
        width = 0
        height = 0
    }

    func update(_ image: CGImage?, detections: [CloudDetection]) -> CGImage? {
        guard let image else {
            reset()
            return nil
        }

        // Keep the raw segmentation visible for diagnostics even when the
        // physical geometry rejects every mass estimate (for example a cloud
        // image displayed on a monitor below the horizon).
        guard !detections.isEmpty else {
            reset()
            return image
        }

        guard let mask = alphaMask(from: image) else {
            reset()
            return nil
        }

        if width != image.width || height != image.height {
            width = image.width
            height = image.height
        }

        return makeOverlay(
            mask: mask,
            detections: detections,
            width: width,
            height: height
        )
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

    private func makeOverlay(
        mask: [UInt8],
        detections: [CloudDetection],
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0, mask.count == width * height else { return nil }

        var assignments = [Int](repeating: -1, count: width * height)
        let expanded = detections.map { detection in
            (
                detection: detection,
                bounds: detection.observation.bounds.insetBy(dx: -0.018, dy: -0.018)
            )
        }

        for y in 0..<height {
            let normalizedY = (CGFloat(y) + 0.5) / CGFloat(height)
            for x in 0..<width where mask[y * width + x] != 0 {
                let normalizedX = (CGFloat(x) + 0.5) / CGFloat(width)
                let point = CGPoint(x: normalizedX, y: normalizedY)

                var bestID = -1
                var bestDistance = Double.greatestFiniteMagnitude
                for item in expanded where item.bounds.contains(point) {
                    let centroid = item.detection.observation.centroid
                    let dx = Double(point.x - centroid.x)
                    let dy = Double(point.y - centroid.y)
                    let distance = dx * dx + dy * dy
                    if distance < bestDistance {
                        bestDistance = distance
                        bestID = item.detection.id
                    }
                }

                if bestID >= 0 {
                    assignments[y * width + x] = bestID
                }
            }
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)

        func assignedID(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, x < width, y >= 0, y < height else { return -1 }
            return assignments[y * width + x]
        }

        for y in 0..<height {
            for x in 0..<width {
                let id = assignedID(x, y)
                guard id >= 0 else { continue }

                let boundary =
                    assignedID(x - 1, y) != id
                    || assignedID(x + 1, y) != id
                    || assignedID(x, y - 1) != id
                    || assignedID(x, y + 1) != id
                let offset = (y * width + x) * 4
                let color = trackColor(id)
                rgba[offset] = color.0
                rgba[offset + 1] = color.1
                rgba[offset + 2] = color.2
                rgba[offset + 3] = boundary ? 238 : 48
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

    private func trackColor(_ id: Int) -> (UInt8, UInt8, UInt8) {
        let palette: [(UInt8, UInt8, UInt8)] = [
            (70, 214, 255),
            (255, 177, 72),
            (194, 121, 255),
            (80, 242, 179),
            (255, 104, 158),
            (255, 231, 92),
            (112, 157, 255),
            (120, 245, 235)
        ]
        let index = abs(id) % palette.count
        return palette[index]
    }
}
