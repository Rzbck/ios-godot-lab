import SwiftUI

struct CameraScreenV6: View {
    private struct CloudGuide: Identifiable {
        let name: String
        let altitude: String
        let summary: String

        var id: String { name }
    }

    @StateObject private var camera = CameraService()
    @State private var pulse = false
    @State private var showCloudIndex = false

    private let cloudGuides = [
        CloudGuide(
            name: "Cumulus",
            altitude: "Souvent basse altitude",
            summary: "Nuage gonflé aux contours marqués, souvent associé aux mouvements verticaux de l'air."
        ),
        CloudGuide(
            name: "Stratocumulus",
            altitude: "Basse altitude",
            summary: "Grandes masses ou rouleaux arrondis formant souvent une couche discontinue."
        ),
        CloudGuide(
            name: "Stratus",
            altitude: "Très basse altitude",
            summary: "Couche assez uniforme et étendue, parfois proche d'un brouillard élevé."
        ),
        CloudGuide(
            name: "Cirrus",
            altitude: "Haute altitude",
            summary: "Nuages fins et fibreux principalement composés de cristaux de glace."
        )
    ]

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

            if showCloudIndex {
                cloudIndexPanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(20)
            } else {
                cloudIndexHandle
                    .zIndex(20)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 36)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height)
                    else { return }

                    if value.translation.width < -60 {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showCloudIndex = true
                        }
                    } else if value.translation.width > 60 {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showCloudIndex = false
                        }
                    }
                }
        )
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

    private var cloudIndexHandle: some View {
        HStack {
            Spacer()

            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    showCloudIndex = true
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("i")
                        .font(.system(size: 8, weight: .black, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 27, height: 45)
                .background(.black.opacity(0.28), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.12), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 4)
    }

    private var cloudIndexPanel: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 50)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("INDEX NUAGES")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(0.8)

                        Text("Classification indicative")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                            showCloudIndex = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Glisse vers la droite pour revenir à la caméra.")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.50))

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 9) {
                        ForEach(cloudGuides) { guide in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.white.opacity(0.72))

                                    Text(guide.name.uppercased())
                                        .font(.system(
                                            size: 11,
                                            weight: .black,
                                            design: .rounded
                                        ))

                                    Spacer()
                                }

                                Text(guide.altitude)
                                    .font(.system(
                                        size: 8.5,
                                        weight: .bold,
                                        design: .rounded
                                    ))
                                    .foregroundStyle(.white.opacity(0.50))

                                Text(guide.summary)
                                    .font(.system(
                                        size: 9.5,
                                        weight: .medium,
                                        design: .rounded
                                    ))
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(11)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.23), in: RoundedRectangle(
                                cornerRadius: 14,
                                style: .continuous
                            ))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.08), lineWidth: 0.8)
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .frame(width: 292)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.10))
                    .frame(width: 1)
            }
        }
        .ignoresSafeArea()
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

            if !camera.analysisModelsReady {
                Text("IA…")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.60))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.24), in: Capsule())
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
