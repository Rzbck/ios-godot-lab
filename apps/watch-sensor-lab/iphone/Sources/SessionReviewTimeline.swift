import Charts
import Foundation
import SwiftUI

struct ActivityReviewRecord: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let sessionID: String
    let detectedActivity: String
    let confirmedActivity: String
    let confirmedAt: Date
    let changedByUser: Bool
    let healthKitSyncState: String

    init(
        sessionID: String,
        detectedActivity: String,
        confirmedActivity: String,
        confirmedAt: Date = Date(),
        healthKitSyncState: String
    ) {
        self.version = Self.currentVersion
        self.sessionID = sessionID
        self.detectedActivity = detectedActivity
        self.confirmedActivity = confirmedActivity
        self.confirmedAt = confirmedAt
        self.changedByUser = detectedActivity != confirmedActivity
        self.healthKitSyncState = healthKitSyncState
    }
}

struct ActivityReviewStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load(sessionID: String) -> ActivityReviewRecord? {
        guard let url = reviewURL(sessionID: sessionID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ActivityReviewRecord.self, from: data)
    }

    func save(_ record: ActivityReviewRecord) throws {
        guard let url = reviewURL(sessionID: record.sessionID, createRoot: true) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    func effectiveActivity(for summary: TrackerSummary) -> String {
        guard
            let review = load(sessionID: summary.sessionID),
            review.healthKitSyncState == "replacement_verified"
        else {
            return summary.activity
        }

        return review.confirmedActivity
    }

    private func reviewURL(sessionID: String, createRoot: Bool = false) -> URL? {
        guard !sessionID.isEmpty,
              let documents = try? FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
              ) else { return nil }

        let sessionDirectory = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)

        if createRoot {
            try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        }
        return sessionDirectory.appendingPathComponent("activity_review.json")
    }
}

struct SessionTimelinePoint: Identifiable, Equatable {
    let bucket: Int64
    let timestamp: Date
    var speedKPH: Double?
    var heartRateBPM: Double?
    var altitudeMeters: Double?
    var cadenceSPM: Double?
    var temperatureC: Double?
    var apparentTemperatureC: Double?
    var humidityPercent: Double?
    var pressureHPA: Double?
    var windSpeedKPH: Double?
    var windGustKPH: Double?
    var windDirectionDegrees: Double?

    var id: Int64 { bucket }
}

final class SessionTimelineLoader {
    private struct BucketValue {
        var timestamp: Date
        var speedKPH: Double?
        var heartRateBPM: Double?
        var altitudeMeters: Double?
        var cadenceSPM: Double?
        var temperatureC: Double?
        var apparentTemperatureC: Double?
        var humidityPercent: Double?
        var pressureHPA: Double?
        var windSpeedKPH: Double?
        var windGustKPH: Double?
        var windDirectionDegrees: Double?
    }

    func load(sessionID: String, bucketSeconds: Double = 5) -> [SessionTimelinePoint] {
        guard !sessionID.isEmpty,
              let documents = try? FileManager.default.url(
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

        var buckets: [Int64: BucketValue] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["record"] as? String == "sample",
                  let timestampValue = object["timestamp"] as? Double,
                  let kind = object["kind"] as? String,
                  let payload = object["payload"] as? [String: Any] else { continue }

            let bucket = Int64(floor(timestampValue / bucketSeconds))
            var value = buckets[bucket] ?? BucketValue(timestamp: Date(timeIntervalSince1970: timestampValue))
            value.timestamp = Date(timeIntervalSince1970: timestampValue)

            switch kind {
            case "watch_location":
                if let speed = payload["speed_mps"] as? Double, speed >= 0 {
                    value.speedKPH = speed * 3.6
                }
                if let altitude = payload["display_altitude_m"] as? Double {
                    value.altitudeMeters = altitude
                } else if let altitude = payload["altitude_m"] as? Double {
                    value.altitudeMeters = altitude
                }

            case "location":
                if value.speedKPH == nil, let speed = payload["speed_mps"] as? Double, speed >= 0 {
                    value.speedKPH = speed * 3.6
                }
                if value.altitudeMeters == nil, let altitude = payload["altitude_m"] as? Double {
                    value.altitudeMeters = altitude
                }

            case "heart_rate":
                if let bpm = payload["bpm"] as? Double, bpm > 0 {
                    value.heartRateBPM = bpm
                }

            case "pedometer":
                if let cadence = payload["cadence_spm"] as? Double, cadence > 0 {
                    value.cadenceSPM = cadence
                }

            case "weather":
                value.temperatureC = payload["temperature_c"] as? Double
                value.apparentTemperatureC = payload["apparent_temperature_c"] as? Double
                value.humidityPercent = payload["relative_humidity_percent"] as? Double
                value.pressureHPA = payload["pressure_hpa"] as? Double
                value.windSpeedKPH = payload["wind_speed_kph"] as? Double
                value.windGustKPH = payload["wind_gust_kph"] as? Double
                value.windDirectionDegrees = payload["wind_direction_degrees"] as? Double

            default:
                break
            }
            buckets[bucket] = value
        }

        return buckets
            .sorted { $0.key < $1.key }
            .map { key, value in
                SessionTimelinePoint(
                    bucket: key,
                    timestamp: value.timestamp,
                    speedKPH: value.speedKPH,
                    heartRateBPM: value.heartRateBPM,
                    altitudeMeters: value.altitudeMeters,
                    cadenceSPM: value.cadenceSPM,
                    temperatureC: value.temperatureC,
                    apparentTemperatureC: value.apparentTemperatureC,
                    humidityPercent: value.humidityPercent,
                    pressureHPA: value.pressureHPA,
                    windSpeedKPH: value.windSpeedKPH,
                    windGustKPH: value.windGustKPH,
                    windDirectionDegrees: value.windDirectionDegrees
                )
            }
    }
}

/// Read-only historical activity summary.
///
/// The former picker triggered a second, Watch-side HealthKit mutation path.
/// Historical HealthKit changes now have a single entry point: the iPhone
/// Récupération tab backed by HistoricalHealthKitRepairCoordinator.
struct ActivityReviewCard: View {
    let summary: TrackerSummary
    var requiresConfirmation = false
    var onSaved: ((ActivityReviewRecord) -> Void)?

    @State private var storedReview: ActivityReviewRecord?
    private let reviewStore = ActivityReviewStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("ACTIVITÉ ENREGISTRÉE", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let storedReview,
                   storedReview.healthKitSyncState == "replacement_verified" {
                    Text("ANCIENNE VALIDATION")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.orange)
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracker raw")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(activityLabelForReview(summary.activity))
                        .font(.headline.weight(.bold))
                }
                Spacer()
                Image(systemName: activitySymbolForReview(summary.activity))
                    .font(.title2)
                    .foregroundStyle(.mint)
            }

            Text("Toute correction ou reconstruction Santé se fait désormais uniquement dans l’onglet Récupération de l’iPhone. Ce panneau ne modifie plus HealthKit.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if requiresConfirmation {
                Label("Pour corriger le sport, ouvre Récupération.", systemImage: "iphone.and.arrow.forward")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear {
            let existing = reviewStore.load(sessionID: summary.sessionID)
            storedReview = existing
            if let existing { onSaved?(existing) }
        }
    }
}

struct SessionTimelineView: View {
    let points: [SessionTimelinePoint]

    var body: some View {
        if points.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Text("PROGRESSION")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                chartSection(title: "Vitesse", unit: "km/h", symbol: "speedometer") {
                    Chart(points) { point in
                        if let value = point.speedKPH {
                            LineMark(x: .value("Temps", point.timestamp), y: .value("Vitesse", value))
                        }
                    }
                }

                chartSection(title: "Fréquence cardiaque", unit: "bpm", symbol: "heart.fill") {
                    Chart(points) { point in
                        if let value = point.heartRateBPM {
                            LineMark(x: .value("Temps", point.timestamp), y: .value("FC", value))
                        }
                    }
                }

                chartSection(title: "Altitude", unit: "m", symbol: "mountain.2.fill") {
                    Chart(points) { point in
                        if let value = point.altitudeMeters {
                            LineMark(x: .value("Temps", point.timestamp), y: .value("Altitude", value))
                        }
                    }
                }

                chartSection(title: "Cadence", unit: "pas/min", symbol: "metronome.fill") {
                    Chart(points) { point in
                        if let value = point.cadenceSPM {
                            LineMark(x: .value("Temps", point.timestamp), y: .value("Cadence", value))
                        }
                    }
                }

                if points.contains(where: { $0.temperatureC != nil || $0.apparentTemperatureC != nil }) {
                    chartSection(title: "Température", unit: "°C", symbol: "thermometer.medium") {
                        Chart(points) { point in
                            if let value = point.temperatureC {
                                LineMark(x: .value("Temps", point.timestamp), y: .value("Température", value))
                                    .foregroundStyle(by: .value("Série", "Température"))
                            }
                            if let value = point.apparentTemperatureC {
                                LineMark(x: .value("Temps", point.timestamp), y: .value("Ressenti", value))
                                    .foregroundStyle(by: .value("Série", "Ressenti"))
                            }
                        }
                    }
                }

                if points.contains(where: { $0.windSpeedKPH != nil || $0.windGustKPH != nil }) {
                    chartSection(title: "Vent", unit: "km/h", symbol: "wind") {
                        Chart(points) { point in
                            if let value = point.windSpeedKPH {
                                LineMark(x: .value("Temps", point.timestamp), y: .value("Vent", value))
                                    .foregroundStyle(by: .value("Série", "Vent"))
                            }
                            if let value = point.windGustKPH {
                                PointMark(x: .value("Temps", point.timestamp), y: .value("Rafales", value))
                                    .foregroundStyle(by: .value("Série", "Rafales"))
                            }
                        }
                    }
                }

                if points.contains(where: { $0.humidityPercent != nil || $0.pressureHPA != nil }) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ATMOSPHÈRE")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            if let humidity = points.compactMap(\.humidityPercent).last {
                                timelineValue(label: "Humidité", value: String(format: "%.0f %%", humidity))
                            }
                            if let pressure = points.compactMap(\.pressureHPA).last {
                                timelineValue(label: "Pression", value: String(format: "%.0f hPa", pressure))
                            }
                            if let direction = points.compactMap(\.windDirectionDegrees).last {
                                timelineValue(label: "Vent de", value: compassDirection(direction))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func chartSection<Content: View>(
        title: String,
        unit: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title.uppercased(), systemImage: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            content()
                .frame(height: 130)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
        }
    }

    private func timelineValue(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func compassDirection(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let labels = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let index = Int((normalized + 22.5) / 45.0) % labels.count
        return "\(labels[index]) · \(Int(normalized.rounded()))°"
    }
}

private func activityLabelForReview(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.label ?? (raw == "transition" ? "Transition" : raw)
}

private func activitySymbolForReview(_ raw: String) -> String {
    ActivityKind(rawValue: raw)?.symbol ?? (raw == "transition" ? "arrow.triangle.2.circlepath" : "figure.mixed.cardio")
}
