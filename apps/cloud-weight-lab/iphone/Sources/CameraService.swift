import AVFoundation
import QuartzCore
import SwiftUI
import UIKit

final class CameraService: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case requesting
        case running
        case denied
        case failed(String)
    }

    let session = AVCaptureSession()

    @Published private(set) var status: Status = .idle
    @Published private(set) var analysis: CloudFrameAnalysis?
    @Published private(set) var detections: [CloudDetection] = []
    @Published private(set) var telemetry: CloudTelemetrySnapshot?
    @Published private(set) var diagnosticReport = ""
    @Published private(set) var activeCamera: AVCaptureDevice?
    @Published private(set) var apiState: CloudDiagnosticsAPI.State = .stopped
    @Published private(set) var analysisModelsReady = false

    // Core ML is deliberately loaded off the UI thread so the camera preview
    // can appear immediately at launch.
    private var analyzer: CloudAnalyzer?
    private var analyzerLoadStarted = false

    private let estimator = CloudMassEstimator()
    private let stabilizer = CloudTemporalStabilizer()
    private let overlayStabilizer = CloudOverlayStabilizer()
    private let telemetryMonitor = CloudTelemetryMonitor()
    private let diagnosticsStore = CloudDiagnosticsStore()
    private let sessionRecorder = CloudSessionRecorder()
    private lazy var diagnosticsAPI: CloudDiagnosticsAPI = {
        let api = CloudDiagnosticsAPI(store: diagnosticsStore, sessionRecorder: sessionRecorder)
        api.stateDidChange = { [weak self] next in
            self?.apiState = next
        }
        return api
    }()

    private let captureQueue = DispatchQueue(label: "cloudweight.capture", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "cloudweight.analysis", qos: .userInitiated)
    private let modelLoadQueue = DispatchQueue(label: "cloudweight.model-load", qos: .userInitiated)
    private let rotationStateLock = NSLock()
    private var configured = false
    private var fieldOfViewDegrees = 65.0
    private var analysisInFlight = false
    private var droppedFrames = 0
    private var throttledFrames = 0
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureRotationDegrees = 0.0
    private var lastCaptureWidth = 0
    private var lastCaptureHeight = 0
    private var lastRawCoverage: Double?
    private var lowLightActive = false
    private var lowLightEnterStreak = 0
    private var lowLightExitStreak = 0
    private var orientationNotificationsStarted = false
    private var appLifecycleActive = false

    func requestAndStart() {
        guard !appLifecycleActive else { return }
        appLifecycleActive = true

        telemetryMonitor.reset()

        if !orientationNotificationsStarted {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            orientationNotificationsStarted = true
        }

        diagnosticsAPI.start()
        prepareAnalyzer()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            status = .requesting
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.status = .denied
                    }
                }
            }
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .failed("Autorisation caméra inconnue")
        }
    }

    private func prepareAnalyzer() {
        guard !analyzerLoadStarted else { return }
        analyzerLoadStarted = true

        // Model construction must never block the camera analysis queue.
        // Once loading finishes, ownership is handed to analysisQueue so
        // captureOutput only reads/writes analyzer from one serial queue.
        modelLoadQueue.async { [weak self] in
            guard let self else { return }

            let loadedAnalyzer = CloudAnalyzer()

            guard loadedAnalyzer.isReady else {
                let message = loadedAnalyzer.loadError
                    ?? "Modèle de segmentation indisponible"

                DispatchQueue.main.async {
                    self.status = .failed(message)
                }
                return
            }

            self.analysisQueue.async {
                self.analyzer = loadedAnalyzer

                DispatchQueue.main.async {
                    self.analysisModelsReady = true
                }
            }
        }
    }

    func armDiagnosticsAPI() {
        diagnosticsAPI.armPairing(seconds: 120)
    }

    func unpairDiagnosticsAPI() {
        diagnosticsAPI.unpair()
    }

    func pauseForBackground() {
        guard appLifecycleActive else { return }
        appLifecycleActive = false

        diagnosticsAPI.stop()

        captureQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                self.session.stopRunning()
            }

            self.sessionRecorder.endSession()

            self.analysisQueue.async {
                self.stabilizer.reset()
                self.overlayStabilizer.reset()
                self.lastRawCoverage = nil
                self.lastCaptureWidth = 0
                self.lastCaptureHeight = 0
            }
        }
    }

    func stop() {
        appLifecycleActive = false

        if orientationNotificationsStarted {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            orientationNotificationsStarted = false
        }

        diagnosticsAPI.stop()
        rotationObservation = nil
        captureQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning { self.session.stopRunning() }
            self.sessionRecorder.endSession()
        }
    }

    private func configureAndStart() {
        captureQueue.async { [weak self] in
            guard let self else { return }

            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .hd1280x720

                guard let camera = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .back
                ) else {
                    self.finishConfigurationFailure("Caméra arrière indisponible")
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else {
                        self.finishConfigurationFailure("Entrée caméra indisponible")
                        return
                    }
                    self.session.addInput(input)
                    self.configureCameraForAnalysis(camera)
                    self.fieldOfViewDegrees = Double(camera.activeFormat.videoFieldOfView)
                    self.captureDevice = camera
                } catch {
                    self.finishConfigurationFailure("Impossible d'ouvrir la caméra")
                    return
                }

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: self.analysisQueue)

                guard self.session.canAddOutput(output) else {
                    self.finishConfigurationFailure("Flux vidéo indisponible")
                    return
                }
                self.session.addOutput(output)
                self.videoOutput = output

                let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
                self.rotationCoordinator = coordinator
                self.rotationObservation = coordinator.observe(
                    \.videoRotationAngleForHorizonLevelCapture,
                    options: [.initial, .new]
                ) { [weak self] coordinator, _ in
                    let angle = coordinator.videoRotationAngleForHorizonLevelCapture
                    self?.captureQueue.async { [weak self] in
                        self?.applyCaptureRotation(angle)
                    }
                }

                self.session.commitConfiguration()
                self.configured = true
                DispatchQueue.main.async { self.activeCamera = camera }
            }

            if !self.session.isRunning { self.session.startRunning() }
            self.sessionRecorder.startSession(buildSHA: BuildInfo.gitSHA, version: BuildInfo.version)
            DispatchQueue.main.async { self.status = .running }
        }
    }

    private func configureCameraForAnalysis(_ camera: AVCaptureDevice) {
        do {
            try camera.lockForConfiguration()
            defer { camera.unlockForConfiguration() }

            if camera.isExposureModeSupported(.continuousAutoExposure) {
                camera.exposureMode = .continuousAutoExposure
            }
            if camera.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            if camera.isLowLightBoostSupported {
                camera.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
        } catch {
            // Capture continues with system defaults; telemetry records support/state.
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        rotationStateLock.lock()
        captureRotationDegrees = Double(angle)
        rotationStateLock.unlock()

        guard let connection = videoOutput?.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    private func currentCaptureRotationDegrees() -> Double {
        rotationStateLock.lock()
        let value = captureRotationDegrees
        rotationStateLock.unlock()
        return value
    }

    private func finishConfigurationFailure(_ message: String) {
        session.commitConfiguration()
        DispatchQueue.main.async { self.status = .failed(message) }
    }

    private func updateLowLightMode(
        boostEnabled: Bool,
        iso: Double,
        exposureMilliseconds: Double,
        meanLuminance: Double
    ) -> Bool {
        let enterCandidate = boostEnabled
            || iso >= 110
            || exposureMilliseconds >= 17
            || meanLuminance < 0.22
        let exitCandidate = !boostEnabled
            && iso < 85
            && exposureMilliseconds < 13
            && meanLuminance > 0.30

        if lowLightActive {
            lowLightEnterStreak = 0
            if exitCandidate {
                lowLightExitStreak += 1
                if lowLightExitStreak >= 30 {
                    lowLightActive = false
                    lowLightExitStreak = 0
                }
            } else {
                lowLightExitStreak = 0
            }
        } else {
            lowLightExitStreak = 0
            if enterCandidate {
                lowLightEnterStreak += 1
                if lowLightEnterStreak >= 5 {
                    lowLightActive = true
                    lowLightEnterStreak = 0
                }
            } else {
                lowLightEnterStreak = 0
            }
        }
        return lowLightActive
    }

    private func currentOrientationName() -> String {
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !analysisInFlight else {
            throttledFrames += 1
            return
        }
        guard let cameraBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        analysisInFlight = true
        let analysisStarted = CACurrentMediaTime()
        let captureWidth = CVPixelBufferGetWidth(cameraBuffer)
        let captureHeight = CVPixelBufferGetHeight(cameraBuffer)
        let captureOrientation = captureWidth > captureHeight ? "landscape" : "portrait"
        let sceneSanity = SceneSanityGate.evaluate(sampleBuffer: sampleBuffer)

        let cameraISO = Double(captureDevice?.iso ?? 0)
        let exposureMilliseconds = captureDevice.map {
            max(0, CMTimeGetSeconds($0.exposureDuration) * 1_000)
        } ?? 0
        let exposureTargetOffset = Double(captureDevice?.exposureTargetOffset ?? 0)
        let boostSupported = captureDevice?.isLowLightBoostSupported ?? false
        let boostEnabled = captureDevice?.isLowLightBoostEnabled ?? false

        var whiteBalanceTemperature = 0.0
        var whiteBalanceTint = 0.0
        if let device = captureDevice {
            let values = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
            whiteBalanceTemperature = Double(values.temperature)
            whiteBalanceTint = Double(values.tint)
        }

        let lowLightMode = updateLowLightMode(
            boostEnabled: boostEnabled,
            iso: cameraISO,
            exposureMilliseconds: exposureMilliseconds,
            meanLuminance: sceneSanity.meanLuminance
        )

        let rawAnalysis: CloudFrameAnalysis?
        let analyzerTiming: CloudAnalyzerTiming?
        if sceneSanity.rejected {
            rawAnalysis = CloudFrameAnalysis(
                timestamp: Date(),
                observations: [],
                totalCoverage: 0,
                overlayImage: nil,
                engine: .ucloudNetCoreML,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
            analyzerTiming = nil
        } else if let analyzer {
            rawAnalysis = analyzer.analyze(
                sampleBuffer: sampleBuffer,
                fieldOfViewDegrees: fieldOfViewDegrees,
                environment: CloudAnalysisEnvironment(lowLight: lowLightMode)
            )
            analyzerTiming = analyzer.lastTiming
        } else {
            // Preview remains usable while Core ML finishes loading.
            rawAnalysis = CloudFrameAnalysis(
                timestamp: Date(),
                observations: [],
                totalCoverage: 0,
                overlayImage: nil,
                engine: .ucloudNetCoreML,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
            analyzerTiming = nil
        }

        let rawCoverage = rawAnalysis?.totalCoverage ?? 0
        let geometryChanged = lastCaptureWidth > 0
            && lastCaptureHeight > 0
            && (lastCaptureWidth != captureWidth || lastCaptureHeight != captureHeight)
        let sceneJump = lastRawCoverage.map { abs(rawCoverage - $0) > 0.60 } ?? false

        if geometryChanged || sceneJump {
            stabilizer.reset()
            overlayStabilizer.reset()
        }
        if geometryChanged {
            analyzer?.resetSemanticGate()
        }
        lastCaptureWidth = captureWidth
        lastCaptureHeight = captureHeight
        lastRawCoverage = rawCoverage

        let rawDetections = rawAnalysis?.observations.compactMap { observation in
            estimator.estimate(from: observation).map {
                CloudDetection(observation: observation, estimate: $0)
            }
        } ?? []
        let stabilizedDetections = stabilizer.update(raw: rawDetections)
        let stabilizedOverlay = overlayStabilizer.update(
            rawAnalysis?.overlayImage,
            detections: stabilizedDetections
        )
        let displayAnalysis = rawAnalysis.map { analysis in
            CloudFrameAnalysis(
                timestamp: analysis.timestamp,
                observations: analysis.observations,
                totalCoverage: analysis.totalCoverage,
                overlayImage: stabilizedOverlay,
                engine: analysis.engine,
                fieldOfViewDegrees: analysis.fieldOfViewDegrees
            )
        }

        let duration = CACurrentMediaTime() - analysisStarted
        let droppedSincePreviousAnalysis = droppedFrames
        let throttledSincePreviousAnalysis = throttledFrames
        droppedFrames = 0
        throttledFrames = 0

        let nextTelemetry = telemetryMonitor.snapshot(
            analysisDurationSeconds: duration,
            analyzerTiming: analyzerTiming,
            analysis: rawAnalysis,
            rawDetections: rawDetections.count,
            stabilizedDetections: stabilizedDetections.count,
            trackingStats: stabilizer.lastStats,
            droppedFrames: droppedSincePreviousAnalysis,
            throttledFrames: throttledSincePreviousAnalysis,
            orientation: captureOrientation,
            deviceOrientation: currentOrientationName(),
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            captureRotationDegrees: currentCaptureRotationDegrees(),
            sceneLuminancePercent: sceneSanity.meanLuminance * 100,
            sceneSaturationPercent: sceneSanity.meanSaturation * 100,
            sceneDarkPercent: sceneSanity.darkFraction * 100,
            sceneBrightPercent: sceneSanity.brightFraction * 100,
            sceneClippedPercent: sceneSanity.clippedFraction * 100,
            sceneNeutralHighlightPercent: sceneSanity.neutralHighlightFraction * 100,
            sceneRejected: sceneSanity.rejected,
            lowLightMode: lowLightMode,
            cameraISO: cameraISO,
            cameraExposureMilliseconds: exposureMilliseconds,
            cameraExposureTargetOffset: exposureTargetOffset,
            cameraLowLightBoostSupported: boostSupported,
            cameraLowLightBoostEnabled: boostEnabled,
            cameraWhiteBalanceTemperatureKelvin: whiteBalanceTemperature,
            cameraWhiteBalanceTint: whiteBalanceTint
        )
        let nextReport = telemetryMonitor.makeReport(buildSHA: BuildInfo.gitSHA)

        diagnosticsStore.record(telemetry: nextTelemetry, detections: stabilizedDetections)
        // Diagnostics deliberately preserve the raw segmentation so false
        // positives remain inspectable even though the normal UI hides them.
        diagnosticsStore.maybeCapture(
            sampleBuffer: sampleBuffer,
            overlayImage: rawAnalysis?.overlayImage,
            telemetry: nextTelemetry,
            detections: stabilizedDetections
        )
        sessionRecorder.record(telemetry: nextTelemetry, detections: stabilizedDetections)
        sessionRecorder.maybeCapture(
            sampleBuffer: sampleBuffer,
            overlayImage: rawAnalysis?.overlayImage,
            telemetry: nextTelemetry,
            detections: stabilizedDetections
        )

        analysisInFlight = false

        DispatchQueue.main.async { [weak self] in
            self?.analysis = displayAnalysis
            self?.detections = stabilizedDetections
            self?.telemetry = nextTelemetry
            self?.diagnosticReport = nextReport
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        droppedFrames += 1
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    private weak var configuredDevice: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    func configure(session: AVCaptureSession, device: AVCaptureDevice?) {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill

        guard let device else { return }
        guard configuredDevice !== device else { return }

        configuredDevice = device
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            guard let self, let connection = self.previewLayer.connection else { return }
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.configure(session: session, device: device)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.configure(session: session, device: device)
    }
}
