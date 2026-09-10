import ActivityKit
import Foundation

struct TrackerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var activity: String
        var phase: String
        var elapsedSeconds: Double
        var referenceDate: Date
        var distanceMeters: Double
        var speedKPH: Double
        var heartRateBPM: Double
        var elevationGainMeters: Double
    }

    var sessionID: String
}
