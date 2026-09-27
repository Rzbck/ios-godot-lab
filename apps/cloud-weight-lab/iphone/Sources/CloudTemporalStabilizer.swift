import CoreGraphics
import Foundation

final class CloudTemporalStabilizer {
    private struct Track {
        let id: Int
        var detection: CloudDetection
        var misses: Int
        var pendingKind: CloudKind?
        var pendingKindCount: Int
    }

    private var tracks: [Track] = []
    private var nextTrackID = 1

    private let maximumMisses = 1
    private let maximumCentroidDistance = 0.22
    private let minimumIntersectionOverUnion = 0.04

    func reset() {
        tracks.removeAll(keepingCapacity: true)
        nextTrackID = 1
    }

    func update(raw detections: [CloudDetection]) -> [CloudDetection] {
        var unmatched = Set(detections.indices)

        for index in tracks.indices {
            guard let match = bestMatch(for: tracks[index].detection, in: detections, candidates: unmatched) else {
                tracks[index].misses += 1
                continue
            }

            unmatched.remove(match.index)
            tracks[index] = updatedTrack(
                tracks[index],
                with: detections[match.index],
                centroidDistance: match.centroidDistance
            )
        }

        tracks.removeAll { $0.misses > maximumMisses }

        for index in unmatched.sorted() {
            let detection = detectionWithStableID(detections[index], id: nextTrackID)
            tracks.append(
                Track(
                    id: nextTrackID,
                    detection: detection,
                    misses: 0,
                    pendingKind: nil,
                    pendingKindCount: 0
                )
            )
            nextTrackID += 1
        }

        return tracks
            .map(\.detection)
            .sorted { $0.estimate.midpointKilograms > $1.estimate.midpointKilograms }
    }

    private func bestMatch(
        for existing: CloudDetection,
        in detections: [CloudDetection],
        candidates: Set<Int>
    ) -> (index: Int, score: Double, centroidDistance: Double)? {
        var best: (index: Int, score: Double, centroidDistance: Double)?

        for index in candidates {
            let candidate = detections[index]
            let distance = centroidDistance(
                existing.observation.centroid,
                candidate.observation.centroid
            )
            let overlap = intersectionOverUnion(
                existing.observation.bounds,
                candidate.observation.bounds
            )

            guard distance <= maximumCentroidDistance || overlap >= minimumIntersectionOverUnion else {
                continue
            }

            let distanceScore = max(0, 1 - distance / maximumCentroidDistance)
            let score = overlap * 0.72 + distanceScore * 0.28

            if best == nil || score > best!.score {
                best = (index, score, distance)
            }
        }

        return best
    }

    private func updatedTrack(
        _ track: Track,
        with incoming: CloudDetection,
        centroidDistance: Double
    ) -> Track {
        var next = track
        next.misses = 0

        let geometryAlpha = centroidDistance > 0.10 ? 0.68 : 0.34
        let measurementAlpha = centroidDistance > 0.10 ? 0.48 : 0.24
        let stableKind = stabilizedKind(track: &next, incoming: incoming.observation.kind)

        let oldObservation = track.detection.observation
        let newObservation = incoming.observation
        let oldEstimate = track.detection.estimate
        let newEstimate = incoming.estimate

        let smoothedObservation = CloudObservation(
            id: track.id,
            kind: stableKind,
            confidence: blend(oldObservation.confidence, newObservation.confidence, alpha: measurementAlpha),
            coverage: blend(oldObservation.coverage, newObservation.coverage, alpha: measurementAlpha),
            bounds: blend(oldObservation.bounds, newObservation.bounds, alpha: geometryAlpha),
            centroid: blend(oldObservation.centroid, newObservation.centroid, alpha: geometryAlpha),
            averageBrightness: blend(oldObservation.averageBrightness, newObservation.averageBrightness, alpha: measurementAlpha),
            averageSaturation: blend(oldObservation.averageSaturation, newObservation.averageSaturation, alpha: measurementAlpha),
            fieldOfViewDegrees: newObservation.fieldOfViewDegrees
        )

        let smoothedEstimate = CloudMassEstimate(
            lowKilograms: blend(oldEstimate.lowKilograms, newEstimate.lowKilograms, alpha: measurementAlpha),
            midpointKilograms: blend(oldEstimate.midpointKilograms, newEstimate.midpointKilograms, alpha: measurementAlpha),
            highKilograms: blend(oldEstimate.highKilograms, newEstimate.highKilograms, alpha: measurementAlpha),
            estimatedWidthMeters: blend(oldEstimate.estimatedWidthMeters, newEstimate.estimatedWidthMeters, alpha: measurementAlpha),
            estimatedHeightMeters: blend(oldEstimate.estimatedHeightMeters, newEstimate.estimatedHeightMeters, alpha: measurementAlpha),
            confidence: blend(oldEstimate.confidence, newEstimate.confidence, alpha: measurementAlpha)
        )

        next.detection = CloudDetection(
            observation: smoothedObservation,
            estimate: smoothedEstimate
        )
        return next
    }

    private func stabilizedKind(track: inout Track, incoming: CloudKind) -> CloudKind {
        let current = track.detection.observation.kind
        guard incoming != current else {
            track.pendingKind = nil
            track.pendingKindCount = 0
            return current
        }

        if track.pendingKind == incoming {
            track.pendingKindCount += 1
        } else {
            track.pendingKind = incoming
            track.pendingKindCount = 1
        }

        if track.pendingKindCount >= 3 {
            track.pendingKind = nil
            track.pendingKindCount = 0
            return incoming
        }
        return current
    }

    private func detectionWithStableID(_ detection: CloudDetection, id: Int) -> CloudDetection {
        let observation = detection.observation
        return CloudDetection(
            observation: CloudObservation(
                id: id,
                kind: observation.kind,
                confidence: observation.confidence,
                coverage: observation.coverage,
                bounds: observation.bounds,
                centroid: observation.centroid,
                averageBrightness: observation.averageBrightness,
                averageSaturation: observation.averageSaturation,
                fieldOfViewDegrees: observation.fieldOfViewDegrees
            ),
            estimate: detection.estimate
        )
    }

    private func centroidDistance(_ lhs: CGPoint, _ rhs: CGPoint) -> Double {
        let dx = Double(lhs.x - rhs.x)
        let dy = Double(lhs.y - rhs.y)
        return sqrt(dx * dx + dy * dy)
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }

        let intersectionArea = Double(intersection.width * intersection.height)
        let lhsArea = Double(lhs.width * lhs.height)
        let rhsArea = Double(rhs.width * rhs.height)
        let union = lhsArea + rhsArea - intersectionArea
        guard union > 0 else { return 0 }
        return intersectionArea / union
    }

    private func blend(_ old: Double, _ new: Double, alpha: Double) -> Double {
        old + (new - old) * alpha
    }

    private func blend(_ old: CGFloat, _ new: CGFloat, alpha: Double) -> CGFloat {
        old + (new - old) * CGFloat(alpha)
    }

    private func blend(_ old: CGPoint, _ new: CGPoint, alpha: Double) -> CGPoint {
        CGPoint(
            x: blend(old.x, new.x, alpha: alpha),
            y: blend(old.y, new.y, alpha: alpha)
        )
    }

    private func blend(_ old: CGRect, _ new: CGRect, alpha: Double) -> CGRect {
        CGRect(
            x: blend(old.origin.x, new.origin.x, alpha: alpha),
            y: blend(old.origin.y, new.origin.y, alpha: alpha),
            width: blend(old.size.width, new.size.width, alpha: alpha),
            height: blend(old.size.height, new.size.height, alpha: alpha)
        )
    }
}
