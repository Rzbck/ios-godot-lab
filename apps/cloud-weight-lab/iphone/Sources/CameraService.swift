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

    private let analyzer = CloudAnalyzer()
    private let estimator = CloudMassEstimator()
    private let stabilizer = CloudTemporalStabilizer()
    private let telemetryMonitor = CloudTelemetryMonitor()
    private let captureQueue = DispatchQueue(label: "cloudweight.capture", qos: .userInitiated)
    private let analysisQueue = DispatchQueue(label: "cloudweight.analysis", qos: .userInitiated)
    private var configured = false
    private var lastAnalysisTime = 0.0
    private var fieldOfViewDegrees = 65.0
    private var analysisInFlight = false
    private var throttledFrames = 0

    func requestAndStart() {
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

    func stop() {
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
                self.session.commitConfiguration()
                self.configured = true
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                self.status = .running
            }
        }
    }

    private func finishConfigurationFailure(_ message: String) {
        session.commitConfiguration()
        DispatchQueue.main.async {
            self.status = .failed(message)
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
        guard now - lastAnalysisTime >= 0.18, !analysisInFlight else {
            throttledFrames += 1
            return
        }

        lastAnalysisTime = now
        analysisInFlight = true
        let analysisStarted = CACurrentMediaTime()

        let nextAnalysis = analyzer.analyze(
            sampleBuffer: sampleBuffer,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
        let rawDetections = nextAnalysis?.observations.compactMap { observation in
            estimator.estimate(from: observation).map {
                CloudDetection(observation: observation, estimate: $0)
            }
        } ?? []
        let stabilizedDetections = stabilizer.update(raw: rawDetections)
        let duration = CACurrentMediaTime() - analysisStarted
        let skippedSincePreviousAnalysis = throttledFrames
        throttledFrames = 0

        let nextTelemetry = telemetryMonitor.snapshot(
            analysisDurationSeconds: duration,
            analysis: nextAnalysis,
            rawDetections: rawDetections.count,
            stabilizedDetections: stabilizedDetections.count,
            throttledFrames: skippedSincePreviousAnalysis
        )

        analysisInFlight = false

        DispatchQueue.main.async { [weak self] in
            self?.analysis = nextAnalysis
            self?.detections = stabilizedDetections
            self?.telemetry = nextTelemetry
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let connection = view.previewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}
