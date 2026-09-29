import CoreGraphics
import Foundation

struct CloudTrackingStats: Equatable {
    let activeTracks: Int
    let visibleTracks: Int
    let matchedTracks: Int
    let createdTracks: Int
    let hiddenMissedTracks: Int
}

final class CloudTemporalStabilizer {
    private struct Track {
        let id: Int
        var detection: CloudDetection
        var misses: Int
        var hits: Int
        var velocity: CGPoint
        var pendingKind: CloudKind?
        var pendingKindCount: Int
    }

    private struct MatchCandidate {
        let trackIndex: Int
        let detectionIndex: Int
        let score: Double
        let centroidDistance: Double
    }

    private var tracks: [Track] = []
    private var nextTrackID = 1

    private let maximumTransientMisses = 1
    private let maximumMatureMisses = 3
    private let maximumCentroidDistance = 0.22
    private let minimumIntersectionOverUnion = 0.035
    private let immediateConfirmationCoverage = 0.08
    private let confirmationHits = 3

    private let initialKindConfirmationHits = 15
    private let establishedKindConfirmationHits = 60
    private let establishedKindAfterHits = 45

    private(set) var lastStats = CloudTrackingStats(
        activeTracks: 0,
        visibleTracks: 0,
        matchedTracks: 0,
        createdTracks: 0,
        hiddenMissedTracks: 0
    )

    func reset() {
        tracks.removeAll(keepingCapacity: true)
        nextTrackID = 1
        lastStats = CloudTrackingStats(
            activeTracks: 0,
            visibleTracks: 0,
            matchedTracks: 0,
            createdTracks: 0,
            hiddenMissedTracks: 0
        )
    }

    func update(raw detections: [CloudDetection]) -> [CloudDetection] {
        let candidates = matchCandidates(for: detections)
        var matchedTrackIndices = Set<Int>()
        var matchedDetectionIndices = Set<Int>()
        var matches: [Int: MatchCandidate] = [:]

        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            guard !matchedTrackIndices.contains(candidate.trackIndex),
                  !matchedDetectionIndices.contains(candidate.detectionIndex) else {
                continue
            }
            matchedTrackIndices.insert(candidate.trackIndex)
            matchedDetectionIndices.insert(candidate.detectionIndex)
            matches[candidate.trackIndex] = candidate
        }

        for index in tracks.indices {
            if let match = matches[index] {
                tracks[index] = updatedTrack(
                    tracks[index],
                    with: detections[match.detectionIndex],
                    centroidDistance: match.centroidDistance
                )
            } else {
                tracks[index].misses += 1
                tracks[index].velocity = CGPoint(
                    x: tracks[index].velocity.x * 0.45,
                    y: tracks[index].velocity.y * 0.45
                )
            }
        }

        tracks.removeAll { track in
            let maximumMisses = track.hits >= confirmationHits
                ? maximumMatureMisses
                : maximumTransientMisses
            return track.misses > maximumMisses
        }

        var createdTracks = 0
        for index in detections.indices where !matchedDetectionIndices.contains(index) {
            let detection = detectionWithStableID(detections[index], id: nextTrackID)
            tracks.append(
                Track(
                    id: nextTrackID,
                    detection: detection,
                    misses: 0,
                    hits: 1,
                    velocity: .zero,
                    pendingKind: nil,
                    pendingKindCount: 0
                )
            )
            nextTrackID += 1
            createdTracks += 1
        }

        let visible = tracks.filter { track in
            guard track.misses == 0 else { return false }
            return track.hits >= confirmationHits
                || track.detection.observation.coverage >= immediateConfirmationCoverage
        }

        lastStats = CloudTrackingStats(
            activeTracks: tracks.count,
            visibleTracks: visible.count,
            matchedTracks: matchedTrackIndices.count,
            createdTracks: createdTracks,
            hiddenMissedTracks: tracks.filter { $0.misses > 0 }.count
        )

        return visible
            .map(\.detection)
            .sorted { $0.estimate.midpointKilograms > $1.estimate.midpointKilograms }
    }

    private func matchCandidates(for detections: [CloudDetection]) -> [MatchCandidate] {
        var result: [MatchCandidate] = []
        result.reserveCapacity(tracks.count * detections.count)

        for trackIndex in tracks.indices {
            let existing = tracks[trackIndex]
            let predicted = CGPoint(
                x: clampUnit(existing.detection.observation.centroid.x + existing.velocity.x),
                y: clampUnit(existing.detection.observation.centroid.y + existing.velocity.y)
            )

            for detectionIndex in detections.indices {
                let candidate = detections[detectionIndex]
                let distance = centroidDistance(predicted, candidate.observation.centroid)
                let overlap = intersectionOverUnion(
                    existing.detection.observation.bounds,
                    candidate.observation.bounds
                )

                guard distance <= maximumCentroidDistance
                        || overlap >= minimumIntersectionOverUnion else {
                    continue
                }

                let oldCoverage = max(0.0001, existing.detection.observation.coverage)
                let newCoverage = max(0.0001, candidate.observation.coverage)
                let coverageRatio = min(oldCoverage, newCoverage) / max(oldCoverage, newCoverage)

                // A tiny track suddenly swallowed by a very broad region is
                // usually a merge, not continuity of the same physical cloud.
                if coverageRatio < 0.28 && max(oldCoverage, newCoverage) >= 0.38 {
                    continue
                }

                let distanceScore = max(0, 1 - distance / maximumCentroidDistance)
                let score = overlap * 0.52
                    + distanceScore * 0.35
                    + coverageRatio * 0.13

                result.append(
                    MatchCandidate(
                        trackIndex: trackIndex,
                        detectionIndex: detectionIndex,
                        score: score,
                        centroidDistance: distance
                    )
                )
            }
        }
        return result
    }

    private func updatedTrack(
        _ track: Track,
        with incoming: CloudDetection,
        centroidDistance: Double
    ) -> Track {
        var next = track
        next.misses = 0
        next.hits += 1

        let oldObservation = track.detection.observation
        let newObservation = incoming.observation
        let oldEstimate = track.detection.estimate
        let newEstimate = incoming.estimate

        let oldCoverage = max(0.0001, oldObservation.coverage)
        let newCoverage = max(0.0001, newObservation.coverage)
        let coverageRatio = min(oldCoverage, newCoverage) / max(oldCoverage, newCoverage)
        let geometryOverlap = intersectionOverUnion(oldObservation.bounds, newObservation.bounds)
        let majorGeometryChange = coverageRatio < 0.52
            || (geometryOverlap < 0.20 && centroidDistance > 0.04)
        let layerTransition = newObservation.coverage >= 0.42
            && oldObservation.coverage < 0.34

        let measuredVelocity = CGPoint(
            x: newObservation.centroid.x - oldObservation.centroid.x,
            y: newObservation.centroid.y - oldObservation.centroid.y
        )
        next.velocity = CGPoint(
            x: blend(track.velocity.x, measuredVelocity.x, alpha: 0.58),
            y: blend(track.velocity.y, measuredVelocity.y, alpha: 0.58)
        )

        let geometryAlpha = centroidDistance > 0.085 ? 0.90 : 0.70
        let measurementAlpha = centroidDistance > 0.085 ? 0.62 : 0.42
        let stableKind = stabilizedKind(
            track: &next,
            incoming: newObservation.kind,
            majorGeometryChange: majorGeometryChange,
            layerTransition: layerTransition
        )

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

        let incomingAgreesWithStableKind = newObservation.kind == stableKind
        let targetEstimate = incomingAgreesWithStableKind ? newEstimate : oldEstimate
        let kindChanged = stableKind != oldObservation.kind
        let massAlpha: Double
        if kindChanged {
            massAlpha = majorGeometryChange ? 0.28 : 0.10
        } else if incomingAgreesWithStableKind {
            massAlpha = centroidDistance > 0.085 ? 0.42 : 0.24
        } else {
            massAlpha = 0.04
        }

        let smoothedEstimate = blendEstimate(oldEstimate, targetEstimate, alpha: massAlpha)
        next.detection = CloudDetection(
            observation: smoothedObservation,
            estimate: smoothedEstimate
        )
        return next
    }

    private func stabilizedKind(
        track: inout Track,
        incoming: CloudKind,
        majorGeometryChange: Bool,
        layerTransition: Bool
    ) -> CloudKind {
        let current = track.detection.observation.kind
        guard incoming != current else {
            track.pendingKind = nil
            track.pendingKindCount = 0
            return current
        }

        // The field ZIP showed Cumulus surviving while the same mask grew from
        // ~28% to ~67% coverage. Crossing into a broad cloud layer must break
        // that stale type immediately.
        if layerTransition {
            track.pendingKind = nil
            track.pendingKindCount = 0
            return incoming
        }

        if track.pendingKind == incoming {
            track.pendingKindCount += 1
        } else {
            track.pendingKind = incoming
            track.pendingKindCount = 1
        }

        let requiredHits: Int
        if majorGeometryChange {
            requiredHits = 3
        } else {
            requiredHits = track.hits < establishedKindAfterHits
                ? initialKindConfirmationHits
                : establishedKindConfirmationHits
        }

        if track.pendingKindCount >= requiredHits {
            track.pendingKind = nil
            track.pendingKindCount = 0
            return incoming
        }
        return current
    }

    private func blendEstimate(
        _ old: CloudMassEstimate,
        _ new: CloudMassEstimate,
        alpha: Double
    ) -> CloudMassEstimate {
        CloudMassEstimate(
            lowKilograms: blend(old.lowKilograms, new.lowKilograms, alpha: alpha),
            midpointKilograms: blend(old.midpointKilograms, new.midpointKilograms, alpha: alpha),
            highKilograms: blend(old.highKilograms, new.highKilograms, alpha: alpha),
            estimatedWidthMeters: blend(old.estimatedWidthMeters, new.estimatedWidthMeters, alpha: alpha),
            estimatedHeightMeters: blend(old.estimatedHeightMeters, new.estimatedHeightMeters, alpha: alpha),
            estimatedDepthMeters: blend(old.estimatedDepthMeters, new.estimatedDepthMeters, alpha: alpha),
            estimatedDistanceMeters: blend(old.estimatedDistanceMeters, new.estimatedDistanceMeters, alpha: alpha),
            projectedAreaSquareMeters: blend(old.projectedAreaSquareMeters, new.projectedAreaSquareMeters, alpha: alpha),
            estimatedVolumeCubicMeters: blend(old.estimatedVolumeCubicMeters, new.estimatedVolumeCubicMeters, alpha: alpha),
            angularWidthDegrees: blend(old.angularWidthDegrees, new.angularWidthDegrees, alpha: alpha),
            angularHeightDegrees: blend(old.angularHeightDegrees, new.angularHeightDegrees, alpha: alpha),
            centerElevationDegrees: blend(old.centerElevationDegrees, new.centerElevationDegrees, alpha: alpha),
            confidence: blend(old.confidence, new.confidence, alpha: alpha)
        )
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

    private func clampUnit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
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
