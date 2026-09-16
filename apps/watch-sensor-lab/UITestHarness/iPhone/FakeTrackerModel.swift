import Combine
import CoreLocation
import Foundation

/// Test-only model compiled into the finish-review UI harness.
/// It deliberately has no HealthKit, WatchConnectivity, CoreMotion, storage,
/// timers, or permissions. The production ActivityExperienceView is compiled
/// unchanged against this deterministic surface.
final class TrackerModel: ObservableObject {
    @Published var isActive = true
    @Published var isPaused = false
    @Published var selectedActivity: ActivityKind = .automatic
    @Published var effectiveActivity: ActivityKind = .walking
    @Published var elapsedSeconds: TimeInterval = 125
    @Published var distanceMeters = 420.0
    @Published var currentSpeedMps = 1.4
    @Published var altitudeMeters = 486.0
    @Published var elevationGainMeters = 12.0
    @Published var elevationLossMeters = 4.0
    @Published var heartRate = 104.0
    @Published var averageHeartRate = 99.0
    @Published var activeEnergyKcal = 18.0
    @Published var cadenceSPM = 108.0
    @Published var steps = 220
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var horizontalAccuracy = 5.0
    @Published var watchReachable = true
    @Published var healthAuthorized = true
    @Published var statusMessage = "Fixture UI · aucun capteur réel"
    @Published var pendingCommand: String?
    @Published var autoPauseEnabled = true
    @Published var finishResult = "none"

    let currentWeather: HarnessWeather? = nil

    var displayActivity: ActivityKind {
        selectedActivity.isAutomatic ? effectiveActivity : selectedActivity
    }

    var gpsSettled: Bool { true }

    var workflowFinishReview: TrackerFinishReviewState {
        TrackerWorkflowPolicy.finishReview(
            selectedActivity: selectedActivity,
            effectiveActivity: effectiveActivity,
            suggestedActivity: .cycling
        )
    }

    func requestLocationPermission() {}

    func workflowSelectActivity(_ activity: ActivityKind) {
        selectedActivity = activity
        effectiveActivity = activity.isAutomatic ? .walking : activity
    }

    func workflowSetAutoPauseEnabled(_ enabled: Bool) {
        autoPauseEnabled = enabled
    }

    func workflowStart() {
        isActive = true
        isPaused = false
    }

    func workflowPause() {
        isPaused = true
    }

    func workflowResume() {
        isPaused = false
    }

    func workflowFinish(
        disposition: TrackerFinishDisposition,
        finalActivity: ActivityKind?
    ) {
        switch disposition {
        case .preserveDetectedSegments:
            finishResult = "preserve"
        case .forceSingleActivity:
            finishResult = "force:\(finalActivity?.rawValue ?? "nil")"
        }
    }
}

struct HarnessWeather {
    let temperatureC: Double?
    let apparentTemperatureC: Double?
    let windSpeedKPH: Double?
    let relativeHumidityPercent: Double?
}
