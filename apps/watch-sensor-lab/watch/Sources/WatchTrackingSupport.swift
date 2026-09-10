import CoreLocation
import CoreMotion
import Foundation

extension ActivityKind {
    /// Hard plausibility ceiling used only to reject impossible GPS spikes.
    /// It is intentionally generous so it does not clip real athletic performance.
    var plausibleMaxSpeedMps: Double {
        switch self {
        case .walking: return 3.6          // 13.0 km/h
        case .hiking: return 3.3           // 11.9 km/h
        case .running, .trackAndField: return 12.5 // 45 km/h
        case .cycling, .handCycling: return 28.0   // 100.8 km/h
        case .crossCountrySkiing, .downhillSkiing, .snowSports, .snowboarding, .skatingSports: return 35.0
        case .swimming, .waterFitness, .waterPolo: return 4.0
        case .automatic: return 28.0
        default: return 20.0
        }
    }

    var autoPauseDelay: TimeInterval {
        switch self {
        case .cycling, .handCycling: return 8
        case .running, .walking, .hiking: return 12
        default: return 15
        }
    }
}

struct WatchMotionFrame {
    let accelX: Double
    let accelY: Double
    let accelZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let gyroSource: String
}

/// Keeps exactly one CMMotionManager and prefers bias-corrected device-motion rotation rate.
/// Raw gyro remains a fallback for hardware/OS combinations where device motion isn't available.
final class WatchMotionSampler {
    private let manager = CMMotionManager()
    private var latestAccel = (x: 0.0, y: 0.0, z: 0.0)
    private var latestGyro = (x: 0.0, y: 0.0, z: 0.0)
    private var gyroSource = "unavailable"

    var isGyroAvailable: Bool { manager.isGyroAvailable || manager.isDeviceMotionAvailable }

    func start(handler: @escaping (WatchMotionFrame) -> Void) {
        stop()
        let interval = 1.0 / 20.0
        manager.accelerometerUpdateInterval = interval
        manager.gyroUpdateInterval = interval
        manager.deviceMotionUpdateInterval = interval

        if manager.isDeviceMotionAvailable {
            gyroSource = "device_motion"
            manager.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                let rotation = sample.rotationRate
                self.latestGyro = (rotation.x, rotation.y, rotation.z)
            }
        } else if manager.isGyroAvailable {
            gyroSource = "raw_gyro"
            manager.startGyroUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                let rotation = sample.rotationRate
                self.latestGyro = (rotation.x, rotation.y, rotation.z)
            }
        }

        if manager.isAccelerometerAvailable {
            manager.startAccelerometerUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                self.latestAccel = (sample.acceleration.x, sample.acceleration.y, sample.acceleration.z)
                handler(
                    WatchMotionFrame(
                        accelX: self.latestAccel.x,
                        accelY: self.latestAccel.y,
                        accelZ: self.latestAccel.z,
                        gyroX: self.latestGyro.x,
                        gyroY: self.latestGyro.y,
                        gyroZ: self.latestGyro.z,
                        gyroSource: self.gyroSource
                    )
                )
            }
        }
    }

    func stop() {
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        manager.stopDeviceMotionUpdates()
        latestAccel = (0, 0, 0)
        latestGyro = (0, 0, 0)
        gyroSource = "unavailable"
    }
}

/// Barometer/altimeter source for stable ascent/descent. GPS altitude stays as fallback/current
/// coordinate context, but cumulative elevation should prefer this filtered relative-altitude stream.
final class WatchAltitudeSampler {
    private let altimeter = CMAltimeter()
    private var filteredRelativeAltitude: Double?
    private var lastFilteredRelativeAltitude: Double?

    var onRelativeDelta: ((Double) -> Void)?
    var onAbsoluteAltitude: ((Double, Double) -> Void)?

    func start() {
        stop()

        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                let raw = data.relativeAltitude.doubleValue
                let filtered = self.filteredRelativeAltitude.map { $0 * 0.82 + raw * 0.18 } ?? raw
                self.filteredRelativeAltitude = filtered

                if let previous = self.lastFilteredRelativeAltitude {
                    let delta = filtered - previous
                    if abs(delta) >= 0.30 {
                        self.onRelativeDelta?(delta)
                        self.lastFilteredRelativeAltitude = filtered
                    }
                } else {
                    self.lastFilteredRelativeAltitude = filtered
                }
            }
        }

        if CMAltimeter.isAbsoluteAltitudeAvailable() {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard self != nil, let data else { return }
                self?.onAbsoluteAltitude?(data.altitude, data.accuracy)
            }
        }
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        filteredRelativeAltitude = nil
        lastFilteredRelativeAltitude = nil
    }
}
