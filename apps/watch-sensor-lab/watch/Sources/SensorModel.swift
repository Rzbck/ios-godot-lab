import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity

final class SensorModel: NSObject, ObservableObject {
    static let shared = SensorModel()

    enum Phase: String {
        case ready
        case active
        case paused
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var sessionID = ""
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var currentSpeedMps = 0.0
    @Published private(set) var altitudeMeters = 0.0
    @Published private(set) var elevationGainMeters = 0.0
    @Published private(set) var elevationLossMeters = 0.0
    @Published private(set) var heartRate = 0.0
    @Published private(set) var averageHeartRate = 0.0
    @Published private(set) var activeEnergyKcal = 0.0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var horizontalAccuracy = -1.0
    @Published private(set) var phoneReachable = false
    @Published private(set) var healthAuthorized = false
    @Published private(set) var sessionStatus = "Prêt"

    @Published private(set) var accelX = 0.0
    @Published private(set) var accelY = 0.0
    @Published private(set) var accelZ = 0.0
    @Published private(set) var gyroX = 0.0
    @Published private(set) var gyroY = 0.0
    @Published private(set) var gyroZ = 0.0

    var running: Bool { phase == .active || phase == .paused }
    var isPaused: Bool { phase == .paused }

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var timer: Timer?
    private var previousLocation: CLLocation?
    private var previousAltitudeLocation: CLLocation?
    private var lastStateSend = Date.distantPast
    private var lastMotionSend = Date.distantPast
    private var pendingRemoteSessionID: String?
    private var pendingPhoneConfiguration: HKWorkoutConfiguration?

    private override init() {
        super.init()
        configureLocation()
        activateSession()
        requestHealthAuthorization()
    }

    func activateSession() {
        guard WCSession.isSupported() else {
            sessionStatus = "iPhone non disponible"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        phoneReachable = session.isReachable
    }

    func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else { return }

        let readTypes: Set<HKObjectType> = [heartRateType, energyType, distanceType]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthAuthorized = success
                if let error {
                    self?.sessionStatus = "Santé: \(error.localizedDescription)"
                }
            }
        }
    }

    func start() {
        start(configuration: nil, origin: "watch", sessionID: nil)
    }

    func startFromPhoneConfiguration(_ configuration: HKWorkoutConfiguration) {
        pendingPhoneConfiguration = configuration
        // WatchConnectivity normally delivers the shared session id immediately. Give its
        // application context a short window to arrive before creating the HealthKit session.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.running, let config = self.pendingPhoneConfiguration else { return }
            self.pendingPhoneConfiguration = nil
            self.start(
                configuration: config,
                origin: "iphone",
                sessionID: self.pendingRemoteSessionID
            )
        }
    }

    func start(configuration: HKWorkoutConfiguration?, origin: String, sessionID: String? = nil) {
        guard !running else {
            if self.sessionID.isEmpty, let sessionID { self.sessionID = sessionID }
            return
        }

        let identifier = sessionID ?? pendingRemoteSessionID ?? Self.makeSessionID()
        pendingRemoteSessionID = nil
        pendingPhoneConfiguration = nil

        let config = configuration ?? {
            let value = HKWorkoutConfiguration()
            value.activityType = .running
            value.locationType = .outdoor
            return value
        }()

        guard healthAuthorized else {
            requestHealthAuthorizationAndStart(config, origin: origin, sessionID: identifier)
            return
        }
        startAuthorized(config, origin: origin, sessionID: identifier)
    }

    private func requestHealthAuthorizationAndStart(
        _ configuration: HKWorkoutConfiguration,
        origin: String,
        sessionID: String
    ) {
        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else { return }

        let readTypes: Set<HKObjectType> = [heartRateType, energyType, distanceType]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.healthAuthorized = success
                guard success else {
                    self.sessionStatus = error?.localizedDescription ?? "Autorisation Santé requise"
                    return
                }
                self.startAuthorized(configuration, origin: origin, sessionID: sessionID)
            }
        }
    }

    private func startAuthorized(
        _ configuration: HKWorkoutConfiguration,
        origin: String,
        sessionID: String
    ) {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            workoutBuilder = builder

            self.sessionID = sessionID
            startedAt = Date()
            pausedAt = nil
            pausedDuration = 0
            elapsedSeconds = 0
            distanceMeters = 0
            currentSpeedMps = 0
            altitudeMeters = 0
            elevationGainMeters = 0
            elevationLossMeters = 0
            heartRate = 0
            averageHeartRate = 0
            activeEnergyKcal = 0
            route = []
            currentCoordinate = nil
            previousLocation = nil
            previousAltitudeLocation = nil
            phase = .active
            sessionStatus = origin == "iphone" ? "Démarrée depuis l’iPhone" : "Session en cours"

            requestLocationPermission()
            locationManager.startUpdatingLocation()
            startMotion()
            startClock()

            let date = startedAt ?? Date()
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !success, let error {
                        self.sessionStatus = "Entraînement: \(error.localizedDescription)"
                    }
                }
            }

            session.startMirroringToCompanionDevice { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.sessionStatus = "iPhone + Watch synchronisés"
                    }
                }
            }

            sendState(force: true)
        } catch {
            sessionStatus = "Impossible de démarrer: \(error.localizedDescription)"
            phase = .ready
        }
    }

    func pause() {
        guard phase == .active else { return }
        pauseCore()
        sendControl(command: "pause")
    }

    func resume() {
        guard phase == .paused else { return }
        resumeCore()
        sendControl(command: "resume")
    }

    func stop() {
        guard running else { return }
        sendControl(command: "stop")
        stopCore(status: "Session enregistrée")
    }

    private func pauseCore() {
        guard phase == .active else { return }
        workoutSession?.pause()
        phase = .paused
        pausedAt = Date()
        currentSpeedMps = 0
        locationManager.stopUpdatingLocation()
        sessionStatus = "En pause"
        sendState(force: true)
    }

    private func resumeCore() {
        guard phase == .paused else { return }
        if let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        self.pausedAt = nil
        previousLocation = nil
        previousAltitudeLocation = nil
        workoutSession?.resume()
        phase = .active
        locationManager.startUpdatingLocation()
        sessionStatus = "Session en cours"
        sendState(force: true)
    }

    private func stopCore(status: String) {
        guard running else { return }
        let end = Date()
        if phase == .paused, let pausedAt {
            pausedDuration += end.timeIntervalSince(pausedAt)
        }
        refreshElapsed()

        locationManager.stopUpdatingLocation()
        stopMotion()
        timer?.invalidate()
        timer = nil
        currentSpeedMps = 0
        sendState(force: true, phaseOverride: "ended")

        let builder = workoutBuilder
        workoutSession?.end()
        builder?.endCollection(withEnd: end) { _, _ in
            builder?.finishWorkout { _, _ in }
        }

        workoutSession = nil
        workoutBuilder = nil
        startedAt = nil
        pausedAt = nil
        phase = .ready
        sessionStatus = status
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    private func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshElapsed()
                self?.sendState()
            }
        }
    }

    private func refreshElapsed() {
        guard let startedAt else {
            elapsedSeconds = 0
            return
        }
        let end = pausedAt ?? Date()
        elapsedSeconds = max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    private func startMotion() {
        let interval = 1.0 / 20.0
        motion.accelerometerUpdateInterval = interval
        motion.gyroUpdateInterval = interval

        if motion.isAccelerometerAvailable {
            motion.startAccelerometerUpdates(to: .main) { [weak self] sample, _ in
                guard let self, let sample else { return }
                self.accelX = sample.acceleration.x
                self.accelY = sample.acceleration.y
                self.accelZ = sample.acceleration.z
                self.sendMotionIfNeeded()
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

    private func stopMotion() {
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
    }

    private func accept(location: CLLocation) {
        guard phase == .active else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        horizontalAccuracy = location.horizontalAccuracy
        currentCoordinate = location.coordinate
        altitudeMeters = location.altitude

        if let previous = previousLocation {
            let delta = location.distance(from: previous)
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if delta >= 0.6, delta < 250, dt > 0 {
                distanceMeters += delta
                let rawSpeed = location.speed >= 0 ? location.speed : delta / dt
                if rawSpeed >= 0, rawSpeed < 80 {
                    currentSpeedMps = currentSpeedMps == 0 ? rawSpeed : (currentSpeedMps * 0.7 + rawSpeed * 0.3)
                }
            }
        }

        if location.verticalAccuracy >= 0, location.verticalAccuracy <= 25, let previousAltitudeLocation {
            let delta = location.altitude - previousAltitudeLocation.altitude
            if abs(delta) >= 1.5 {
                if delta > 0 {
                    elevationGainMeters += delta
                } else {
                    elevationLossMeters += abs(delta)
                }
                self.previousAltitudeLocation = location
            }
        } else if previousAltitudeLocation == nil {
            previousAltitudeLocation = location
        }

        if route.isEmpty || location.distance(from: CLLocation(
            latitude: route.last!.latitude,
            longitude: route.last!.longitude
        )) >= 1.5 {
            route.append(location.coordinate)
        }
        previousLocation = location
        sendState()
    }

    private func sendMotionIfNeeded() {
        let now = Date()
        guard running, now.timeIntervalSince(lastMotionSend) >= 0.2 else { return }
        lastMotionSend = now
        let payload: [String: Any] = [
            "type": "sensor_sample",
            "schema": 2,
            "source": "watch",
            "kind": "motion",
            "timestamp": now.timeIntervalSince1970,
            "payload": [
                "accel": [accelX, accelY, accelZ],
                "gyro": [gyroX, gyroY, gyroZ],
            ],
        ]
        sendLive(payload)
    }

    private func sendControl(command: String) {
        let payload: [String: Any] = [
            "type": "tracker_control",
            "command": command,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
        ]
        sendLive(payload)
    }

    private func sendState(force: Bool = false, phaseOverride: String? = nil) {
        guard WCSession.isSupported() else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastStateSend) < 0.75 { return }
        lastStateSend = now

        var payload: [String: Any] = [
            "type": "tracker_state",
            "phase": phaseOverride ?? phase.rawValue,
            "session_id": sessionID,
            "origin": "watch",
            "elapsed_s": elapsedSeconds,
            "distance_m": distanceMeters,
            "speed_mps": currentSpeedMps,
            "altitude_m": altitudeMeters,
            "elevation_gain_m": elevationGainMeters,
            "elevation_loss_m": elevationLossMeters,
            "heart_rate_bpm": heartRate,
            "average_heart_rate_bpm": averageHeartRate,
            "active_energy_kcal": activeEnergyKcal,
            "timestamp": now.timeIntervalSince1970,
        ]
        if let startedAt {
            payload["started_at"] = startedAt.timeIntervalSince1970
        }

        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        sendLive(payload)
    }

    private func sendLive(_ payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    private func handlePhonePayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }

        if type == "tracker_control", let command = payload["command"] as? String {
            applyRemotePhase(command, payload: payload)
            return
        }

        guard type == "tracker_state", let remotePhase = payload["phase"] as? String else { return }
        switch remotePhase {
        case "active":
            if !running {
                let remoteID = payload["session_id"] as? String
                pendingRemoteSessionID = remoteID
                if let pendingPhoneConfiguration {
                    start(configuration: pendingPhoneConfiguration, origin: "iphone", sessionID: remoteID)
                } else {
                    start(configuration: nil, origin: "iphone", sessionID: remoteID)
                }
            } else if phase == .paused {
                resumeCore()
            }
        case "paused":
            if phase == .active { pauseCore() }
        case "ended":
            if running { stopCore(status: "Session terminée depuis l’iPhone") }
        default:
            break
        }
    }

    private func applyRemotePhase(_ command: String, payload: [String: Any]) {
        let remoteID = payload["session_id"] as? String
        switch command {
        case "start":
            pendingRemoteSessionID = remoteID
            if !running {
                if let pendingPhoneConfiguration {
                    start(configuration: pendingPhoneConfiguration, origin: "iphone", sessionID: remoteID)
                } else {
                    start(configuration: nil, origin: "iphone", sessionID: remoteID)
                }
            }
        case "pause":
            if phase == .active { pauseCore() }
        case "resume":
            if phase == .paused { resumeCore() }
        case "stop":
            if running { stopCore(status: "Session terminée depuis l’iPhone") }
        default:
            break
        }
    }

    private static func makeSessionID() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }
}

extension SensorModel: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if toState == .paused { self.phase = .paused }
            if toState == .running { self.phase = .active }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionStatus = "Santé: \(error.localizedDescription)"
        }
    }
}

extension SensorModel: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch quantityType.identifier {
                case HKQuantityTypeIdentifier.heartRate.rawValue:
                    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                    self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? self.heartRate
                    self.averageHeartRate = statistics.averageQuantity()?.doubleValue(for: unit) ?? self.averageHeartRate
                case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                    self.activeEnergyKcal = statistics.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? self.activeEnergyKcal
                case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                    let healthDistance = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                    self.distanceMeters = max(self.distanceMeters, healthDistance)
                default:
                    break
                }
                self.sendState(force: true)
            }
        }
    }
}

extension SensorModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if phase == .active { manager.startUpdatingLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.accept(location: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionStatus = "GPS: \(error.localizedDescription)"
        }
    }
}

extension SensorModel: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.phoneReachable = session.isReachable
            if let error { self?.sessionStatus = "iPhone: \(error.localizedDescription)" }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.phoneReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePhonePayload(message)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handlePhonePayload(applicationContext)
        }
    }
}
