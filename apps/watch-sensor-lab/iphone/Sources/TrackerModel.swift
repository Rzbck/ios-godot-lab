import Combine
import CoreLocation
import Foundation
import HealthKit
import WatchConnectivity

final class TrackerModel: NSObject, ObservableObject {
    enum Phase: String {
        case ready
        case active
        case paused
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var sessionID = ""
    @Published private(set) var origin = "iphone"
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var currentSpeedMps = 0.0
    @Published private(set) var averageSpeedMps = 0.0
    @Published private(set) var maxSpeedMps = 0.0
    @Published private(set) var altitudeMeters = 0.0
    @Published private(set) var elevationGainMeters = 0.0
    @Published private(set) var elevationLossMeters = 0.0
    @Published private(set) var heartRate = 0.0
    @Published private(set) var averageHeartRate = 0.0
    @Published private(set) var activeEnergyKcal = 0.0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var horizontalAccuracy = -1.0
    @Published private(set) var watchReachable = false
    @Published private(set) var healthAuthorized = false
    @Published private(set) var statusMessage = "Prêt"
    @Published private(set) var lastSummary: TrackerSummary?

    var isActive: Bool { phase == .active || phase == .paused }
    var isPaused: Bool { phase == .paused }

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private let store = NativeSessionStore()

    private var mirroredWorkoutSession: HKWorkoutSession?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var timer: Timer?
    private var previousLocation: CLLocation?
    private var previousAltitudeLocation: CLLocation?
    private var lastStatePush = Date.distantPast
    private var lastHeartRateSample = 0.0
    private var controlRevision: Int64 = 0
    private var lastEndedSessionID = ""

    override init() {
        super.init()
        configureLocation()
        configureHealthMirroring()
        configureWatchConnectivity()
        requestHealthAuthorization()
    }

    func requestLocationPermission() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusMessage = "GPS prêt"
        case .denied, .restricted:
            statusMessage = "Autorisation GPS requise"
        @unknown default:
            break
        }
    }

    func startFromPhone() {
        guard !isActive else { return }
        let identifier = Self.makeSessionID()
        controlRevision = 1
        lastEndedSessionID = ""
        beginLocalSession(sessionID: identifier, origin: "iphone")
        sendControl(command: "start")
        launchWatchWorkout()
    }

    func pauseFromPhone() {
        guard phase == .active else { return }
        controlRevision += 1
        pauseLocalSession()
        sendControl(command: "pause")
    }

    func resumeFromPhone() {
        guard phase == .paused else { return }
        controlRevision += 1
        resumeLocalSession()
        sendControl(command: "resume")
    }

    func stopFromPhone() {
        guard isActive else { return }
        controlRevision += 1
        sendControl(command: "stop")
        finishLocalSession(reason: "iphone")
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
    }

    private func configureHealthMirroring() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            DispatchQueue.main.async {
                guard let self else { return }
                self.mirroredWorkoutSession = mirroredSession
                self.statusMessage = "Session Apple Watch détectée"

                if WCSession.isSupported(), WCSession.default.activationState != .activated {
                    WCSession.default.activate()
                }
            }
        }
    }

    private func configureWatchConnectivity() {
        guard WCSession.isSupported() else {
            statusMessage = "Apple Watch non prise en charge"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        watchReachable = session.isReachable
    }

    private func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
            let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else { return }

        let readTypes: Set<HKObjectType> = [
            heartRateType,
            energyType,
            distanceType,
            HKObjectType.workoutType(),
        ]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthAuthorized = success
                if let error {
                    self?.statusMessage = "Santé: \(error.localizedDescription)"
                }
            }
        }
    }

    private func launchWatchWorkout() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.healthStore.startWatchApp(toHandle: configuration)
                await MainActor.run {
                    self.statusMessage = "Session envoyée à l’Apple Watch"
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "iPhone actif · Watch à ouvrir"
                }
            }
        }
    }

    private func beginLocalSession(sessionID: String, origin: String) {
        guard !isActive else { return }
        requestLocationPermission()

        self.sessionID = sessionID
        self.origin = origin
        startedAt = Date()
        pausedAt = nil
        pausedDuration = 0
        elapsedSeconds = 0
        distanceMeters = 0
        currentSpeedMps = 0
        averageSpeedMps = 0
        maxSpeedMps = 0
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
        lastHeartRateSample = 0
        phase = .active
        statusMessage = origin == "watch" ? "Session démarrée depuis la Watch" : "Session en cours"

        do {
            try store.begin(
                sessionID: sessionID,
                metadata: [
                    "app": "Watch Tracker",
                    "build_sha": BuildInfo.gitSHA,
                    "origin": origin,
                    "platform": "iphone",
                ]
            )
        } catch {
            statusMessage = "Enregistrement local indisponible"
        }

        locationManager.startUpdatingLocation()
        startClock()
        pushStateToWatch(force: true)
    }

    private func pauseLocalSession() {
        guard phase == .active else { return }
        phase = .paused
        pausedAt = Date()
        currentSpeedMps = 0
        locationManager.stopUpdatingLocation()
        statusMessage = "En pause"
        store.appendSample(source: "iphone", kind: "session_control", payload: ["command": "pause"])
        pushStateToWatch(force: true)
    }

    private func resumeLocalSession() {
        guard phase == .paused else { return }
        if let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        self.pausedAt = nil
        phase = .active
        previousLocation = nil
        previousAltitudeLocation = nil
        locationManager.startUpdatingLocation()
        statusMessage = "Session en cours"
        store.appendSample(source: "iphone", kind: "session_control", payload: ["command": "resume"])
        pushStateToWatch(force: true)
    }

    private func finishLocalSession(reason: String) {
        guard isActive, let startedAt else { return }

        if phase == .paused, let pausedAt {
            pausedDuration += Date().timeIntervalSince(pausedAt)
        }
        refreshElapsed()
        let endedAt = Date()
        let summary = TrackerSummary(
            sessionID: sessionID,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: elapsedSeconds,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            maxSpeedMps: maxSpeedMps,
            averageHeartRate: averageHeartRate
        )

        lastEndedSessionID = sessionID
        store.finish(summary: summary)
        lastSummary = summary
        locationManager.stopUpdatingLocation()
        timer?.invalidate()
        timer = nil
        phase = .ready
        currentSpeedMps = 0
        statusMessage = "Session enregistrée"
        pushStateToWatch(force: true, phaseOverride: "ended", stopReason: reason)
        mirroredWorkoutSession = nil
        self.startedAt = nil
        self.pausedAt = nil
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshElapsed()
                self?.pushStateToWatch()
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
        averageSpeedMps = elapsedSeconds > 0 ? distanceMeters / elapsedSeconds : 0
    }

    private func accept(location: CLLocation) {
        guard phase == .active else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 45 else { return }
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
                    currentSpeedMps = currentSpeedMps == 0 ? rawSpeed : (currentSpeedMps * 0.72 + rawSpeed * 0.28)
                    maxSpeedMps = max(maxSpeedMps, currentSpeedMps)
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
        refreshElapsed()
        store.appendSample(
            source: "iphone",
            kind: "location",
            payload: [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude_m": location.altitude,
                "speed_mps": currentSpeedMps,
                "distance_m": distanceMeters,
                "elevation_gain_m": elevationGainMeters,
                "elevation_loss_m": elevationLossMeters,
            ],
            quality: [
                "horizontal_accuracy_m": location.horizontalAccuracy,
                "vertical_accuracy_m": location.verticalAccuracy,
            ]
        )
        pushStateToWatch()
    }

    private func sendControl(command: String) {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            "type": "tracker_control",
            "command": command,
            "session_id": sessionID,
            "control_revision": controlRevision,
            "timestamp": Date().timeIntervalSince1970,
        ]
        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func pushStateToWatch(force: Bool = false, phaseOverride: String? = nil, stopReason: String? = nil) {
        guard WCSession.isSupported() else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastStatePush) < 1.0 { return }
        lastStatePush = now

        var payload: [String: Any] = [
            "type": "tracker_state",
            "phase": phaseOverride ?? phase.rawValue,
            "session_id": sessionID,
            "origin": origin,
            "control_revision": controlRevision,
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
        if let stopReason {
            payload["stop_reason"] = stopReason
        }

        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleWatchPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }

        if type == "sensor_sample" {
            if isActive,
               let source = payload["source"] as? String,
               let kind = payload["kind"] as? String,
               let data = payload["payload"] as? [String: Any] {
                store.appendSample(source: source, kind: kind, payload: data)
            }
            return
        }

        guard type == "tracker_state" || type == "tracker_control" else { return }
        let remoteSessionID = (payload["session_id"] as? String) ?? ""
        let remoteRevision = Self.int64Value(payload["control_revision"]) ?? 0

        if type == "tracker_control", let command = payload["command"] as? String {
            guard acceptRemoteTransition(
                sessionID: remoteSessionID,
                revision: remoteRevision,
                allowNewSession: command == "start"
            ) else { return }
            applyRemoteCommand(command, payload: payload)
            return
        }

        guard let remotePhase = payload["phase"] as? String else { return }
        guard acceptRemoteTransition(
            sessionID: remoteSessionID,
            revision: remoteRevision,
            allowNewSession: remotePhase == "active"
        ) else { return }

        if remotePhase == "active", !isActive {
            beginLocalSession(sessionID: remoteSessionID, origin: "watch")
        } else if remotePhase == "paused", phase == .active {
            pauseLocalSession()
        } else if remotePhase == "active", phase == .paused {
            resumeLocalSession()
        } else if remotePhase == "ended", isActive {
            finishLocalSession(reason: "watch")
        }

        if let value = Self.doubleValue(payload["heart_rate_bpm"]) {
            heartRate = value
            if value > 0, abs(value - lastHeartRateSample) >= 0.1 {
                lastHeartRateSample = value
                store.appendSample(source: "watch", kind: "heart_rate", payload: ["bpm": value])
            }
        }
        if let value = Self.doubleValue(payload["average_heart_rate_bpm"]) { averageHeartRate = value }
        if let value = Self.doubleValue(payload["active_energy_kcal"]) { activeEnergyKcal = value }
    }

    private func acceptRemoteTransition(
        sessionID remoteSessionID: String,
        revision: Int64,
        allowNewSession: Bool
    ) -> Bool {
        guard !remoteSessionID.isEmpty else { return false }
        if remoteSessionID == lastEndedSessionID { return false }

        if remoteSessionID != sessionID {
            guard !isActive, allowNewSession else { return false }
            controlRevision = revision
            return true
        }

        guard revision >= controlRevision else { return false }
        controlRevision = revision
        return true
    }

    private func applyRemoteCommand(_ command: String, payload: [String: Any]) {
        switch command {
        case "start":
            if !isActive {
                beginLocalSession(
                    sessionID: (payload["session_id"] as? String) ?? Self.makeSessionID(),
                    origin: "watch"
                )
            }
        case "pause":
            pauseLocalSession()
        case "resume":
            resumeLocalSession()
        case "stop":
            finishLocalSession(reason: "watch")
        default:
            break
        }
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }

    static func makeSessionID() -> String {
        String(Int(Date().timeIntervalSince1970 * 1000))
    }
}

extension TrackerModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                self.statusMessage = self.isActive ? "GPS actif" : "GPS prêt"
                if self.phase == .active { manager.startUpdatingLocation() }
            case .denied, .restricted:
                self.statusMessage = "Autorisation GPS requise"
            default:
                break
            }
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
            self?.statusMessage = "GPS: \(error.localizedDescription)"
        }
    }
}

extension TrackerModel: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.watchReachable = session.isReachable
            if let error {
                self?.statusMessage = "Watch: \(error.localizedDescription)"
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.watchReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWatchPayload(message)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.handleWatchPayload(applicationContext)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
