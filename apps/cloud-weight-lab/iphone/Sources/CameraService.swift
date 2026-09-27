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

    private let analyzer = CloudAnalyzer()
    private let estimator = CloudMassEstimator()
    private let stabilizer = CloudTemporalStabilizer()
    private let overlayStabilizer = CloudOverlayStabilizer()
    private let telemetryMonitor = CloudTelemetryMonitor()
    private let diagnosticsStore = CloudDiagnosticsStore()
    private lazy var diagnosticsAPI: CloudDiagnosticsAPI = {
        let api = CloudDiagnosticsAPI(store: diagnosticsStore)
        api.stateDidChange = { [weak self] next in
            self?.apiState = next
        }
        return api
    }()

    private let captureQueue = DispatchQueue(label: "cloudweight.capture", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "cloudweight.analysis", qos: .userInitiated)
    private let minimumAnalysisInterval = 0.07
    private let rotationStateLock = NSLock()
    private var configured = false
    private var lastAnalysisTime = 0.0
    private var fieldOfViewDegrees = 65.0
    private var analysisInFlight = false
    private var droppedFrames = 0
    private var throttledFrames = 0
    private var videoOutput: AVCaptureVideoDataOutput?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureRotationDegrees = 0.0
    private var lastCaptureWidth = 0
    private var lastCaptureHeight = 0
    private var lastRawCoverage: Double?

    func requestAndStart() {
        telemetryMonitor.reset()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        diagnosticsAPI.start()

        guard analyzer.isReady else {
            status = .failed(analyzer.loadError ?? "Modèle de segmentation indisponible")
            return
        }

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

    func armDiagnosticsAPI() {
        diagnosticsAPI.armPairing(seconds: 45)
    }

    func unpairDiagnosticsAPI() {
        diagnosticsAPI.unpair()
    }

    func stop() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        diagnosticsAPI.stop()
        rotationObservation = nil
        captureQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
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
                    self.fieldOfViewDegrees = Double(camera.activeFormat.videoFieldOfView)
                } catch {
                    self.finishConfigurationFailure("Impossible d'ouvrir la caméra")
                    return
                }

                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_32BGRA
                ]
                output.setSampleBufferDelegate(self, queue: self.analysisQueue)

                guard self.session.canAddOutput(output) else {
                    self.finishConfigurationFailure("Flux vidéo indisponible")
                    return
                }
                self.session.addOutput(output)
                self.videoOutput = output

                let coordinator = AVCaptureDevice.RotationCoordinator(
                    device: camera,
                    previewLayer: nil
                )
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
                DispatchQueue.main.async {
                    self.activeCamera = camera
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.status = .running
            }
        }
    }

    private func applyCaptureRotation(_ angle: CGFloat) {
        rotationStateLock.lock()
        captureRotationDegrees = Double(angle)
        rotationStateLock.unlock()

        guard let connection = videoOutput?.connection(with: .video),
              connection.isVideoRotationAngleSupported(angle) else {
            return
        }
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
        DispatchQueue.main.async {
            self.status = .failed(message)
        }
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
        let now = CACurrentMediaTime()
        guard now - lastAnalysisTime >= minimumAnalysisInterval, !analysisInFlight else {
            throttledFrames += 1
            return
        }

        guard let cameraBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        lastAnalysisTime = now
        analysisInFlight = true
        let analysisStarted = CACurrentMediaTime()
        let captureWidth = CVPixelBufferGetWidth(cameraBuffer)
        let captureHeight = CVPixelBufferGetHeight(cameraBuffer)
        let captureOrientation = captureWidth > captureHeight ? "landscape" : "portrait"
        let sceneSanity = SceneSanityGate.evaluate(sampleBuffer: sampleBuffer)

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
        } else {
            rawAnalysis = analyzer.analyze(
                sampleBuffer: sampleBuffer,
                fieldOfViewDegrees: fieldOfViewDegrees
            )
            analyzerTiming = analyzer.lastTiming
        }

        let rawCoverage = rawAnalysis?.totalCoverage ?? 0
        let geometryChanged =
            lastCaptureWidth > 0
            && lastCaptureHeight > 0
            && (lastCaptureWidth != captureWidth || lastCaptureHeight != captureHeight)
        let sceneJump = lastRawCoverage.map { abs(rawCoverage - $0) > 0.30 } ?? false

        if geometryChanged || sceneJump {
            stabilizer.reset()
            overlayStabilizer.reset()
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
        let stabilizedOverlay = overlayStabilizer.update(rawAnalysis?.overlayImage)
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
            droppedFrames: droppedSincePreviousAnalysis,
            throttledFrames: throttledSincePreviousAnalysis,
            orientation: captureOrientation,
            deviceOrientation: currentOrientationName(),
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            captureRotationDegrees: currentCaptureRotationDegrees(),
            sceneLuminancePercent: sceneSanity.meanLuminance * 100,
            sceneRejected: sceneSanity.rejected
        )
        let nextReport = telemetryMonitor.makeReport(buildSHA: BuildInfo.gitSHA)

        diagnosticsStore.record(
            telemetry: nextTelemetry,
            detections: stabilizedDetections
        )
        diagnosticsStore.maybeCapture(
            sampleBuffer: sampleBuffer,
            overlayImage: stabilizedOverlay,
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

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

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
        let coordinator = AVCaptureDevice.RotationCoordinator(
            device: device,
            previewLayer: previewLayer
        )
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            guard let self,
                  let connection = self.previewLayer.connection else {
                return
            }
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
