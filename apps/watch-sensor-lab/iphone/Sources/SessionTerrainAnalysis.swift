import CoreLocation
import Foundation

struct SessionTerrainPoint: Identifiable, Equatable {
    let distanceMeters: Double
    let altitudeMeters: Double
    let gradePercent: Double?

    var id: Double { distanceMeters }
}

struct SessionTerrainReport: Equatable {
    let points: [SessionTerrainPoint]
    let elevationRangeMeters: Double?
    let maxUphillGradePercent: Double?
    let maxDownhillGradePercent: Double?
    let reliefLabel: String
    let surfaceLabel: String
    let note: String

    static let unavailable = SessionTerrainReport(
        points: [],
        elevationRangeMeters: nil,
        maxUphillGradePercent: nil,
        maxDownhillGradePercent: nil,
        reliefLabel: "Indisponible",
        surfaceLabel: "Indéterminée",
        note: "Pas assez de points altitude/GPS fiables pour établir un profil."
    )
}

struct SessionTerrainAnalyzer {
    private struct RawPoint {
        let location: CLLocation
        let verticalAccuracy: Double
    }

    func analyze(sessionID: String) -> SessionTerrainReport {
        let raw = loadPoints(sessionID: sessionID)
        guard raw.count >= 3 else { return .unavailable }

        var result: [SessionTerrainPoint] = []
        result.reserveCapacity(min(raw.count, 1_500))
        var cumulative = 0.0
        var previous = raw[0]
        var altitudes: [Double] = [previous.location.altitude]
        var grades: [Double] = []
        result.append(SessionTerrainPoint(distanceMeters: 0, altitudeMeters: previous.location.altitude, gradePercent: nil))

        for current in raw.dropFirst() {
            let segmentDistance = current.location.distance(from: previous.location)
            guard segmentDistance >= 2, segmentDistance <= 120 else {
                previous = current
                continue
            }

            cumulative += segmentDistance
            let altitudeDelta = current.location.altitude - previous.location.altitude
            let grade: Double?
            if segmentDistance >= 6, abs(altitudeDelta) <= 35 {
                grade = max(-40, min(40, altitudeDelta / segmentDistance * 100))
                if let grade { grades.append(grade) }
            } else {
                grade = nil
            }

            altitudes.append(current.location.altitude)
            result.append(
                SessionTerrainPoint(
                    distanceMeters: cumulative,
                    altitudeMeters: current.location.altitude,
                    gradePercent: grade
                )
            )
            previous = current
        }

        guard result.count >= 3,
              let minimum = altitudes.min(),
              let maximum = altitudes.max() else { return .unavailable }

        let range = max(0, maximum - minimum)
        let distanceKm = max(0.1, cumulative / 1000)
        let reliefPerKm = range / distanceKm
        let relief: String
        switch reliefPerKm {
        case ..<8: relief = "Plutôt plat"
        case ..<25: relief = "Ondulé"
        case ..<60: relief = "Vallonné"
        default: relief = "Relief marqué"
        }

        let uphill = grades.filter { $0 > 0 }.max()
        let downhill = grades.filter { $0 < 0 }.min()

        return SessionTerrainReport(
            points: downsample(result, maxPoints: 180),
            elevationRangeMeters: range,
            maxUphillGradePercent: uphill,
            maxDownhillGradePercent: downhill,
            reliefLabel: relief,
            surfaceLabel: "Indéterminée sans données cartographiques externes",
            note: "Relief estimé uniquement à partir des points GPS/altitude enregistrés. Le type de surface (route, sentier, gravier) nécessite une source cartographique dédiée pour être fiable."
        )
    }

    private func loadPoints(sessionID: String) -> [RawPoint] {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return [] }

        let directory = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        let urls = [
            directory.appendingPathComponent("samples.jsonl"),
            directory.appendingPathComponent("watch_reliable.jsonl"),
        ]

        var points: [(Date, RawPoint)] = []
        var signatures = Set<String>()

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["record"] as? String == "sample",
                      object["kind"] as? String == "location",
                      let timestamp = object["timestamp"] as? Double,
                      let payload = object["payload"] as? [String: Any],
                      let latitude = payload["latitude"] as? Double,
                      let longitude = payload["longitude"] as? Double,
                      let altitude = payload["altitude_m"] as? Double else { continue }

                let quality = object["quality"] as? [String: Any] ?? [:]
                let horizontal = quality["horizontal_accuracy_m"] as? Double ?? 20
                let vertical = quality["vertical_accuracy_m"] as? Double ?? 20
                guard horizontal >= 0, horizontal <= 35, vertical >= 0, vertical <= 25 else { continue }

                let signature = "\(Int(timestamp.rounded()))|\(String(format: "%.5f", latitude))|\(String(format: "%.5f", longitude))"
                guard signatures.insert(signature).inserted else { continue }

                let location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    altitude: altitude,
                    horizontalAccuracy: horizontal,
                    verticalAccuracy: vertical,
                    timestamp: Date(timeIntervalSince1970: timestamp)
                )
                points.append((location.timestamp, RawPoint(location: location, verticalAccuracy: vertical)))
            }
        }

        return points.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func downsample(_ points: [SessionTerrainPoint], maxPoints: Int) -> [SessionTerrainPoint] {
        guard points.count > maxPoints, maxPoints > 2 else { return points }
        let strideValue = Double(points.count - 1) / Double(maxPoints - 1)
        return (0..<maxPoints).map { index in
            points[min(points.count - 1, Int((Double(index) * strideValue).rounded()))]
        }
    }
}
