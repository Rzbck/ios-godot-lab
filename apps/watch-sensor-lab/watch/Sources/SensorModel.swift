import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity

final class SensorModel: NSObject, ObservableObject {
    static let shared = SensorModel()

    enum Phase: String { case ready, active, paused }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var selectedActivity: ActivityKind = .automatic
    @Published private(set) var effectiveActivity: ActivityKind = .walking
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
    var displayActivity: ActivityKind { selectedActivity.isAutomatic ? effectiveActivity : selectedActivity }

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()
    private let activityManager = CMMotionActivityManager()
    private let defaults = UserDefaults.standard

    // Development builds deliberately discard the Health workout when finished.
    private let saveWorkoutToHealth = false

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
    private var authorityRevision: Int64 = 0
    private var selectionRevision: Int64 = 0
    private var lastEndedSessionID = ""
    private var lastPurgeID = ""
    private var autoCandidate: ActivityKind?
    private var autoCandidateToken = UUID()

    private override init() {
        super.init()
        lastPurgeID = defaults.string(forKey: "tracker.lastPurgeID") ?? ""
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

    func selectActivity(_ activity: ActivityKind) {
        guard !running else { return }
        selectedActivity = activity
        effectiveActivity = activity.isAutomatic ? .walking : activity
        selectionRevision = Self.revisionNow()
        sessionStatus = activity.isAutomatic ? "Auto · marche/course/vélo" : activity.label
        sendWC(makeMessage(kind: .selection))
    }

    func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var readTypes = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { readTypes.insert(type) }
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthAuthorized = success
                if let error { self?.sessionStatus = "Santé: \(error.localizedDescription)" }
            }
        }
    }

    func start() {
        guard !running else { return }
        authorityRevision = max(1, authorityRevision + 1)
        lastEndedSessionID = ""
        start(configuration: nil, origin: "watch", sessionID: nil)
    }

    func startFromPhoneConfiguration(_ configuration: HKWorkoutConfiguration) {
        guard !running else { return }
        pendingPhoneConfiguration = configuration
        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: configuration.activityType) {
            selectedActivity = activity
            effectiveActivity = activity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.running, let config = self.pendingPhoneConfiguration else { return }
            self.pendingPhoneConfiguration = nil
            self.authorityRevision = max(1, self.authorityRevision + 1)
            self.start(configuration: config, origin: "iphone", sessionID: self.pendingRemoteSessionID)
        }
    }

    private func start(configuration: HKWorkoutConfiguration?, origin: String, sessionID: String?) {
        guard !running else { return }
        let identifier = sessionID ?? pendingRemoteSessionID ?? Self.makeSessionID()
        pendingRemoteSessionID = nil
        pendingPhoneConfiguration = nil

        let config = configuration ?? {
            let value = HKWorkoutConfiguration()
            value.activityType = selectedActivity.healthKitType
            value.locationType = .outdoor
            return value
        }()

        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: config.activityType) {
            selectedActivity = activity
            effectiveActivity = activity
        }

        guard healthAuthorized else {
            requestHealthAuthorizationAndStart(config, origin: origin, sessionID: identifier)
            return
        }
        startAuthorized(config, origin: origin, sessionID: identifier)
    }

    private func requestHealthAuthorizationAndStart(_ configuration: HKWorkoutConfiguration, origin: String, sessionID: String) {
        var readTypes = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { readTypes.insert(type) }
        }
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

    private func startAuthorized(_ configuration: HKWorkoutConfiguration, origin: String, sessionID: String) {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            workoutBuilder = builder

            self.sessionID = sessionID
            startedAt = Date()
            pausedAt = nil
            pausedDuration = 0
            resetPresentationData(keepActivity: true)
            phase = .active
            if selectedActivity.isAutomatic { effectiveActivity = .walking }
            authorityRevision = max(authorityRevision, 1)
            sessionStatus = selectedActivity.isAutomatic ? "Auto · analyse en cours" : "\(selectedActivity.label) en cours"

            requestLocationPermission()
            locationManager.startUpdatingLocation()
            startMotion()
            startAutomaticClassifierIfNeeded()
            startClock()

            let date = startedAt ?? Date()
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !success, let error { self.sessionStatus = "Entraînement: \(error.localizedDescription)" }
                }
            }

            session.startMirroringToCompanionDevice { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.sessionStatus = success ? "iPhone + Watch synchronisés" : "Miroir iPhone: \(error?.localizedDescription ?? "indisponible")"
                    self.sendAuthority(force: true)
                }
            }
            sendAuthority(force: true)
        } catch {
            sessionStatus = "Impossible de démarrer: \(error.localizedDescription)"
            phase = .ready
        }
    }

    func pause() {
        guard phase == .active else { return }
        authorityRevision += 1
        pauseCore()
        sendAuthority(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        authorityRevision += 1
        resumeCore()
        sendAuthority(force: true)
    }

    func stop() {
        guard running else { return }
        authorityRevision += 1
        stopCore(status: "Session terminée")
    }

    func deleteAllTestData() {
        guard !running else {
            sessionStatus = "Termine la session avant d’effacer"
            return
        }
        let purgeID = UUID().uuidString
        applyPurge(purgeID)
        var message = makeMessage(kind: .purge)
        message.purgeID = purgeID
        sendWC(message)
    }

    private func pauseCore() {
        guard phase == .active else { return }
        phase = .paused
        pausedAt = Date()
        currentSpeedMps = 0
        locationManager.stopUpdatingLocation()
        workoutSession?.pause()
        sessionStatus = "En pause · Watch autoritaire"
    }

    private func resumeCore() {
        guard phase == .paused else { return }
        if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
        self.pausedAt = nil
        previousLocation = nil
        previousAltitudeLocation = nil
        phase = .active
        workoutSession?.resume()
        locationManager.startUpdatingLocation()
        sessionStatus = selectedActivity.isAutomatic ? "Auto · \(effectiveActivity.label)" : "\(selectedActivity.label) en cours"
    }

    private func stopCore(status: String) {
        guard running else { return }
        let end = Date()
        if phase == .paused, let pausedAt { pausedDuration += end.timeIntervalSince(pausedAt) }
        refreshElapsed()
        locationManager.stopUpdatingLocation()
        stopMotion()
        stopAutomaticClassifier()
        timer?.invalidate()
        timer = nil
        currentSpeedMps = 0
        lastEndedSessionID = sessionID

        sendAuthority(force: true, phaseOverride: "ended")

        let builder = workoutBuilder
        workoutSession?.end()
        if saveWorkoutToHealth {
            builder?.endCollection(withEnd: end) { _, _ in builder?.finishWorkout { _, _ in } }
        } else {
            builder?.discardWorkout()
        }
        workoutSession = nil
        workoutBuilder = nil
        startedAt = nil
        pausedAt = nil
        phase = .ready
        sessionStatus = saveWorkoutToHealth ? status : "\(status) · Santé non modifiée"
    }

    private func resetPresentationData(keepActivity: Bool) {
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
        horizontalAccuracy = -1
        previousLocation = nil
        previousAltitudeLocation = nil
        accelX = 0
        accelY = 0
        accelZ = 0
        gyroX = 0
        gyroY = 0
        gyroZ = 0
        autoCandidate = nil
        if !keepActivity {
            selectedActivity = .automatic
            effectiveActivity = .walking
        }
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        locationManager.pausesLocationUpdatesAutomatically = false
    }

    private func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshElapsed()
                self?.sendAuthority()
            }
        }
    }

    private func refreshElapsed() {
        guard let startedAt else { elapsedSeconds = 0; return }
        let end = pausedAt ?? Date()
        elapsedSeconds = max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    private func startAutomaticClassifierIfNeeded() {
        guard selectedActivity.isAutomatic, CMMotionActivityManager.isActivityAvailable() else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity, self.running, self.selectedActivity.isAutomatic else { return }
            guard activity.confidence != .low else { return }
            let candidate: ActivityKind?
            if activity.running { candidate = .running }
            else if activity.cycling { candidate = .cycling }
            else if activity.walking { candidate = .walking }
            else { candidate = nil }
            guard let candidate else { return }
            self.stageAutomaticCandidate(candidate)
        }
    }

    private func stageAutomaticCandidate(_ candidate: ActivityKind) {
        guard candidate != effectiveActivity else {
            autoCandidate = nil
            return
        }
        if autoCandidate != candidate {
            autoCandidate = candidate
            autoCandidateToken = UUID()
            let token = autoCandidateToken
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self, self.running, self.phase == .active, self.selectedActivity.isAutomatic,
                      self.autoCandidate == candidate, self.autoCandidateToken == token else { return }
                self.effectiveActivity = candidate
                self.autoCandidate = nil
                self.authorityRevision += 1
                self.sessionStatus = "Auto · \(candidate.label) détectée"
                self.sendAuthority(force: true)
            }
        }
    }

    private func stopAutomaticClassifier() {
        activityManager.stopActivityUpdates()
        autoCandidate = nil
        autoCandidateToken = UUID()
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
                    currentSpeedMps = currentSpeedMps == 0 ? rawSpeed : currentSpeedMps * 0.7 + rawSpeed * 0.3
                }
            }
        }

        if location.verticalAccuracy >= 0, location.verticalAccuracy <= 25, let previousAltitudeLocation {
            let delta = location.altitude - previousAltitudeLocation.altitude
            if abs(delta) >= 1.5 {
                if delta > 0 { elevationGainMeters += delta } else { elevationLossMeters += abs(delta) }
                self.previousAltitudeLocation = location
            }
        } else if previousAltitudeLocation == nil {
            previousAltitudeLocation = location
        }

        if route.isEmpty || location.distance(from: CLLocation(latitude: route.last!.latitude, longitude: route.last!.longitude)) >= 1.5 {
            route.append(location.coordinate)
        }
        previousLocation = location
        sendAuthority()
    }

    private func sendMotionIfNeeded() {
        let now = Date()
        guard running, now.timeIntervalSince(lastMotionSend) >= 0.2 else { return }
        lastMotionSend = now
        let payload: [String: Any] = [
            "type": "sensor_sample",
            "source": "watch",
            "kind": "motion",
            "timestamp": now.timeIntervalSince1970,
            "payload": [
                "accel": [accelX, accelY, accelZ],
                "gyro": [gyroX, gyroY, gyroZ],
                "selected_activity": selectedActivity.rawValue,
                "effective_activity": effectiveActivity.rawValue,
            ],
        ]
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }

    private func makeMessage(kind: TrackerWireMessage.Kind) -> TrackerWireMessage {
        TrackerWireMessage(
            kind: kind,
            command: nil,
            sessionID: sessionID,
            revision: authorityRevision,
            selectionRevision: selectionRevision,
            selectedActivity: selectedActivity.rawValue,
            effectiveActivity: effectiveActivity.rawValue,
            phase: running ? phase.rawValue : "ready",
            purgeID: lastPurgeID,
            timestamp: Date().timeIntervalSince1970,
            startedAt: startedAt?.timeIntervalSince1970,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            speedMps: currentSpeedMps,
            altitudeMeters: altitudeMeters,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            heartRateBPM: heartRate,
            averageHeartRateBPM: averageHeartRate,
            activeEnergyKcal: activeEnergyKcal
        )
    }

    private func sendAuthority(force: Bool = false, phaseOverride: String? = nil) {
        let now = Date()
        if !force, now.timeIntervalSince(lastStateSend) < 0.75 { return }
        lastStateSend = now
        var message = makeMessage(kind: .authority)
        if let phaseOverride { message.phase = phaseOverride }
        if let data = TrackerWireCodec.encode(message), let workoutSession {
            workoutSession.sendToRemoteWorkoutSession(data: data) { _, _ in }
        }
        sendWC(message)
    }

    private func sendWC(_ message: TrackerWireMessage) {
        guard WCSession.isSupported(), let data = TrackerWireCodec.encode(message) else { return }
        let payload: [String: Any] = ["type": "tracker_wire_v3", "data": data]
        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleWire(_ message: TrackerWireMessage) {
        applyPurgeIfNeeded(message.purgeID)
        switch message.kind {
        case .request:
            handleRequest(message)
        case .selection:
            guard !running, message.selectionRevision >= selectionRevision else { return }
            selectionRevision = message.selectionRevision
            if let value = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = value }
            effectiveActivity = selectedActivity.isAutomatic ? .walking : selectedActivity
            sessionStatus = selectedActivity.isAutomatic ? "Auto synchronisé" : "\(selectedActivity.label) synchronisée"
            sendWC(makeMessage(kind: .selection))
        case .purge:
            applyPurgeIfNeeded(message.purgeID)
        case .authority:
            break
        }
    }

    private func handleRequest(_ message: TrackerWireMessage) {
        guard let command = message.command else { return }
        if command == "start" {
            guard !running else { sendAuthority(force: true); return }
            selectionRevision = max(selectionRevision, message.selectionRevision)
            if let value = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = value }
            effectiveActivity = selectedActivity.isAutomatic ? .walking : selectedActivity
            pendingRemoteSessionID = message.sessionID
            authorityRevision = max(1, authorityRevision + 1)
            if let config = pendingPhoneConfiguration {
                pendingPhoneConfiguration = nil
                start(configuration: config, origin: "iphone", sessionID: message.sessionID)
            } else {
                start(configuration: nil, origin: "iphone", sessionID: message.sessionID)
            }
            return
        }

        guard running, message.sessionID == sessionID else { return }
        switch command {
        case "pause":
            if phase == .active { pause() } else { sendAuthority(force: true) }
        case "resume":
            if phase == .paused { resume() } else { sendAuthority(force: true) }
        case "stop":
            if running { stop() }
        default:
            break
        }
    }

    private func applyPurgeIfNeeded(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID, !running else { return }
        applyPurge(purgeID)
    }

    private func applyPurge(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID else { return }
        lastPurgeID = purgeID
        defaults.set(purgeID, forKey: "tracker.lastPurgeID")
        resetPresentationData(keepActivity: true)
        sessionID = ""
        lastEndedSessionID = ""
        authorityRevision = 0
        sessionStatus = "Données de test effacées sur les deux appareils"
    }

    private static func makeSessionID() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }
    private static func revisionNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension SensorModel: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if toState == .paused, self.phase == .active {
                self.phase = .paused
                self.authorityRevision += 1
                self.sendAuthority(force: true)
            } else if toState == .running, self.phase == .paused {
                self.phase = .active
                self.authorityRevision += 1
                self.sendAuthority(force: true)
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.sessionStatus = "Santé: \(error.localizedDescription)" }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for packet in data {
            guard let message = TrackerWireCodec.decode(packet) else { continue }
            DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
        }
    }
}

extension SensorModel: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
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
                case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                     HKQuantityTypeIdentifier.distanceCycling.rawValue,
                     HKQuantityTypeIdentifier.distanceSwimming.rawValue:
                    let healthDistance = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                    self.distanceMeters = max(self.distanceMeters, healthDistance)
                default:
                    break
                }
                self.sendAuthority(force: true)
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
        DispatchQueue.main.async { [weak self] in self?.accept(location: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.sessionStatus = "GPS: \(error.localizedDescription)" }
    }
}

extension SensorModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.phoneReachable = session.isReachable
            if let error { self?.sessionStatus = "iPhone: \(error.localizedDescription)" }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.phoneReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }

    private func receiveWC(_ payload: [String: Any]) {
        guard payload["type"] as? String == "tracker_wire_v3",
              let data = payload["data"] as? Data,
              let message = TrackerWireCodec.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
    }
}
