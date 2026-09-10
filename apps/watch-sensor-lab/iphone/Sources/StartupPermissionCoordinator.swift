import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit

@MainActor
final class StartupPermissionCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var healthRequestFinished = false

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private let pedometer = CMPedometer()
    private var started = false
    private var motionProbeStarted = false

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func start() {
        guard !started else { return }
        started = true
        requestHealthThenLocation()
    }

    private func requestHealthThenLocation() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthRequestFinished = true
            requestLocationThenMotion()
            return
        }

        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read: Self.healthReadTypes()
        ) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.healthRequestFinished = true
                self.requestLocationThenMotion()
            }
        }
    }

    private func requestLocationThenMotion() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            requestMotionProbe()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard started, manager.authorizationStatus != .notDetermined else { return }
        requestMotionProbe()
    }

    private func requestMotionProbe() {
        guard !motionProbeStarted else { return }
        motionProbeStarted = true
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .notDetermined else { return }

        let end = Date()
        let start = end.addingTimeInterval(-60)
        pedometer.queryPedometerData(from: start, to: end) { _, _ in }
    }

    private static func healthReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]

        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .restingHeartRate,
            .heartRateVariabilitySDNN,
            .vo2Max,
            .stepCount,
            .appleExerciseTime,
            .walkingSpeed,
            .walkingStepLength,
            .walkingAsymmetryPercentage,
            .walkingDoubleSupportPercentage,
            .appleWalkingSteadiness,
            .runningSpeed,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation,
            .heartRateRecoveryOneMinute,
            .respiratoryRate,
        ]

        for identifier in quantityIdentifiers {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }

        return types
    }
}
