import ActivityKit
import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity

final class TrackerModel: NSObject, ObservableObject {
    enum Phase: String { case ready, active, paused }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var selectedActivity: ActivityKind = .automatic
    @Published private(set) var effectiveActivity: ActivityKind = .walking
    @Published private(set) var sessionID = ""
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
    @Published private(set) var maxHeartRate = 0.0
    @Published private(set) var activeEnergyKcal = 0.0
    @Published private(set) var cadenceSPM = 0.0
    @Published private(set) var steps = 0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var horizontalAccuracy = -1.0
    @Published private(set) var watchReachable = false
    @Published private(set) var healthAuthorized = false
    @Published private(set) var statusMessage = "Prêt"
    @Published private(set) var pendingCommand: String?
    @Published private(set) var lastSummary: TrackerSummary?
    @Published private(set) var currentWeather: SessionWeatherSnapshot?
    @Published private(set) var autoPauseEnabled = false

    var isActive: Bool { phase == .active || phase == .paused }
    var isPaused: Bool { phase == .paused }
    var displayActivity: ActivityKind { selectedActivity.isAutomatic ? effectiveActivity : selectedActivity }
    var gpsSettled: Bool { horizontalAccuracy > 0 && horizontalAccuracy <= 20 && elapsedSeconds >= 5 }

    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private let store = NativeSessionStore()
    private let defaults = UserDefaults.standard
    private let pedometer = CMPedometer()
    private let weatherRecorder = WorkoutWeatherRecorder()

    private var mirroredWorkoutSession: HKWorkoutSession?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var timer: Timer?
    private var previousLocation: CLLocation?
    private var previousAltitudeLocation: CLLocation?
    private var phoneDistanceMeters = 0.0
    private var phoneSpeedMps = 0.0
    private var phoneElevationGainMeters = 0.0
    private var phoneElevationLossMeters = 0.0
    private var lastHeartRateSample = 0.0
    private var lastAuthorityRevision: Int64 = 0
    private var pendingCommandAtRevision: Int64 = -1
    private var selectionRevision: Int64 = 0
    private var lastEndedSessionID = ""
    private var lastPurgeID = ""
    private var liveActivity: Activity<TrackerActivityAttributes>?
    private var lastLiveActivityUpdate = Date.distantPast
    private var lastRemotePhase: String?
    private var lastEffectiveActivity: ActivityKind = .walking
    private var cadenceAccumulator = 0.0
    private var cadenceSampleCount = 0
    private var lastGPSRejectionLog = Date.distantPast

    override init() {
        super.init()
        lastPurgeID = defaults.string(forKey: "tracker.lastPurgeID") ?? ""
        autoPauseEnabled = defaults.bool(forKey: "tracker.autoPauseEnabled")
        recoverLiveActivity()
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
            if !isActive { statusMessage = "GPS prêt" }
        case .denied, .restricted:
            statusMessage = "Autorisation GPS requise"
        @unknown default:
            break
        }
    }

    func selectActivity(_ activity: ActivityKind) {
        guard !isActive, pendingCommand == nil else { return }
        selectedActivity = activity
        effectiveActivity = activity.isAutomatic ? .walking : activity
        lastEffectiveActivity = effectiveActivity
        selectionRevision = Self.revisionNow()
        statusMessage = activity.isAutomatic ? "Auto · marche/course/vélo" : activity.label
        sendWC(makeMessage(kind: .selection))
    }

    func setAutoPauseEnabled(_ enabled: Bool) {
        guard !isActive else { return }
        autoPauseEnabled = enabled
        defaults.set(enabled, forKey: "tracker.autoPauseEnabled")
        sendPreferences()
    }

    func startFromPhone() {
        guard !isActive, pendingCommand == nil else { return }
        let identifier = Self.makeSessionID()
        sessionID = identifier
        lastEndedSessionID = ""
        lastAuthorityRevision = 0
        pendingCommand = "start"
        pendingCommandAtRevision = 0
        statusMessage = "Démarrage en attente de confirmation de la Watch…"

        sendPreferences()
        var request = makeMessage(kind: .request)
        request.command = "start"
        sendWC(request)
        launchWatchWorkout()

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self,
                  self.pendingCommand == "start",
                  self.sessionID == identifier,
                  !self.isActive else { return }
            self.pendingCommand = nil
            self.pendingCommandAtRevision = -1
            self.sessionID = ""
            self.statusMessage = "La Watch n’a pas confirmé le démarrage"
        }
    }

    func pauseFromPhone() { requestControl("pause", allowed: phase == .active) }
    func resumeFromPhone() { requestControl("resume", allowed: phase == .paused) }
    func stopFromPhone() {
        if let location = previousLocation {
            captureWeather(at: location, force: true)
        }
        requestControl("stop", allowed: isActive)
    }

    func deleteAllTestData() {
        guard !isActive, pendingCommand == nil else {
            statusMessage = "Termine la session avant d’effacer les données"
            return
        }
        let purgeID = UUID().uuidString
        applyPurge(purgeID)
        var message = makeMessage(kind: .purge)
        message.purgeID = purgeID
        sendWC(message)
    }

    private func requestControl(_ command: String, allowed: Bool) {
        guard allowed, pendingCommand == nil else { return }
        pendingCommand = command
        pendingCommandAtRevision = lastAuthorityRevision
        store.appendEvent("control_requested", source: "iphone", payload: [
            "command": command,
            "authority_revision": lastAuthorityRevision,
        ])
        statusMessage = "Commande \(command) envoyée à la Watch…"
        var request = makeMessage(kind: .request)
        request.command = command
        sendToWatch(request)
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
                mirroredSession.delegate = self
                self.store.appendEvent("health_mirror_connected", source: "iphone")
                self.statusMessage = "Watch connectée · session miroir active"
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

        let readTypes: Set<HKObjectType> = [heartRateType, energyType, distanceType, HKObjectType.workoutType()]
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthAuthorized = success
                if let error { self?.statusMessage = "Santé: \(error.localizedDescription)" }
            }
        }
    }

    private func launchWatchWorkout() {
        let configuration = HKWorkoutConfiguration()
        // Auto no longer starts as Mixed Cardio. Until multi-segment Auto is promoted, it starts
        // with the current conservative effective type (Walking by default) instead of lying in Health.
        configuration.activityType = selectedActivity.isAutomatic ? effectiveActivity.healthKitType : selectedActivity.healthKitType
        configuration.locationType = .outdoor

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.healthStore.startWatchApp(toHandle: configuration)
                await MainActor.run {
                    if self.pendingCommand == "start" {
                        self.statusMessage = "Démarrage envoyé à l’Apple Watch…"
                    }
                }
            } catch {
                await MainActor.run {
                    if self.pendingCommand == "start" {
                        self.statusMessage = "Watch à ouvrir · attente de confirmation…"
                    }
                }
            }
        }
    }

    private func beginLocalSession(sessionID: String, origin: String) {
        if isActive, self.sessionID == sessionID { return }
        requestLocationPermission()
        self.sessionID = sessionID
        startedAt = Date()
        pausedAt = nil
        pausedDuration = 0
        resetPresentationData(keepActivity: true)
        phase = .active

        do {
            try store.begin(
                sessionID: sessionID,
                metadata: [
                    "app": "Watch Tracker",
                    "build_sha": BuildInfo.gitSHA,
                    "origin": origin,
                    "platform": "iphone",
                    "selected_activity": selectedActivity.rawValue,
                    "effective_activity": effectiveActivity.rawValue,
                    "sync_architecture": "watch_authoritative_v4",
                    "auto_pause_enabled": autoPauseEnabled,
                ]
            )
            store.appendEvent("session_started", source: "iphone", payload: [
                "origin": origin,
                "authority_revision": lastAuthorityRevision,
            ])
        } catch {
            statusMessage = "Enregistrement local indisponible"
        }

        weatherRecorder.reset()
        locationManager.startUpdatingLocation()
        startPedometer()
        startClock()
        startLiveActivity()
    }

    private func applyAuthority(_ message: TrackerWireMessage) {
        guard message.kind == .authority else { return }
        guard !message.sessionID.isEmpty else { return }
        guard message.sessionID != lastEndedSessionID else { return }
        guard message.revision >= lastAuthorityRevision else {
            store.appendEvent("stale_authority_rejected", source: "iphone", payload: [
                "received_revision": message.revision,
                "current_revision": lastAuthorityRevision,
            ])
            return
        }

        applyPurgeIfNeeded(message.purgeID)
        let previousRevision = lastAuthorityRevision
        lastAuthorityRevision = message.revision
        selectionRevision = max(selectionRevision, message.selectionRevision)
        if let selected = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = selected }
        if let effective = ActivityKind(rawValue: message.effectiveActivity), !effective.isAutomatic {
            if effective != effectiveActivity {
                store.appendEvent("effective_activity_changed", source: "watch", payload: [
                    "from": effectiveActivity.rawValue,
                    "to": effective.rawValue,
                    "authority_revision": message.revision,
                ])
            }
            effectiveActivity = effective
            lastEffectiveActivity = effective
        }

        let remotePhase = Phase(rawValue: message.phase ?? "")
        if (remotePhase == .active || remotePhase == .paused), (!isActive || sessionID != message.sessionID) {
            beginLocalSession(sessionID: message.sessionID, origin: "watch")
        }

        if let started = message.startedAt {
            let authoritativeStart = Date(timeIntervalSince1970: started)
            if self.startedAt == nil || abs(self.startedAt!.timeIntervalSince(authoritativeStart)) > 2 {
                self.startedAt = authoritativeStart
                pausedDuration = 0
            }
        }

        if let value = message.elapsedSeconds { elapsedSeconds = value }
        if let value = message.distanceMeters { distanceMeters = max(0, value) }
        if let value = message.speedMps {
            let limit = Self.plausibleSpeedLimit(for: displayActivity)
            if value >= 0, value <= limit {
                currentSpeedMps = value
                maxSpeedMps = max(maxSpeedMps, value)
            } else if Date().timeIntervalSince(lastGPSRejectionLog) > 5 {
                lastGPSRejectionLog = Date()
                store.appendEvent("authority_speed_rejected", source: "iphone", payload: [
                    "speed_mps": value,
                    "limit_mps": limit,
                    "activity": displayActivity.rawValue,
                ])
            }
        }
        if let value = message.altitudeMeters { altitudeMeters = value }
        if let value = message.elevationGainMeters { elevationGainMeters = max(0, value) }
        if let value = message.elevationLossMeters { elevationLossMeters = max(0, value) }
        if let value = message.heartRateBPM {
            heartRate = max(0, value)
            maxHeartRate = max(maxHeartRate, heartRate)
            if value > 0, abs(value - lastHeartRateSample) >= 0.1 {
                lastHeartRateSample = value
                store.appendSample(source: "watch", kind: "heart_rate", payload: [
                    "bpm": value,
                    "activity": effectiveActivity.rawValue,
                ])
            }
        }
        if let value = message.averageHeartRateBPM { averageHeartRate = max(0, value) }
        if let value = message.activeEnergyKcal { activeEnergyKcal = max(0, value) }
        averageSpeedMps = elapsedSeconds > 0 ? distanceMeters / elapsedSeconds : 0

        let acknowledgedPending = pendingCommand != nil && message.revision > pendingCommandAtRevision

        if lastRemotePhase != message.phase {
            store.appendEvent("phase_changed", source: "watch", payload: [
                "from": lastRemotePhase ?? "none",
                "to": message.phase ?? "none",
                "authority_revision": message.revision,
                "selection_revision": message.selectionRevision,
            ])
            lastRemotePhase = message.phase
        }

        switch remotePhase {
        case .active:
            if phase == .paused, let pausedAt {
                pausedDuration += Date().timeIntervalSince(pausedAt)
            }
            pausedAt = nil
            phase = .active
            statusMessage = selectedActivity.isAutomatic
                ? "Auto · \(effectiveActivity.label) détectée"
                : "\(effectiveActivity.label) · Watch autoritaire"
        case .paused:
            if phase != .paused { pausedAt = Date() }
            phase = .paused
            currentSpeedMps = 0
            statusMessage = "En pause · synchronisé"
        case .ready:
            break
        case .none:
            if message.phase == "ended" {
                if acknowledgedPending || message.revision > previousRevision {
                    pendingCommand = nil
                    pendingCommandAtRevision = -1
                }
                finishLocalSession(reason: "watch")
                return
            }
        }

        if acknowledgedPending {
            store.appendEvent("control_acknowledged", source: "watch", payload: [
                "command": pendingCommand ?? "unknown",
                "authority_revision": message.revision,
            ])
            pendingCommand = nil
            pendingCommandAtRevision = -1
        }
        updateLiveActivity(force: remotePhase != .active)
    }

    private func finishLocalSession(reason: String) {
        guard isActive, let start = startedAt else {
            phase = .ready
            pendingCommand = nil
            pendingCommandAtRevision = -1
            sessionID = ""
            return
        }
        let end = Date()
        store.appendEvent("session_finished", source: "iphone", payload: [
            "reason": reason,
            "authority_revision": lastAuthorityRevision,
        ])

        let averageCadence = cadenceSampleCount > 0 ? cadenceAccumulator / Double(cadenceSampleCount) : nil
        let summary = TrackerSummary(
            sessionID: sessionID,
            activity: effectiveActivity.rawValue,
            startedAt: start,
            endedAt: end,
            duration: elapsedSeconds,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            maxSpeedMps: maxSpeedMps,
            averageHeartRate: averageHeartRate,
            activeEnergyKcal: activeEnergyKcal,
            maxHeartRate: maxHeartRate,
            averageCadenceSPM: averageCadence,
            weatherSnapshots: weatherRecorder.snapshots,
            segments: nil,
            buildSHA: BuildInfo.gitSHA,
            schemaVersion: NativeSessionStore.currentSchema,
            algorithmVersion: NativeSessionStore.currentAlgorithmVersion
        )
        lastEndedSessionID = sessionID
        store.finish(summary: summary)
        lastSummary = summary
        locationManager.stopUpdatingLocation()
        stopPedometer()
        timer?.invalidate()
        timer = nil
        phase = .ready
        currentSpeedMps = 0
        statusMessage = "\(effectiveActivity.label) terminée · synchronisée"
        pendingCommand = nil
        pendingCommandAtRevision = -1
        endLiveActivity(final: true)
        mirroredWorkoutSession = nil
        startedAt = nil
        pausedAt = nil
    }

    private func resetPresentationData(keepActivity: Bool) {
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
        maxHeartRate = 0
        activeEnergyKcal = 0
        cadenceSPM = 0
        steps = 0
        route = []
        currentCoordinate = nil
        horizontalAccuracy = -1
        previousLocation = nil
        previousAltitudeLocation = nil
        phoneDistanceMeters = 0
        phoneSpeedMps = 0
        phoneElevationGainMeters = 0
        phoneElevationLossMeters = 0
        lastHeartRateSample = 0
        lastRemotePhase = nil
        lastGPSRejectionLog = .distantPast
        cadenceAccumulator = 0
        cadenceSampleCount = 0
        currentWeather = nil
        weatherRecorder.reset()
        if !keepActivity {
            selectedActivity = .automatic
            effectiveActivity = .walking
        }
        lastEffectiveActivity = effectiveActivity
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.phase == .active, let start = self.startedAt {
                    self.elapsedSeconds = max(self.elapsedSeconds, Date().timeIntervalSince(start) - self.pausedDuration)
                    self.averageSpeedMps = self.elapsedSeconds > 0 ? self.distanceMeters / self.elapsedSeconds : 0
                }
                self.updateLiveActivity()
            }
        }
    }

    private func startPedometer() {
        stopPedometer()
        guard CMPedometer.isStepCountingAvailable() || CMPedometer.isCadenceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                if let error {
                    self.store.appendEvent("pedometer_error", source: "iphone", payload: ["message": error.localizedDescription])
                    return
                }
                guard let data else { return }
                self.steps = data.numberOfSteps.intValue
                if let cadence = data.currentCadence?.doubleValue, cadence > 0 {
                    self.cadenceSPM = cadence * 60
                    self.cadenceAccumulator += self.cadenceSPM
                    self.cadenceSampleCount += 1
                }
                var payload: [String: Any] = ["steps": self.steps]
                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }
                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }
                if let distance = data.distance?.doubleValue { payload["distance_m"] = distance }
                self.store.appendSample(source: "iphone", kind: "pedometer", payload: payload)
            }
        }
    }

    private func stopPedometer() {
        pedometer.stopUpdates()
    }

    private func accept(location: CLLocation) {
        guard phase == .active else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        horizontalAccuracy = location.horizontalAccuracy
        currentCoordinate = location.coordinate

        if let previous = previousLocation {
            let delta = location.distance(from: previous)
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            let impliedSpeed = dt > 0 ? delta / dt : .infinity
            let rawSpeed = location.speed >= 0 ? location.speed : impliedSpeed
            let limit = Self.plausibleSpeedLimit(for: displayActivity)
            let accuracyOK = max(previous.horizontalAccuracy, location.horizontalAccuracy) <= 25
            let plausible = dt > 0.15 && dt < 12 && delta >= 0.6 && delta < 150 && impliedSpeed <= limit * 1.35 && rawSpeed <= limit * 1.35

            if accuracyOK, plausible {
                phoneDistanceMeters += delta
                let clippedSpeed = min(rawSpeed, limit)
                phoneSpeedMps = phoneSpeedMps == 0 ? clippedSpeed : phoneSpeedMps * 0.78 + clippedSpeed * 0.22
            } else if Date().timeIntervalSince(lastGPSRejectionLog) > 5, delta > 3 {
                lastGPSRejectionLog = Date()
                store.appendEvent("iphone_gps_delta_rejected", source: "iphone", payload: [
                    "delta_m": delta,
                    "dt_s": dt,
                    "implied_speed_mps": impliedSpeed.isFinite ? impliedSpeed : -1,
                    "horizontal_accuracy_m": location.horizontalAccuracy,
                    "activity": displayActivity.rawValue,
                ])
            }
        }

        if location.verticalAccuracy >= 0, location.verticalAccuracy <= 12, let previousAltitudeLocation {
            let delta = location.altitude - previousAltitudeLocation.altitude
            if abs(delta) >= 3.0 {
                if delta > 0 { phoneElevationGainMeters += delta } else { phoneElevationLossMeters += abs(delta) }
                self.previousAltitudeLocation = location
            }
        } else if previousAltitudeLocation == nil, location.verticalAccuracy >= 0, location.verticalAccuracy <= 12 {
            previousAltitudeLocation = location
        }

        if route.isEmpty || location.distance(from: CLLocation(latitude: route.last!.latitude, longitude: route.last!.longitude)) >= 1.5 {
            route.append(location.coordinate)
        }
        previousLocation = location

        if lastAuthorityRevision == 0 {
            distanceMeters = phoneDistanceMeters
            currentSpeedMps = phoneSpeedMps
            maxSpeedMps = max(maxSpeedMps, phoneSpeedMps)
            altitudeMeters = location.altitude
            elevationGainMeters = phoneElevationGainMeters
            elevationLossMeters = phoneElevationLossMeters
        }

        store.appendSample(
            source: "iphone",
            kind: "location",
            payload: [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude_m": location.altitude,
                "speed_mps": phoneSpeedMps,
                "distance_m": phoneDistanceMeters,
                "selected_activity": selectedActivity.rawValue,
                "effective_activity": effectiveActivity.rawValue,
            ],
            quality: [
                "horizontal_accuracy_m": location.horizontalAccuracy,
                "vertical_accuracy_m": location.verticalAccuracy,
                "native_speed_mps": location.speed,
                "native_speed_accuracy_mps": location.speedAccuracy,
            ]
        )

        captureWeather(at: location)
    }

    private func captureWeather(at location: CLLocation, force: Bool = false) {
        weatherRecorder.captureIfNeeded(at: location, force: force) { [weak self] snapshot in
            guard let self, let snapshot, self.isActive else { return }
            self.currentWeather = snapshot
            var payload: [String: Any] = [
                "provider": snapshot.provider,
                "latitude": snapshot.latitude,
                "longitude": snapshot.longitude,
            ]
            if let value = snapshot.temperatureC { payload["temperature_c"] = value }
            if let value = snapshot.apparentTemperatureC { payload["apparent_temperature_c"] = value }
            if let value = snapshot.relativeHumidityPercent { payload["relative_humidity_percent"] = value }
            if let value = snapshot.pressureHPA { payload["pressure_hpa"] = value }
            if let value = snapshot.windSpeedKPH { payload["wind_speed_kph"] = value }
            if let value = snapshot.windDirectionDegrees { payload["wind_direction_degrees"] = value }
            if let value = snapshot.windGustKPH { payload["wind_gust_kph"] = value }
            if let value = snapshot.weatherCode { payload["weather_code"] = value }
            self.store.appendSample(source: "weather", kind: "weather", payload: payload)
            self.store.appendEvent("weather_snapshot", source: "iphone", payload: ["provider": snapshot.provider])
        }
    }

    private func makeMessage(kind: TrackerWireMessage.Kind) -> TrackerWireMessage {
        TrackerWireMessage(
            kind: kind,
            command: nil,
            sessionID: sessionID,
            revision: lastAuthorityRevision,
            selectionRevision: selectionRevision,
            selectedActivity: selectedActivity.rawValue,
            effectiveActivity: effectiveActivity.rawValue,
            phase: isActive ? phase.rawValue : "ready",
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

    private func sendToWatch(_ message: TrackerWireMessage) {
        if let data = TrackerWireCodec.encode(message), let mirroredWorkoutSession {
            mirroredWorkoutSession.sendToRemoteWorkoutSession(data: data) { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !success, let error {
                        self.store.appendEvent("remote_workout_send_error", source: "iphone", payload: ["message": error.localizedDescription])
                    }
                }
            }
        }
        sendWC(message)
    }

    private func sendWC(_ message: TrackerWireMessage) {
        guard WCSession.isSupported(), let data = TrackerWireCodec.encode(message) else { return }
        let payload: [String: Any] = ["type": "tracker_wire_v3", "data": data]
        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                DispatchQueue.main.async {
                    self?.store.appendEvent("watchconnectivity_send_error", source: "iphone", payload: ["message": error.localizedDescription])
                }
            }
        }
    }

    private func sendPreferences() {
        guard WCSession.isSupported() else { return }
        let payload: [String: Any] = [
            "type": "tracker_preferences_v4",
            "auto_pause_enabled": autoPauseEnabled,
            "timestamp": Date().timeIntervalSince1970,
        ]
        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    private func handleWire(_ message: TrackerWireMessage) {
        applyPurgeIfNeeded(message.purgeID)
        switch message.kind {
        case .authority:
            applyAuthority(message)
        case .selection:
            guard !isActive, message.selectionRevision >= selectionRevision else { return }
            selectionRevision = message.selectionRevision
            if let value = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = value }
            if let value = ActivityKind(rawValue: message.effectiveActivity), !value.isAutomatic { effectiveActivity = value }
            statusMessage = selectedActivity.isAutomatic ? "Auto synchronisé" : "\(selectedActivity.label) synchronisée"
        case .purge:
            applyPurgeIfNeeded(message.purgeID)
        case .request:
            break
        }
    }

    private func applyPurgeIfNeeded(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID, !isActive else { return }
        applyPurge(purgeID)
    }

    private func applyPurge(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID else { return }
        lastPurgeID = purgeID
        defaults.set(purgeID, forKey: "tracker.lastPurgeID")
        do {
            try store.deleteAllSessions()
            resetPresentationData(keepActivity: true)
            sessionID = ""
            lastEndedSessionID = ""
            lastAuthorityRevision = 0
            lastSummary = nil
            pendingCommand = nil
            pendingCommandAtRevision = -1
            statusMessage = "Toutes les activités locales ont été effacées"
            endLiveActivity(final: false)
        } catch {
            statusMessage = "Suppression impossible: \(error.localizedDescription)"
        }
    }

    private func recoverLiveActivity() {
        liveActivity = Activity<TrackerActivityAttributes>.activities.first
    }

    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, liveActivity == nil else { return }
        let attributes = TrackerActivityAttributes(sessionID: sessionID)
        let content = ActivityContent(state: liveState(), staleDate: nil)
        do {
            liveActivity = try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            statusMessage = "Session active · Live Activity indisponible"
        }
    }

    private func updateLiveActivity(force: Bool = false) {
        guard let liveActivity else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastLiveActivityUpdate) >= 5 else { return }
        lastLiveActivityUpdate = now
        let content = ActivityContent(state: liveState(), staleDate: nil)
        Task { await liveActivity.update(content) }
    }

    private func endLiveActivity(final: Bool) {
        guard let activity = liveActivity else { return }
        let content = ActivityContent(state: liveState(), staleDate: nil)
        liveActivity = nil
        Task {
            await activity.end(content, dismissalPolicy: final ? .after(Date().addingTimeInterval(30)) : .immediate)
        }
    }

    private func liveState() -> TrackerActivityAttributes.ContentState {
        TrackerActivityAttributes.ContentState(
            activity: displayActivity.label,
            phase: phase.rawValue,
            elapsedSeconds: elapsedSeconds,
            referenceDate: Date(),
            distanceMeters: distanceMeters,
            speedKPH: gpsSettled ? currentSpeedMps * 3.6 : 0,
            heartRateBPM: heartRate,
            elevationGainMeters: elevationGainMeters
        )
    }

    private static func plausibleSpeedLimit(for activity: ActivityKind) -> Double {
        switch activity {
        case .walking: return 3.6
        case .hiking: return 3.3
        case .running, .trackAndField: return 12.5
        case .cycling, .handCycling: return 28
        case .crossCountrySkiing, .downhillSkiing, .snowSports, .snowboarding, .skatingSports: return 35
        case .swimming, .waterFitness, .waterPolo: return 4
        case .automatic: return 28
        default: return 20
        }
    }

    private static func makeSessionID() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }
    private static func revisionNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension TrackerModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                if self.phase == .active { manager.startUpdatingLocation() }
            case .denied, .restricted:
                self.statusMessage = "Autorisation GPS requise"
                self.store.appendEvent("location_authorization_denied", source: "iphone")
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in self?.accept(location: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "GPS: \(error.localizedDescription)"
            self?.store.appendEvent("location_error", source: "iphone", payload: ["message": error.localizedDescription])
        }
    }
}

extension TrackerModel: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.store.appendEvent("health_session_state", source: "iphone", payload: [
                "from": fromState.rawValue,
                "to": toState.rawValue,
                "mirrored": workoutSession.type == .mirrored,
            ])
            if workoutSession.type == .mirrored, toState == .running, self.pendingCommand == nil {
                self.statusMessage = "Session miroir HealthKit active"
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.statusMessage = "HealthKit: \(error.localizedDescription)"
            self?.store.appendEvent("health_session_error", source: "iphone", payload: ["message": error.localizedDescription])
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for packet in data {
            guard let message = TrackerWireCodec.decode(packet) else { continue }
            DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didDisconnectFromRemoteDeviceWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.mirroredWorkoutSession = nil
            self.store.appendEvent("health_mirror_disconnected", source: "iphone", payload: [
                "message": error?.localizedDescription ?? "none",
            ])
            self.statusMessage = error == nil ? "Watch en reconnexion…" : "Watch déconnectée: \(error!.localizedDescription)"
        }
    }
}

extension TrackerModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.watchReachable = session.isReachable
            if let error { self.statusMessage = "Watch: \(error.localizedDescription)" }
            self.sendPreferences()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let previous = self.watchReachable
            self.watchReachable = session.isReachable
            if self.isActive, previous != session.isReachable {
                self.store.appendEvent("watch_reachability_changed", source: "iphone", payload: ["reachable": session.isReachable])
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }

    private func receiveWC(_ payload: [String: Any]) {
        if payload["type"] as? String == "sensor_sample",
           let source = payload["source"] as? String,
           let kind = payload["kind"] as? String,
           let sample = payload["payload"] as? [String: Any] {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isActive else { return }
                if kind == "event", let name = sample["name"] as? String {
                    var eventPayload = sample
                    eventPayload.removeValue(forKey: "name")
                    self.store.appendEvent(name, source: source, payload: eventPayload)
                } else {
                    self.store.appendSample(source: source, kind: kind, payload: sample)
                }
            }
            return
        }

        guard payload["type"] as? String == "tracker_wire_v3",
              let data = payload["data"] as? Data,
              let message = TrackerWireCodec.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
