import SwiftUI
import UIKit

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @State private var pulse = false
    @State private var showDiagnostics = false
    @State private var diagnosticCopied = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .opacity(camera.status == .running ? 1 : 0.15)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.56),
                    .clear,
                    .clear,
                    Color.black.opacity(0.68)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            detectionOverlay
                .ignoresSafeArea()

            VStack(spacing: 8) {
                header
                if showDiagnostics {
                    diagnosticsCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .task {
            camera.requestAndStart()
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            camera.stop()
        }
        .animation(.easeInOut(duration: 0.22), value: camera.detections.count)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLOUD WEIGHT")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(1.3)
                Text("détourage neuronal du ciel")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.20)) {
                    showDiagnostics.toggle()
                    diagnosticCopied = false
                }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: statusColor.opacity(0.8), radius: 5)
                    Text(statusText)
                        .font(.system(size: 10.5, weight: .black, design: .rounded))
                        .tracking(0.55)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(showDiagnostics ? .white : .white.opacity(0.55))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var diagnosticsCard: some View {
        if let telemetry = camera.telemetry {
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    diagnosticMetric(
                        title: "PIPELINE",
                        value: String(format: "%.0f ms", telemetry.analysisMilliseconds)
                    )
                    diagnosticMetric(
                        title: "CADENCE",
                        value: telemetry.effectiveHz > 0
                            ? String(format: "%.1f Hz", telemetry.effectiveHz)
                            : "—"
                    )
                    diagnosticMetric(
                        title: "Δ MASQUE",
                        value: String(format: "%.1f %%", telemetry.maskChangePercent)
                    )
                    diagnosticMetric(
                        title: "NUAGE",
                        value: String(format: "%.1f %%", telemetry.cloudCoveragePercent)
                    )
                }

                HStack(spacing: 7) {
                    diagnosticMetric(
                        title: "PREP",
                        value: String(format: "%.0f ms", telemetry.preprocessingMilliseconds)
                    )
                    diagnosticMetric(
                        title: "CIEL AI",
                        value: String(format: "%.0f ms", telemetry.skyInferenceMilliseconds)
                    )
                    diagnosticMetric(
                        title: "NUAGE AI",
                        value: String(format: "%.0f ms", telemetry.cloudInferenceMilliseconds)
                    )
                    diagnosticMetric(
                        title: "POST",
                        value: String(format: "%.0f ms", telemetry.postprocessingMilliseconds)
                    )
                }

                HStack(spacing: 7) {
                    diagnosticMetric(
                        title: "CIEL",
                        value: String(format: "%.1f %%", telemetry.skyCoveragePercent)
                    )
                    diagnosticMetric(
                        title: "BRUT→STABLE",
                        value: "\(telemetry.rawDetections)→\(telemetry.stabilizedDetections)"
                    )
                    diagnosticMetric(
                        title: "DROP/THR",
                        value: "\(telemetry.droppedFrames)/\(telemetry.throttledFrames)"
                    )
                    diagnosticMetric(
                        title: "ORIENT.",
                        value: shortOrientation(telemetry.orientation)
                    )
                }

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("THERMAL · \(telemetry.thermalState.uppercased())")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        Text("Paysage mesuré en V5 mais pas encore corrigé : la V4/V5 reste orientée portrait.")
                            .font(.system(size: 8.2, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        guard !camera.diagnosticReport.isEmpty else { return }
                        UIPasteboard.general.string = camera.diagnosticReport
                        diagnosticCopied = true
                    } label: {
                        Label(
                            diagnosticCopied ? "COPIÉ" : "COPIER DIAG",
                            systemImage: diagnosticCopied ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .tracking(0.3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.diagnosticReport.isEmpty)
                }

                Text("V5 · \(BuildInfo.gitSHA) · rapport local uniquement · aucune image, localisation ou identité appareil")
                    .font(.system(size: 8.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.46))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                .black.opacity(0.52),
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.14), lineWidth: 1)
            )
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Télémétrie : attente de la première analyse…")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .padding(10)
            .background(.black.opacity(0.45), in: Capsule())
        }
    }

    private func diagnosticMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 7.2, weight: .black, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 9.4, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.54)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            .white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    @ViewBuilder
    private var detectionOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = camera.analysis?.overlayImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(0.84)
                        .transition(.opacity)
                }

                ForEach(camera.detections.prefix(6)) { detection in
                    cloudLabel(detection)
                        .position(
                            x: clamped(
                                detection.observation.centroid.x * proxy.size.width,
                                lower: 66,
                                upper: max(66, proxy.size.width - 66)
                            ),
                            y: clamped(
                                detection.observation.centroid.y * proxy.size.height,
                                lower: 92,
                                upper: max(92, proxy.size.height - 160)
                            )
                        )
                }

                if camera.status == .running && camera.detections.isEmpty {
                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.17), lineWidth: 1)
                            .frame(
                                width: pulse ? 128 : 104,
                                height: pulse ? 128 : 104
                            )
                        Circle()
                            .stroke(.white.opacity(0.72), lineWidth: 1.4)
                            .frame(width: 62, height: 62)
                        Rectangle()
                            .fill(.white.opacity(0.82))
                            .frame(width: 18, height: 1)
                        Rectangle()
                            .fill(.white.opacity(0.82))
                            .frame(width: 1, height: 18)
                    }
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * 0.43
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cloudLabel(_ detection: CloudDetection) -> some View {
        VStack(spacing: 2) {
            Text(detection.observation.kind.rawValue.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.72))
            Text("≈ \(massString(detection.estimate.midpointKilograms))")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(.black.opacity(0.50), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        switch camera.status {
        case .denied:
            messageCard(
                title: "Caméra désactivée",
                message: "Autorise la caméra dans Réglages. Les images restent sur l'iPhone.",
                symbol: "camera.fill"
            )
        case .failed(let message):
            messageCard(
                title: "Analyse indisponible",
                message: message,
                symbol: "exclamationmark.triangle.fill"
            )
        case .idle, .requesting:
            messageCard(
                title: "Préparation",
                message: "Chargement des modèles et ouverture de la caméra…",
                symbol: "sparkles"
            )
        case .running:
            if !camera.detections.isEmpty, let analysis = camera.analysis {
                estimateCard(detections: camera.detections, analysis: analysis)
            } else {
                messageCard(
                    title: "Cherche des nuages",
                    message: "Le garde ciel filtre la scène puis UCloudNet détoure les régions nuageuses.",
                    symbol: "viewfinder"
                )
            }
        }
    }

    private func estimateCard(
        detections: [CloudDetection],
        analysis: CloudFrameAnalysis
    ) -> some View {
        let totalMid = detections.reduce(0) { $0 + $1.estimate.midpointKilograms }
        let totalLow = detections.reduce(0) { $0 + $1.estimate.lowKilograms }
        let totalHigh = detections.reduce(0) { $0 + $1.estimate.highKilograms }
        let averageConfidence = detections.reduce(0) {
            $0 + $1.estimate.confidence
        } / Double(max(1, detections.count))
        let primary = detections[0]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detections.count == 1 ? "1 NUAGE DÉTOURÉ" : "\(detections.count) NUAGES DÉTOURÉS")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.58))
                    Text("Σ ≈ \(massString(totalMid))")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.66)
                        .lineLimit(1)
                }
                Spacer()
                confidenceBadge(averageConfidence)
            }

            HStack(spacing: 8) {
                metric(
                    title: "Fourchette",
                    value: "\(massString(totalLow)) – \(massString(totalHigh))"
                )
                metric(
                    title: "Principal",
                    value: primary.observation.kind.rawValue
                )
                metric(
                    title: "Ciel nuageux",
                    value: "\(Int((analysis.totalCoverage * 100).rounded())) %"
                )
            }

            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                Text("\(analysis.engine.rawValue) · suivi temporel V4 · diagnostic V5 local · masse toujours probabiliste.")
            }
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(17)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 27, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.30), radius: 18, y: 8)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8.3, weight: .black, design: .rounded))
                .tracking(0.65)
                .foregroundStyle(.white.opacity(0.46))
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.56)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            .white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        VStack(spacing: 2) {
            Text("CONFIANCE")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.48))
            Text("\(Int((confidence * 100).rounded())) %")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            .white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
    }

    private func messageCard(
        title: String,
        message: String,
        symbol: String
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.white.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var statusText: String {
        switch camera.status {
        case .running: return "CORE ML · LIVE"
        case .requesting: return "CAMÉRA"
        case .denied: return "BLOQUÉ"
        case .failed: return "ERREUR"
        case .idle: return "PRÊT"
        }
    }

    private var statusColor: Color {
        switch camera.status {
        case .running: return .green
        case .requesting, .idle: return .yellow
        case .denied, .failed: return .red
        }
    }

    private func shortOrientation(_ orientation: String) -> String {
        switch orientation {
        case "portrait": return "PORTRAIT"
        case "portraitUpsideDown": return "P. INV."
        case "landscapeLeft": return "LAND. G"
        case "landscapeRight": return "LAND. D"
        case "faceUp": return "À PLAT ↑"
        case "faceDown": return "À PLAT ↓"
        default: return "?"
        }
    }

    private func massString(_ kilograms: Double) -> String {
        let tonnes = kilograms / 1_000.0
        if tonnes >= 1_000_000 {
            return String(format: "%.1f Mt", tonnes / 1_000_000)
        }
        if tonnes >= 1_000 {
            return String(format: "%.1f kt", tonnes / 1_000)
        }
        if tonnes >= 10 {
            return String(format: "%.0f t", tonnes)
        }
        if tonnes >= 1 {
            return String(format: "%.1f t", tonnes)
        }
        return String(format: "%.0f kg", kilograms)
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
