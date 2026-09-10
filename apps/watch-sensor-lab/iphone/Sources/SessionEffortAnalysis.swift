import CoreLocation
import Foundation

struct SessionEffortReport: Equatable {
    let averageTemperatureC: Double?
    let averageApparentTemperatureC: Double?
    let averageHumidityPercent: Double?
    let averageWindSpeedKPH: Double?
    let peakWindGustKPH: Double?
    let averageHeadwindComponentKPH: Double?
    let headwindSampleCount: Int
    let note: String?

    static let empty = SessionEffortReport(
        averageTemperatureC: nil,
        averageApparentTemperatureC: nil,
        averageHumidityPercent: nil,
        averageWindSpeedKPH: nil,
        peakWindGustKPH: nil,
        averageHeadwindComponentKPH: nil,
        headwindSampleCount: 0,
        note: nil
    )
}

private struct TimedRoutePoint {
    let timestamp: Date
    let coordinate: CLLocationCoordinate2D
}

/// Derives descriptive environmental context from the session's own weather snapshots and route.
/// This is intentionally not a medical or performance score. It preserves physical context such as
/// temperature and approximate headwind/tailwind so future comparisons don't treat all paces equally.
final class SessionEffortAnalyzer {
    func analyze(summary: TrackerSummary) -> SessionEffortReport {
        guard let weather = summary.weatherSnapshots, !weather.isEmpty else { return .empty }

        let route = loadTimedRoute(sessionID: summary.sessionID)
        let temperatures = weather.compactMap(\.temperatureC)
        let apparent = weather.compactMap(\.apparentTemperatureC)
        let humidity = weather.compactMap(\.relativeHumidityPercent)
        let winds = weather.compactMap(\.windSpeedKPH)
        let gusts = weather.compactMap(\.windGustKPH)

        var headwindComponents: [Double] = []
        if route.count >= 2 {
            for snapshot in weather {
                guard let windSpeed = snapshot.windSpeedKPH,
                      let windFrom = snapshot.windDirectionDegrees,
                      let heading = movementHeading(around: snapshot.timestamp, route: route) else { continue }
                let delta = shortestAngleDegrees(heading - windFrom)
                let component = windSpeed * cos(delta * .pi / 180)
                headwindComponents.append(component)
            }
        }

        let averageHeadwind = mean(headwindComponents)
        return SessionEffortReport(
            averageTemperatureC: mean(temperatures),
            averageApparentTemperatureC: mean(apparent),
            averageHumidityPercent: mean(humidity),
            averageWindSpeedKPH: mean(winds),
            peakWindGustKPH: gusts.max(),
            averageHeadwindComponentKPH: averageHeadwind,
            headwindSampleCount: headwindComponents.count,
            note: makeNote(
                apparentTemperatureC: mean(apparent) ?? mean(temperatures),
                humidityPercent: mean(humidity),
                averageHeadwindKPH: averageHeadwind
            )
        )
    }

    private func loadTimedRoute(sessionID: String) -> [TimedRoutePoint] {
        guard let documents = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return [] }

        let url = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("samples.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var result: [TimedRoutePoint] = []
        result.reserveCapacity(2_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["record"] as? String == "sample",
                  object["kind"] as? String == "location",
                  let timestamp = object["timestamp"] as? Double,
                  let payload = object["payload"] as? [String: Any],
                  let latitude = payload["latitude"] as? Double,
                  let longitude = payload["longitude"] as? Double else { continue }
            result.append(
                TimedRoutePoint(
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
            )
        }
        return result
    }

    private func movementHeading(around date: Date, route: [TimedRoutePoint]) -> Double? {
        guard route.count >= 2 else { return nil }
        var nearestIndex = 0
        var nearestDelta = Double.greatestFiniteMagnitude
        for (index, point) in route.enumerated() {
            let delta = abs(point.timestamp.timeIntervalSince(date))
            if delta < nearestDelta {
                nearestDelta = delta
                nearestIndex = index
            }
        }
        guard nearestDelta <= 15 * 60 else { return nil }

        let beforeIndex = max(0, nearestIndex - 5)
        let afterIndex = min(route.count - 1, nearestIndex + 5)
        guard beforeIndex != afterIndex else { return nil }
        let before = CLLocation(
            latitude: route[beforeIndex].coordinate.latitude,
            longitude: route[beforeIndex].coordinate.longitude
        )
        let after = CLLocation(
            latitude: route[afterIndex].coordinate.latitude,
            longitude: route[afterIndex].coordinate.longitude
        )
        guard after.distance(from: before) >= 8 else { return nil }
        return bearing(from: route[beforeIndex].coordinate, to: route[afterIndex].coordinate)
    }

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private func shortestAngleDegrees(_ value: Double) -> Double {
        var angle = value.truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 }
        if angle < -180 { angle += 360 }
        return angle
    }

    private func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func makeNote(
        apparentTemperatureC: Double?,
        humidityPercent: Double?,
        averageHeadwindKPH: Double?
    ) -> String? {
        var notes: [String] = []

        if let headwind = averageHeadwindKPH {
            if headwind >= 4 {
                notes.append("Vent de face dominant (~\(Int(headwind.rounded())) km/h de composante moyenne sur les snapshots exploitables).")
            } else if headwind <= -4 {
                notes.append("Vent globalement favorable (~\(Int(abs(headwind).rounded())) km/h de composante arrière moyenne).")
            } else {
                notes.append("Composante de vent face/arrière faible ou surtout latérale sur les snapshots exploitables.")
            }
        }

        if let apparent = apparentTemperatureC {
            if apparent >= 30 {
                notes.append("Chaleur marquée : comparer l’allure avec le cardio plutôt que le pace seul.")
            } else if apparent <= 0 {
                notes.append("Froid marqué : l’environnement doit être conservé lors des comparaisons d’effort.")
            }
        }

        if let humidity = humidityPercent, humidity >= 80, (apparentTemperatureC ?? 0) >= 20 {
            notes.append("Humidité élevée associée à une température douce/chaude.")
        }

        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }
}
