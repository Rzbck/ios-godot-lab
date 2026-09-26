import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraService()
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .opacity(camera.status == .running ? 1 : 0.15)

            LinearGradient(
                colors: [Color.black.opacity(0.58), .clear, Color.black.opacity(0.18), Color.black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            detectionOverlay

            VStack(spacing: 0) {
                header
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 18)
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
        .animation(.snappy(duration: 0.28), value: camera.analysis?.bounds)
        .animation(.easeInOut(duration: 0.25), value: camera.estimate)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("CLOUD WEIGHT")
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .tracking(1.3)
                Text("pèse le ciel, à peu près")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.8), radius: 5)
                Text(statusText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
        }
    }

    @ViewBuilder
    private var detectionOverlay: some View {
        GeometryReader { proxy in
            if let analysis = camera.analysis, camera.estimate != nil {
                let rect = CGRect(
                    x: analysis.bounds.minX * proxy.size.width,
                    y: analysis.bounds.minY * proxy.size.height,
                    width: analysis.bounds.width * proxy.size.width,
                    height: analysis.bounds.height * proxy.size.height
                )

                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(.white.opacity(0.88), style: StrokeStyle(lineWidth: 1.4, dash: [8, 7]))
                        .frame(width: max(72, rect.width), height: max(54, rect.height))
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.5), radius: 6)

                    Circle()
                        .fill(.white)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                        .position(x: rect.midX, y: rect.midY)

                    Text(analysis.kind.rawValue.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.56), in: Capsule())
                        .position(x: rect.midX, y: max(52, rect.minY - 18))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else if camera.status == .running {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.20), lineWidth: 1)
                        .frame(width: pulse ? 126 : 104, height: pulse ? 126 : 104)
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1.5)
                        .frame(width: 62, height: 62)
                    Rectangle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 18, height: 1)
                    Rectangle()
                        .fill(.white.opacity(0.8))
                        .frame(width: 1, height: 18)
                }
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.43)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bottomPanel: some View {
        switch camera.status {
        case .denied:
            messageCard(
                title: "Caméra désactivée",
                message: "Autorise la caméra dans Réglages pour viser un nuage. Les images restent sur l'iPhone.",
                symbol: "camera.fill"
            )
        case .failed(let message):
            messageCard(title: "Caméra indisponible", message: message, symbol: "exclamationmark.triangle.fill")
        case .idle, .requesting:
            messageCard(title: "Préparation", message: "Ouverture de la caméra…", symbol: "sparkles")
        case .running:
            if let estimate = camera.estimate, let analysis = camera.analysis {
                estimateCard(estimate: estimate, analysis: analysis)
            } else {
                messageCard(
                    title: "Vise un nuage",
                    message: "L'analyse tourne automatiquement sur l'iPhone. Aucun bouton, aucun upload.",
                    symbol: "viewfinder"
                )
            }
        }
    }

    private func estimateCard(estimate: CloudMassEstimate, analysis: CloudFrameAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MASSE D'EAU ESTIMÉE")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.58))
                    Text("≈ \(massString(estimate.midpointKilograms))")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                confidenceBadge(estimate.confidence)
            }

            HStack(spacing: 10) {
                metric(title: "Fourchette", value: "\(massString(estimate.lowKilograms)) – \(massString(estimate.highKilograms))")
                metric(title: "Largeur", value: distanceString(estimate.estimatedWidthMeters))
                metric(title: "Cadre", value: "\(Int((analysis.coverage * 100).rounded())) %")
            }

            HStack(spacing: 7) {
                Image(systemName: "info.circle.fill")
                Text("Estimation pédagogique : distance, profondeur et teneur en eau sont inférées. La fourchette compte plus que le chiffre central.")
            }
            .font(.system(size: 10.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .black, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.46))
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func messageCard(title: String, message: String, symbol: String) -> some View {
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var statusText: String {
        switch camera.status {
        case .running: return "LOCAL · LIVE"
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

    private func distanceString(_ meters: Double) -> String {
        if meters >= 1_000 {
            return String(format: "%.1f km", meters / 1_000)
        }
        return String(format: "%.0f m", meters)
    }
}
