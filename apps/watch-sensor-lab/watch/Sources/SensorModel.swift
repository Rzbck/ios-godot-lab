import Combine
import CoreMotion
import Foundation
import WatchConnectivity

final class SensorModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var accelX = 0.0
    @Published var accelY = 0.0
    @Published var accelZ = 0.0
    @Published var gyroX = 0.0
    @Published var gyroY = 0.0
    @Published var gyroZ = 0.0
    @Published var running = false
    @Published var sessionStatus = "WatchConnectivity: inactive"

    private let motion = CMMotionManager()
    private var sequence: UInt64 = 0
    private var lastSend = Date.distantPast

    func activateSession() {
        guard WCSession.isSupported() else {
            sessionStatus = "WatchConnectivity: unsupported"
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        sessionStatus = "WatchConnectivity: activating"
    }

    func start() {
        guard !running else { return }
        running = true

        motion.accelerometerUpdateInterval = 1.0 / 20.0
        motion.gyroUpdateInterval = 1.0 / 20.0

        if motion.isAccelerometerAvailable {
            motion.startAccelerometerUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                self.accelX = sample.acceleration.x
                self.accelY = sample.acceleration.y
                self.accelZ = sample.acceleration.z
                self.sendSnapshotIfNeeded()
            }
        }

        if motion.isGyroAvailable {
            motion.startGyroUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                self.gyroX = sample.rotationRate.x
                self.gyroY = sample.rotationRate.y
                self.gyroZ = sample.rotationRate.z
            }
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        running = false
    }

    private func sendSnapshotIfNeeded() {
        let now = Date()
        guard now.timeIntervalSince(lastSend) >= 0.1 else { return }
        lastSend = now
        sequence &+= 1

        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }

        let payload: [String: Any] = [
            "type": "motion",
            "seq": sequence,
            "t": now.timeIntervalSince1970,
            "accel": [accelX, accelY, accelZ],
            "gyro": [gyroX, gyroY, gyroZ],
        ]

        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            if let error {
                self?.sessionStatus = "WatchConnectivity: \(error.localizedDescription)"
            } else {
                self?.sessionStatus = activationState == .activated
                    ? "WatchConnectivity: activated"
                    : "WatchConnectivity: inactive"
            }
        }
    }
}
