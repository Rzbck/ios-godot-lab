import CoreLocation
import Foundation

/// Lightweight outdoor-weather context for a workout.
///
/// This intentionally does not depend on WeatherKit so the validated iLoader signing chain does not
/// need a new WeatherKit entitlement yet. The storage model keeps provider provenance so the backend
/// can later be swapped to WeatherKit without changing historical-session semantics.
final class WorkoutWeatherRecorder {
    private(set) var snapshots: [SessionWeatherSnapshot] = []

    private var lastCaptureDate: Date?
    private var lastCaptureLocation: CLLocation?
    private var requestInFlight = false

    private let minimumInterval: TimeInterval = 10 * 60
    private let minimumDistanceMeters = 2_000.0

    func reset() {
        snapshots = []
        lastCaptureDate = nil
        lastCaptureLocation = nil
        requestInFlight = false
    }

    func captureIfNeeded(at location: CLLocation, force: Bool = false, completion: @escaping (SessionWeatherSnapshot?) -> Void) {
        guard !requestInFlight else { completion(nil); return }

        if !force, let lastCaptureDate {
            let elapsed = Date().timeIntervalSince(lastCaptureDate)
            let travelled = lastCaptureLocation?.distance(from: location) ?? 0
            guard elapsed >= minimumInterval || travelled >= minimumDistanceMeters else {
                completion(nil)
                return
            }
        }

        guard let url = Self.makeURL(location: location) else {
            completion(nil)
            return
        }

        requestInFlight = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            let snapshot: SessionWeatherSnapshot?
            if let data,
               let response = try? JSONDecoder().decode(OpenMeteoResponse.self, from: data) {
                snapshot = SessionWeatherSnapshot(
                    timestamp: Date(),
                    provider: "open-meteo",
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    temperatureC: response.current.temperature2m,
                    apparentTemperatureC: response.current.apparentTemperature,
                    relativeHumidityPercent: response.current.relativeHumidity2m,
                    pressureHPA: response.current.surfacePressure ?? response.current.pressureMSL,
                    windSpeedKPH: response.current.windSpeed10m,
                    windDirectionDegrees: response.current.windDirection10m,
                    windGustKPH: response.current.windGusts10m,
                    weatherCode: response.current.weatherCode
                )
            } else {
                snapshot = nil
            }

            DispatchQueue.main.async {
                self.requestInFlight = false
                if let snapshot {
                    self.snapshots.append(snapshot)
                    self.lastCaptureDate = snapshot.timestamp
                    self.lastCaptureLocation = location
                }
                completion(snapshot)
            }
        }.resume()
    }

    private static func makeURL(location: CLLocation) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", location.coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", location.coordinate.longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,pressure_msl,surface_pressure,weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m"
            ),
            URLQueryItem(name: "wind_speed_unit", value: "kmh"),
            URLQueryItem(name: "timezone", value: "UTC"),
        ]
        return components?.url
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature2m: Double?
        let relativeHumidity2m: Double?
        let apparentTemperature: Double?
        let pressureMSL: Double?
        let surfacePressure: Double?
        let weatherCode: Int?
        let windSpeed10m: Double?
        let windDirection10m: Double?
        let windGusts10m: Double?

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case pressureMSL = "pressure_msl"
            case surfacePressure = "surface_pressure"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case windGusts10m = "wind_gusts_10m"
        }
    }
}
