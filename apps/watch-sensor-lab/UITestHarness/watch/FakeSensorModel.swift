import Combine
import CoreLocation
import Foundation

/// Test-only watch model used by the UI harness. It matches the surface read by
/// WatchActiveWorkoutView but never creates an HKWorkoutSession or touches a
/// physical sensor. The production watch UI file is compiled unchanged.
final class SensorModel: ObservableObject {
    @Published var isPaused = false
    @Published var autoPaused = false
    @Published var selectedActivity: ActivityKind = .automatic
    @Published var effectiveActivity: ActivityKind = .walking
    @Published var multisportTransition = false
    @Published var phoneReachable = true
    @Published var elapsedSeconds: TimeInterval = 125
    @Published var distanceMeters = 420.0
    @Published var heartRate = 104.0
    @Published var averageHeartRate = 99.0
    @Published var activeEnergyKcal = 18.0
    @Published var cadenceSPM = 108.0
    @Published var steps = 220
    @Published var elevationGainMeters = 12.0
    @Published var elevationLossMeters = 4.0
    @Published var altitudeMeters = 486.0
    @Published var horizontalAccuracy = 5.0
    @Published var currentSpeedMps = 1.4
    @Published var route: [CLLocationCoordinate2D] = []
    @Published var currentCoordinate: CLLocationCoordinate2D?
    @Published var finishResult = "none"

    var displayActivity: ActivityKind {
        selectedActivity.isAutomatic ? effectiveActivity : selectedActivity
    }

    var canAdvanceTriathlon: Bool { false }

    var workflowFinishReview: TrackerFinishReviewState {
        TrackerWorkflowPolicy.finishReview(
            selectedActivity: selectedActivity,
            effectiveActivity: effectiveActivity,
            suggestedActivity: .cycling
        )
    }

    func advanceTriathlon() {}

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
