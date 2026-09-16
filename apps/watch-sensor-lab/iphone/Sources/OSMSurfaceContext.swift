import Combine
import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct OSMCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct OSMSurfaceMatch: Codable, Equatable {
    let wayID: Int64
    let timestamp: Date
    let surface: String?
    let highway: String
    let tracktype: String?
    let smoothness: String?
    let name: String?
    let distanceToWayMeters: Double
    let confidence: Double

    var surfaceKey: String {
        guard let surface, !surface.isEmpty else { return "unknown" }
        return surface.lowercased()
    }

    var surfaceLabel: String { OSMSurfaceVocabulary.surfaceLabel(surfaceKey) }
    var highwayLabel: String { OSMSurfaceVocabulary.highwayLabel(highway) }
}

struct OSMSurfaceSegment: Codable, Equatable, Identifiable {
    let id: String
    var wayID: Int64?
    var surface: String?
    var highway: String?
    var tracktype: String?
    var smoothness: String?
    var name: String?
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var confidenceSum: Double
    var confidenceSamples: Int
    var coordinates: [OSMCoordinate]

    var surfaceKey: String {
        guard let surface, !surface.isEmpty else { return "unknown" }
        return surface.lowercased()
    }

    var averageConfidence: Double {
        guard confidenceSamples > 0 else { return 0 }
        return confidenceSum / Double(confidenceSamples)
    }

    var mapCoordinates: [CLLocationCoordinate2D] { coordinates.map(\.coordinate) }
}

struct OSMContextBreakdown: Identifiable, Equatable {
    let key: String
    let label: String
    let distanceMeters: Double
    var id: String { key }
}

struct OSMRouteContextSnapshot: Codable, Equatable {
    let sessionID: String
    let provider: String
    let attribution: String
    let generatedAt: Date
    let segments: [OSMSurfaceSegment]

    var totalDistanceMeters: Double {
        segments.reduce(0) { $0 + max(0, $1.distanceMeters) }
    }

    var knownSurfaceDistanceMeters: Double {
        segments.reduce(0) { partial, segment in
            segment.surfaceKey == "unknown" ? partial : partial + max(0, segment.distanceMeters)
        }
    }

    var surfaceBreakdown: [OSMContextBreakdown] {
        var totals: [String: Double] = [:]
        for segment in segments {
            totals[segment.surfaceKey, default: 0] += max(0, segment.distanceMeters)
        }
        return totals.map {
            OSMContextBreakdown(
                key: $0.key,
                label: OSMSurfaceVocabulary.surfaceLabel($0.key),
                distanceMeters: $0.value
            )
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }

    var highwayBreakdown: [OSMContextBreakdown] {
        var totals: [String: Double] = [:]
        for segment in segments {
            let key = segment.highway?.lowercased() ?? "unknown"
            totals[key, default: 0] += max(0, segment.distanceMeters)
        }
        return totals.map {
            OSMContextBreakdown(
                key: $0.key,
                label: OSMSurfaceVocabulary.highwayLabel($0.key),
                distanceMeters: $0.value
            )
        }
        .sorted { $0.distanceMeters > $1.distanceMeters }
    }
}

enum OSMSurfacePreferences {
    static let enabledKey = "tracker.osmSurface.enabled"

    static var enabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: enabledKey) == nil { return true }
        return defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }
}

enum OSMSurfaceVocabulary {
    static func surfaceLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "asphalt": return "Bitume"
        case "concrete", "concrete:plates", "concrete:lanes": return "Béton"
        case "paving_stones": return "Pavés"
        case "sett", "cobblestone": return "Pavés irréguliers"
        case "compacted": return "Compacté"
        case "fine_gravel": return "Gravier fin"
        case "gravel", "pebblestone": return "Gravier"
        case "ground", "earth", "dirt": return "Terre"
        case "grass", "grass_paver": return "Herbe"
        case "sand": return "Sable"
        case "mud": return "Boue"
        case "wood", "woodchips": return "Bois"
        case "metal": return "Métal"
        case "unpaved": return "Non revêtu"
        case "unknown", "": return "Inconnu"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func highwayLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "motorway": return "Autoroute"
        case "trunk": return "Axe principal"
        case "primary": return "Route principale"
        case "secondary": return "Route secondaire"
        case "tertiary": return "Route tertiaire"
        case "residential": return "Rue résidentielle"
        case "service": return "Voie de service"
        case "unclassified": return "Route"
        case "track": return "Piste / chemin"
        case "path": return "Sentier"
        case "footway": return "Chemin piéton"
        case "cycleway": return "Piste cyclable"
        case "bridleway": return "Chemin équestre"
        case "steps": return "Escaliers"
        case "pedestrian": return "Zone piétonne"
        case "living_street": return "Zone de rencontre"
        case "unknown", "": return "Type de voie inconnu"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func color(for surfaceKey: String) -> Color {
        switch surfaceKey.lowercased() {
        case "asphalt", "concrete", "concrete:plates", "concrete:lanes": return .cyan
        case "paving_stones", "sett", "cobblestone": return .blue
        case "compacted", "fine_gravel": return .yellow
        case "gravel", "pebblestone": return .orange
        case "ground", "earth", "dirt", "mud": return .brown
        case "grass", "grass_paver": return .green
        case "sand": return .yellow
        case "wood", "woodchips": return .mint
        default: return .gray
        }
    }
}

enum OSMRouteContextStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load(sessionID: String) -> OSMRouteContextSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(sessionID: sessionID, createDirectory: false)) else { return nil }
        return try? decoder.decode(OSMRouteContextSnapshot.self, from: data)
    }

    static func write(_ snapshot: OSMRouteContextSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let url = fileURL(sessionID: snapshot.sessionID, createDirectory: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func fileURL(sessionID: String, createDirectory: Bool) -> URL {
        let documents = (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        let directory = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        if createDirectory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("osm_context.json")
    }
}

private struct OSMOverpassResponse: Decodable {
    let elements: [OSMOverpassElement]
}

private struct OSMOverpassElement: Decodable {
    let id: Int64
    let tags: [String: String]?
    let geometry: [OSMOverpassNode]?
}

private struct OSMOverpassNode: Decodable {
    let lat: Double
    let lon: Double
}

private struct OSMWay {
    let id: Int64
    let tags: [String: String]
    let points: [MKMapPoint]
}

private struct OSMCacheEnvelope: Codable {
    let fetchedAt: Date
    let payload: Data
}

private enum OSMOverpassCache {
    private static let lifetime: TimeInterval = 24 * 3600
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func load(key: String) -> Data? {
        guard let data = try? Data(contentsOf: fileURL(key: key)),
              let envelope = try? decoder.decode(OSMCacheEnvelope.self, from: data),
              Date().timeIntervalSince(envelope.fetchedAt) < lifetime else { return nil }
        return envelope.payload
    }

    static func store(_ payload: Data, key: String) {
        let envelope = OSMCacheEnvelope(fetchedAt: Date(), payload: payload)
        guard let data = try? encoder.encode(envelope) else { return }
        let directory = cacheDirectory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(key: key), options: .atomic)
    }

    private static func cacheDirectory() -> URL {
        let root = (try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("OSMSurfaceCache", isDirectory: true)
    }

    private static func fileURL(key: String) -> URL {
        cacheDirectory().appendingPathComponent(key + ".json")
    }
}

final class OSMRouteContextService: ObservableObject {
    static let shared = OSMRouteContextService()

    @Published private(set) var currentMatch: OSMSurfaceMatch?
    @Published private(set) var liveSegments: [OSMSurfaceSegment] = []
    @Published private(set) var networkState = "OSM · en attente du GPS"

    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    private let decoder = JSONDecoder()
    private var sessionID = ""
    private var activity = "walking"
    private var waysByZone: [String: [OSMWay]] = [:]
    private var zoneOrder: [String] = []
    private var requestInFlight = false
    private var lastQueryAt = Date.distantPast
    private var previousLocation: CLLocation?
    private var lastMatchedLocation: CLLocation?
    private var lastMatchAt = Date.distantPast
    private var lastPersistAt = Date.distantPast

    private init() {}

    func begin(sessionID: String, activity: String) {
        guard OSMSurfacePreferences.enabled, !sessionID.isEmpty else { return }
        if self.sessionID == sessionID {
            self.activity = activity
            return
        }
        self.sessionID = sessionID
        self.activity = activity
        currentMatch = nil
        liveSegments = OSMRouteContextStore.load(sessionID: sessionID)?.segments ?? []
        waysByZone = [:]
        zoneOrder = []
        requestInFlight = false
        previousLocation = nil
        lastMatchedLocation = nil
        lastMatchAt = .distantPast
        lastPersistAt = .distantPast
        networkState = "OSM · recherche du revêtement"
    }

    func ingest(
        coordinate: CLLocationCoordinate2D,
        horizontalAccuracy: Double,
        activity: String,
        timestamp: Date = Date()
    ) {
        guard OSMSurfacePreferences.enabled, !sessionID.isEmpty else { return }
        guard horizontalAccuracy >= 0, horizontalAccuracy <= 45 else { return }
        self.activity = activity

        let location = CLLocation(
            coordinate: coordinate,
            altitude: 0,
            horizontalAccuracy: horizontalAccuracy,
            verticalAccuracy: -1,
            timestamp: timestamp
        )

        ensureCoverage(around: location)

        let movedSinceMatch = lastMatchedLocation.map { location.distance(from: $0) } ?? .infinity
        if timestamp.timeIntervalSince(lastMatchAt) >= 3 || movedSinceMatch >= 6 {
            let match = nearestMatch(to: location)
            transitionIfNeeded(to: match, at: location)
            currentMatch = match
            lastMatchedLocation = location
            lastMatchAt = timestamp
        } else if liveSegments.isEmpty {
            transitionIfNeeded(to: currentMatch, at: location)
        }

        if let previousLocation {
            let delta = location.distance(from: previousLocation)
            let dt = location.timestamp.timeIntervalSince(previousLocation.timestamp)
            if dt > 0, dt < 15, delta >= 0.5, delta <= 120 {
                recordDistance(delta, at: location)
            }
        } else {
            appendCoordinateIfNeeded(location.coordinate)
        }
        previousLocation = location

        if timestamp.timeIntervalSince(lastPersistAt) >= 30 {
            persist(generatedAt: timestamp)
        }
    }

    func finish(sessionID: String, endedAt: Date = Date()) {
        guard !sessionID.isEmpty, self.sessionID == sessionID else { return }
        if !liveSegments.isEmpty {
            liveSegments[liveSegments.count - 1].endedAt = endedAt
        }
        persist(generatedAt: endedAt)
        networkState = "OSM · résumé enregistré"
    }

    func currentSnapshot(generatedAt: Date = Date()) -> OSMRouteContextSnapshot? {
        guard !sessionID.isEmpty, !liveSegments.isEmpty else { return nil }
        return OSMRouteContextSnapshot(
            sessionID: sessionID,
            provider: "OpenStreetMap / Overpass",
            attribution: "© OpenStreetMap contributors · ODbL",
            generatedAt: generatedAt,
            segments: liveSegments
        )
    }

    private func persist(generatedAt: Date) {
        guard let snapshot = currentSnapshot(generatedAt: generatedAt) else { return }
        OSMRouteContextStore.write(snapshot)
        lastPersistAt = generatedAt
    }

    private func transitionIfNeeded(to match: OSMSurfaceMatch?, at location: CLLocation) {
        let surface = match?.surface
        let highway = match?.highway
        let tracktype = match?.tracktype
        let smoothness = match?.smoothness

        if let last = liveSegments.last,
           normalized(last.surface) == normalized(surface),
           normalized(last.highway) == normalized(highway),
           normalized(last.tracktype) == normalized(tracktype),
           normalized(last.smoothness) == normalized(smoothness) {
            if let match {
                liveSegments[liveSegments.count - 1].wayID = match.wayID
                liveSegments[liveSegments.count - 1].name = match.name
                liveSegments[liveSegments.count - 1].confidenceSum += match.confidence
                liveSegments[liveSegments.count - 1].confidenceSamples += 1
            }
            appendCoordinateIfNeeded(location.coordinate)
            return
        }

        if !liveSegments.isEmpty {
            liveSegments[liveSegments.count - 1].endedAt = location.timestamp
        }

        liveSegments.append(
            OSMSurfaceSegment(
                id: UUID().uuidString,
                wayID: match?.wayID,
                surface: surface,
                highway: highway,
                tracktype: tracktype,
                smoothness: smoothness,
                name: match?.name,
                startedAt: location.timestamp,
                endedAt: location.timestamp,
                distanceMeters: 0,
                confidenceSum: match?.confidence ?? 0,
                confidenceSamples: match == nil ? 0 : 1,
                coordinates: [OSMCoordinate(location.coordinate)]
            )
        )
    }

    private func recordDistance(_ distance: Double, at location: CLLocation) {
        if liveSegments.isEmpty {
            transitionIfNeeded(to: currentMatch, at: location)
        }
        guard !liveSegments.isEmpty else { return }
        liveSegments[liveSegments.count - 1].distanceMeters += distance
        liveSegments[liveSegments.count - 1].endedAt = location.timestamp
        appendCoordinateIfNeeded(location.coordinate)
    }

    private func appendCoordinateIfNeeded(_ coordinate: CLLocationCoordinate2D) {
        guard !liveSegments.isEmpty else { return }
        let index = liveSegments.count - 1
        if let last = liveSegments[index].coordinates.last {
            let a = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if b.distance(from: a) < 4 { return }
        }
        liveSegments[index].coordinates.append(OSMCoordinate(coordinate))
    }

    private func ensureCoverage(around location: CLLocation) {
        let key = zoneKey(location.coordinate)
        if waysByZone[key] != nil { return }

        if let cached = OSMOverpassCache.load(key: key), let ways = parseWays(cached) {
            install(ways: ways, key: key)
            networkState = ways.isEmpty ? "OSM · aucune voie renseignée ici" : "OSM · données en cache"
            return
        }

        guard !requestInFlight, Date().timeIntervalSince(lastQueryAt) >= 8 else { return }
        requestInFlight = true
        lastQueryAt = Date()
        networkState = "OSM · chargement de la zone…"

        let lat = String(format: "%.6f", location.coordinate.latitude)
        let lon = String(format: "%.6f", location.coordinate.longitude)
        let query = "[out:json][timeout:12];way(around:1000,\(lat),\(lon))[\"highway\"];out tags geom;"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("WatchTracker/0.4 OSM-surface-context (github.com/Rzbck/ios-godot-lab)", forHTTPHeaderField: "User-Agent")
        request.httpBody = "data=\(encoded)".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestInFlight = false
                if let error {
                    self.networkState = "OSM · réseau indisponible"
                    _ = error
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let ways = self.parseWays(data) else {
                    self.networkState = "OSM · réponse indisponible"
                    return
                }
                OSMOverpassCache.store(data, key: key)
                self.install(ways: ways, key: key)
                self.networkState = ways.isEmpty ? "OSM · aucune voie renseignée ici" : "OSM · zone chargée"
                if let location = self.previousLocation {
                    let match = self.nearestMatch(to: location)
                    self.transitionIfNeeded(to: match, at: location)
                    self.currentMatch = match
                }
            }
        }.resume()
    }

    private func install(ways: [OSMWay], key: String) {
        waysByZone[key] = ways
        zoneOrder.removeAll { $0 == key }
        zoneOrder.append(key)
        while zoneOrder.count > 8 {
            let removed = zoneOrder.removeFirst()
            waysByZone.removeValue(forKey: removed)
        }
    }

    private func parseWays(_ data: Data) -> [OSMWay]? {
        guard let response = try? decoder.decode(OSMOverpassResponse.self, from: data) else { return nil }
        return response.elements.compactMap { element in
            guard let geometry = element.geometry, geometry.count >= 2 else { return nil }
            let tags = element.tags ?? [:]
            return OSMWay(
                id: element.id,
                tags: tags,
                points: geometry.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
            )
        }
    }

    private func nearestMatch(to location: CLLocation) -> OSMSurfaceMatch? {
        let allWays = zoneOrder.compactMap { waysByZone[$0] }.flatMap { $0 }
        guard !allWays.isEmpty else { return nil }

        let point = MKMapPoint(location.coordinate)
        let threshold = max(18, min(48, location.horizontalAccuracy * 1.35 + 8))
        var best: (way: OSMWay, distance: Double)?

        for way in allWays {
            var index = 1
            while index < way.points.count {
                let distance = distanceMeters(point: point, a: way.points[index - 1], b: way.points[index], latitude: location.coordinate.latitude)
                if distance <= threshold, distance < (best?.distance ?? .infinity) {
                    best = (way, distance)
                }
                index += 1
            }
        }

        guard let best else { return nil }
        let distanceConfidence = max(0, 1 - best.distance / threshold)
        let accuracyConfidence = max(0.25, min(1, 1 - max(0, location.horizontalAccuracy - 5) / 45))
        let confidence = min(1, max(0, distanceConfidence * 0.72 + accuracyConfidence * 0.28))
        let tags = best.way.tags

        return OSMSurfaceMatch(
            wayID: best.way.id,
            timestamp: location.timestamp,
            surface: tags["surface"],
            highway: tags["highway"] ?? "unknown",
            tracktype: tags["tracktype"],
            smoothness: tags["smoothness"],
            name: tags["name"],
            distanceToWayMeters: best.distance,
            confidence: confidence
        )
    }

    private func distanceMeters(point: MKMapPoint, a: MKMapPoint, b: MKMapPoint, latitude: Double) -> Double {
        let vx = b.x - a.x
        let vy = b.y - a.y
        let wx = point.x - a.x
        let wy = point.y - a.y
        let lengthSquared = vx * vx + vy * vy
        let t = lengthSquared > 0 ? min(1, max(0, (wx * vx + wy * vy) / lengthSquared)) : 0
        let nearestX = a.x + t * vx
        let nearestY = a.y + t * vy
        let mapPointDistance = hypot(point.x - nearestX, point.y - nearestY)
        return mapPointDistance * MKMetersPerMapPointAtLatitude(latitude)
    }

    private func zoneKey(_ coordinate: CLLocationCoordinate2D) -> String {
        let lat = Int(floor(coordinate.latitude * 100))
        let lon = Int(floor(coordinate.longitude * 100))
        return "\(lat)_\(lon)"
    }

    private func normalized(_ value: String?) -> String {
        value?.lowercased() ?? ""
    }
}

struct OSMSurfaceEffortReport: Equatable {
    let contribution: Double
    let knownCoverage: Double
}

struct OSMSurfaceEffortAnalyzer {
    func analyze(summary: TrackerSummary) -> OSMSurfaceEffortReport {
        guard let snapshot = OSMRouteContextStore.load(sessionID: summary.sessionID) else {
            return OSMSurfaceEffortReport(contribution: 0, knownCoverage: 0)
        }

        let knownSegments = snapshot.segments.filter { $0.surfaceKey != "unknown" && $0.distanceMeters > 0 }
        let knownDistance = knownSegments.reduce(0) { $0 + $1.distanceMeters }
        guard knownDistance > 0 else {
            return OSMSurfaceEffortReport(contribution: 0, knownCoverage: 0)
        }

        let referenceDistance = max(1, max(summary.distanceMeters, snapshot.totalDistanceMeters))
        let coverage = min(1, knownDistance / referenceDistance)
        let weightedRoughness = knownSegments.reduce(0.0) { partial, segment in
            partial + roughness(for: segment) * segment.distanceMeters
        } / knownDistance

        let sportFactor: Double
        switch summary.activity {
        case "cycling", "handCycling": sportFactor = 1.05
        case "running": sportFactor = 0.78
        case "hiking": sportFactor = 0.62
        case "walking": sportFactor = 0.48
        default: sportFactor = 0.40
        }

        let contribution = min(0.65, max(0, weightedRoughness * sportFactor * coverage))
        return OSMSurfaceEffortReport(contribution: contribution, knownCoverage: coverage)
    }

    private func roughness(for segment: OSMSurfaceSegment) -> Double {
        var value: Double
        switch segment.surfaceKey {
        case "asphalt", "concrete", "concrete:plates", "concrete:lanes": value = 0
        case "paving_stones": value = 0.12
        case "sett", "cobblestone": value = 0.24
        case "compacted": value = 0.14
        case "fine_gravel": value = 0.20
        case "gravel", "pebblestone": value = 0.34
        case "ground", "earth", "dirt": value = 0.42
        case "grass", "grass_paver", "woodchips": value = 0.34
        case "sand", "mud": value = 0.62
        case "unpaved": value = 0.32
        default: value = 0
        }

        switch segment.smoothness?.lowercased() {
        case "bad": value += 0.08
        case "very_bad": value += 0.14
        case "horrible", "very_horrible", "impassable": value += 0.22
        default: break
        }

        switch segment.tracktype?.lowercased() {
        case "grade2": value += 0.04
        case "grade3": value += 0.08
        case "grade4": value += 0.14
        case "grade5": value += 0.20
        default: break
        }

        return min(0.80, max(0, value))
    }
}

struct OSMLiveSurfaceBar: View {
    @ObservedObject private var service = OSMRouteContextService.shared
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "road.lanes")
                    .foregroundStyle(OSMSurfaceVocabulary.color(for: service.currentMatch?.surfaceKey ?? "unknown"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.currentMatch?.surfaceLabel ?? "Revêtement OSM")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("OSM")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.mint.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            OSMLiveSurfaceDetailView()
        }
    }

    private var detail: String {
        if let match = service.currentMatch {
            return "\(match.highwayLabel) · confiance \(Int((match.confidence * 100).rounded())) %"
        }
        return service.networkState
    }
}

private struct OSMLiveSurfaceDetailView: View {
    @ObservedObject private var service = OSMRouteContextService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                liveMap
                currentCard
                attribution
            }
            .padding()
            .navigationTitle("Revêtement OSM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var liveMap: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            UserAnnotation()
            ForEach(service.liveSegments.filter { $0.mapCoordinates.count > 1 }) { segment in
                MapPolyline(coordinates: segment.mapCoordinates)
                    .stroke(
                        OSMSurfaceVocabulary.color(for: segment.surfaceKey),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(service.currentMatch?.surfaceLabel ?? "Inconnu")
                    .font(.headline.weight(.black))
                Spacer()
                if let confidence = service.currentMatch?.confidence {
                    Text("\(Int((confidence * 100).rounded())) %")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(service.currentMatch?.highwayLabel ?? service.networkState)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let tracktype = service.currentMatch?.tracktype {
                Text("tracktype=\(tracktype)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            if let smoothness = service.currentMatch?.smoothness {
                Text("smoothness=\(smoothness)").font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("© OpenStreetMap contributors · ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.caption2.weight(.semibold))
            Text("Les requêtes de zone sont espacées et mises en cache. Si OSM ne renseigne pas surface=*, Watch Tracker affiche Inconnu et n’invente pas le revêtement.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OSMPostActivitySummaryContainer: View {
    let summary: TrackerSummary
    @State private var snapshot: OSMRouteContextSnapshot?

    var body: some View {
        PostActivitySummaryView(summary: summary)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let snapshot {
                    OSMSummaryCompactBar(snapshot: snapshot)
                }
            }
            .task(id: summary.sessionID) {
                snapshot = OSMRouteContextStore.load(sessionID: summary.sessionID)
            }
    }
}

private struct OSMSummaryCompactBar: View {
    let snapshot: OSMRouteContextSnapshot
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "road.lanes")
                    .foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("REVÊTEMENT · OSM")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(summaryText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            OSMSummaryDetailView(snapshot: snapshot)
        }
    }

    private var summaryText: String {
        guard let top = snapshot.surfaceBreakdown.first else { return "Aucune donnée OSM" }
        let total = max(1, snapshot.totalDistanceMeters)
        return "\(top.label) \(Int((top.distanceMeters / total * 100).rounded())) % · \(Int((snapshot.knownSurfaceDistanceMeters / total * 100).rounded())) % renseigné"
    }
}

private struct OSMSummaryDetailView: View {
    let snapshot: OSMRouteContextSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if snapshot.segments.contains(where: { $0.mapCoordinates.count > 1 }) {
                        summaryMap
                    }
                    breakdown(title: "REVÊTEMENT", values: snapshot.surfaceBreakdown, colored: true)
                    breakdown(title: "TYPE DE VOIE", values: snapshot.highwayBreakdown, colored: false)
                    attribution
                }
                .padding()
            }
            .navigationTitle("Route / revêtement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var summaryMap: some View {
        Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
            ForEach(snapshot.segments.filter { $0.mapCoordinates.count > 1 }) { segment in
                MapPolyline(coordinates: segment.mapCoordinates)
                    .stroke(
                        OSMSurfaceVocabulary.color(for: segment.surfaceKey),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func breakdown(title: String, values: [OSMContextBreakdown], colored: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption.weight(.black)).foregroundStyle(.secondary)
            ForEach(values) { value in
                let total = max(1, snapshot.totalDistanceMeters)
                HStack(spacing: 9) {
                    if colored {
                        Circle()
                            .fill(OSMSurfaceVocabulary.color(for: value.key))
                            .frame(width: 9, height: 9)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value.label).font(.subheadline.weight(.semibold))
                        ProgressView(value: min(1, value.distanceMeters / total))
                            .tint(colored ? OSMSurfaceVocabulary.color(for: value.key) : .mint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.2f km", value.distanceMeters / 1000))
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                        Text("\(Int((value.distanceMeters / total * 100).rounded())) %")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 5) {
            Link(snapshot.attribution, destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                .font(.caption.weight(.semibold))
            Text("Le revêtement est issu des tags OSM surface/highway/tracktype/smoothness avec map-matching local. Une portion sans surface=* reste explicitement inconnue.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
