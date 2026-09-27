import SwiftUI

struct CameraScreenV6: View {
    @StateObject private var camera = CameraService()
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session, device: camera.activeCamera)
                .ignoresSafeArea()
                .opacity(camera.status == .running ? 1 : 0.16)

            if let image = camera.analysis?.overlayImage {
                GeometryReader { proxy in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .opacity(0.90)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [
                    .black.opacity(0.38),
                    .clear,
                    .clear,
                    .black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            labelsOverlay
                .ignoresSafeArea()

            VStack(spacing: 8) {
                compactHeader
                Spacer()
                compactBottomBar
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 7)
        }
        .task {
            camera.requestAndStart()
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Text("CLOUD WEIGHT")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(0.9)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.35), in: Capsule())

            if let telemetry = camera.telemetry {
                Text(String(format: "%.1f Hz · %.0f ms", telemetry.effectiveHz, telemetry.analysisMilliseconds))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.28), in: Capsule())
            }

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(syncColor)
                    .frame(width: 6, height: 6)
                Text(syncLabel)
                    .font(.system(size: 8.5, weight: .black, design: .rounded))
                    .tracking(0.4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.28), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.8))
            .allowsHitTesting(false)
        }
    }

    private var labelsOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(camera.detections.prefix(8)) { detection in
                    cloudLabel(detection)
                        .position(
                            x: clamped(
                                detection.observation.centroid.x * proxy.size.width,
                                lower: 48,
                                upper: max(48, proxy.size.width - 48)
                            ),
                            y: clamped(
                                detection.observation.centroid.y * proxy.size.height,
                                lower: 58,
                                upper: max(58, proxy.size.height - 76)
                            )
                        )
                }

                if camera.status == .running && camera.detections.isEmpty {
                    Circle()
                        .stroke(.white.opacity(0.56), lineWidth: 1)
                        .frame(width: pulse ? 52 : 42, height: pulse ? 52 : 42)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cloudLabel(_ detection: CloudDetection) -> some View {
        let color = trackColor(detection.id)
        return HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("#\(detection.id) \(detection.observation.kind.rawValue.uppercased())")
                .font(.system(size: 7.5, weight: .black, design: .rounded))
                .tracking(0.35)
            Text("≈ \(massString(detection.estimate.midpointKilograms))")
                .font(.system(size: 9.5, weight: .black, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.85), lineWidth: 0.8))
    }

    @ViewBuilder
    private var compactBottomBar: some View {
        if case .failed(let message) = camera.status {
            Text(message)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(.red.opacity(0.72), in: Capsule())
        } else if let telemetry = camera.telemetry {
            HStack(spacing: 10) {
                if camera.detections.isEmpty {
                    Text("AUCUN NUAGE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(0.7)
                } else {
                    let total = camera.detections.reduce(0) { $0 + $1.estimate.midpointKilograms }
                    Text("Σ ≈ \(massString(total))")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("\(camera.detections.count) NUAGE\(camera.detections.count > 1 ? "S" : "")")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer(minLength: 4)

                if telemetry.lowLightMode {
                    Text("LOW LIGHT")
                        .foregroundStyle(.yellow.opacity(0.90))
                }
                Text(String(format: "CIEL %.0f%%", telemetry.skyCoveragePercent))
                Text(String(format: "NUAGE %.0f%%", telemetry.cloudCoveragePercent))
            }
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8))
        }
    }

    private var syncLabel: String {
        switch camera.apiState {
        case .paired: return "SYNC AUTO"
        case .failed: return "SYNC !"
        case .stopped, .ready, .pairing: return "SYNC READY"
        }
    }

    private var syncColor: Color {
        switch camera.apiState {
        case .paired: return .green
        case .failed: return .red
        case .pairing: return .yellow
        case .ready, .stopped: return .white.opacity(0.55)
        }
    }

    private func trackColor(_ id: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.27, green: 0.84, blue: 1.0),
            Color(red: 1.0, green: 0.69, blue: 0.28),
            Color(red: 0.76, green: 0.47, blue: 1.0),
            Color(red: 0.31, green: 0.95, blue: 0.70),
            Color(red: 1.0, green: 0.41, blue: 0.62),
            Color(red: 1.0, green: 0.90, blue: 0.36),
            Color(red: 0.44, green: 0.62, blue: 1.0),
            Color(red: 0.47, green: 0.96, blue: 0.92)
        ]
        return palette[abs(id) % palette.count]
    }

    private func massString(_ kilograms: Double) -> String {
        let tonnes = kilograms / 1_000.0
        if tonnes >= 1_000_000 { return String(format: "%.1f Mt", tonnes / 1_000_000) }
        if tonnes >= 1_000 { return String(format: "%.1f kt", tonnes / 1_000) }
        if tonnes >= 10 { return String(format: "%.0f t", tonnes) }
        if tonnes >= 1 { return String(format: "%.1f t", tonnes) }
        return String(format: "%.0f kg", kilograms)
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
