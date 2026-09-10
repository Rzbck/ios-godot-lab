import MapKit
import SwiftUI

struct LiveTrackerView: View {
    @EnvironmentObject private var tracker: TrackerModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followUser = true

    private let metricColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ZStack {
            liveMap.ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.52), .clear, .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sessionPanel.padding(.horizontal, 12).padding(.bottom, 8)
        }
        .onAppear { tracker.requestLocationPermission() }
        .onChange(of: tracker.route.count) { _, _ in
            guard followUser, let coordinate = tracker.currentCoordinate else { return }
            withAnimation(.easeOut(duration: 0.35)) {
                cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: tracker.isActive ? 650 : 1_400, longitudinalMeters: tracker.isActive ? 650 : 1_400))
            }
        }
    }

    private var liveMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            UserAnnotation()
            if tracker.route.count > 1 {
                MapPolyline(coordinates: tracker.route)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let first = tracker.route.first {
                Annotation("Départ", coordinate: first) {
                    ZStack {
                        Circle().fill(.black.opacity(0.72)).frame(width: 30, height: 30)
                        Image(systemName: "flag.fill").font(.caption.bold()).foregroundStyle(.mint)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
        .overlay(alignment: .trailing) {
            Button {
                followUser = true
                if let coordinate = tracker.currentCoordinate {
                    cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 650, longitudinalMeters: 650))
                }
            } label: {
                Image(systemName: followUser ? "location.fill" : "location")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in followUser = false })
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("WATCH TRACKER").font(.caption.weight(.bold)).tracking(1.4)
                Text(tracker.isActive ? tracker.displayActivity.label.uppercased() : "PRÊT À PARTIR")
                    .font(.title3.weight(.heavy))
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Circle().fill(tracker.watchReachable ? Color.green : Color.orange).frame(width: 8, height: 8)
                Image(systemName: "applewatch")
                Text(tracker.watchReachable ? "SYNC" : "WATCH").font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var sessionPanel: some View {
        Group {
            if tracker.isActive { activePanel } else { readyPanel }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1) }
    }

    private var activePanel: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(tracker.selectedActivity.isAutomatic ? "AUTO" : tracker.displayActivity.label.uppercased())
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                        if tracker.selectedActivity.isAutomatic {
                            Text("· \(tracker.effectiveActivity.label.uppercased())")
                                .font(.caption2.weight(.black)).foregroundStyle(.mint)
                        }
                    }
                    Text(formatDuration(tracker.elapsedSeconds))
                        .font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                }
                Spacer()
                statusPill
            }

            LazyVGrid(columns: metricColumns, spacing: 10) {
                MetricTile(title: "DISTANCE", value: formatDistance(tracker.distanceMeters), unit: tracker.distanceMeters >= 1000 ? "km" : "m", symbol: "point.topleft.down.to.point.bottomright.curvepath")
                MetricTile(title: "VITESSE", value: String(format: "%.1f", tracker.currentSpeedMps * 3.6), unit: "km/h", symbol: "speedometer")
                MetricTile(title: "ALLURE", value: formatPace(tracker.currentSpeedMps), unit: "/km", symbol: tracker.displayActivity.symbol)
                MetricTile(title: "CŒUR", value: tracker.heartRate > 0 ? String(format: "%.0f", tracker.heartRate) : "—", unit: "bpm", symbol: "heart.fill", emphasized: tracker.heartRate > 0)
                MetricTile(title: "ALTITUDE", value: String(format: "%.0f", tracker.altitudeMeters), unit: "m", symbol: "mountain.2.fill")
                MetricTile(title: "DÉNIVELÉ", value: String(format: "+%.0f", tracker.elevationGainMeters), unit: "m", symbol: "arrow.up.right")
            }

            HStack(spacing: 10) {
                Button {
                    tracker.isPaused ? tracker.resumeFromPhone() : tracker.pauseFromPhone()
                } label: {
                    Label(tracker.isPaused ? "Reprendre" : "Pause", systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(tracker.isPaused ? .green : .orange)
                .disabled(tracker.pendingCommand != nil)

                Button(role: .destructive) {
                    tracker.stopFromPhone()
                } label: {
                    Label("Terminer", systemImage: "stop.fill")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracker.pendingCommand != nil)
            }

            Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var readyPanel: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVITÉ").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    Text(tracker.selectedActivity.isAutomatic ? "Auto · marche / course / vélo" : tracker.selectedActivity.label)
                        .font(.headline.weight(.heavy)).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: tracker.selectedActivity.symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(.mint)
            }

            Menu {
                Section("Automatique") {
                    activityButton(.automatic)
                }
                Section("Déplacement") {
                    ForEach([ActivityKind.walking, .running, .hiking, .cycling, .swimming, .rowing, .paddleSports, .crossCountrySkiing, .downhillSkiing, .snowboarding], id: \.self) { activity in
                        activityButton(activity)
                    }
                }
                Section("Fitness et sports Apple") {
                    ForEach(ActivityKind.allCases.filter { ![.automatic, .walking, .running, .hiking, .cycling, .swimming, .rowing, .paddleSports, .crossCountrySkiing, .downhillSkiing, .snowboarding].contains($0) }) { activity in
                        activityButton(activity)
                    }
                }
            } label: {
                HStack {
                    Label(tracker.selectedActivity.label, systemImage: tracker.selectedActivity.symbol)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity).frame(height: 46)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                ReadinessChip(title: "GPS", ready: tracker.horizontalAccuracy >= 0, symbol: "location.fill")
                ReadinessChip(title: "WATCH", ready: tracker.watchReachable, symbol: "applewatch")
                ReadinessChip(title: "SANTÉ", ready: tracker.healthAuthorized, symbol: "heart.text.square.fill")
            }

            Button { tracker.startFromPhone() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("DÉMARRER · \(tracker.selectedActivity.label.uppercased())")
                }
                .font(.headline.weight(.bold)).frame(maxWidth: .infinity).frame(height: 58)
            }
            .buttonStyle(.borderedProminent).tint(.green)

            if let summary = tracker.lastSummary {
                HStack {
                    Label(ActivityKind(rawValue: summary.activity)?.label ?? summary.activity, systemImage: "checkmark.circle.fill")
                    Spacer()
                    Text("\(formatDistance(summary.distanceMeters)) · \(formatDuration(summary.duration))").monospacedDigit()
                }
                .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(tracker.statusMessage).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(role: .destructive) { tracker.deleteAllTestData() } label: {
                Label("EFFACER LES DONNÉES DE TEST", systemImage: "trash.fill")
                    .font(.caption.weight(.bold)).frame(maxWidth: .infinity).frame(height: 38)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func activityButton(_ activity: ActivityKind) -> some View {
        Button {
            tracker.selectActivity(activity)
        } label: {
            Label(activity.label, systemImage: activity.symbol)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(tracker.isPaused ? Color.orange : Color.green).frame(width: 8, height: 8)
            Text(tracker.isPaused ? "PAUSE" : "WATCH").font(.caption2.weight(.black))
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.white.opacity(0.10), in: Capsule())
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f", meters / 1000) : String(format: "%.0f", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }

    private func formatPace(_ speed: Double) -> String {
        guard speed > 0.25 else { return "—" }
        let secondsPerKm = Int(1000 / speed)
        return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) { Image(systemName: symbol); Text(title) }
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(emphasized ? Color.red : Color.primary).minimumScaleFactor(0.7).lineLimit(1)
            Text(unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ReadinessChip: View {
    let title: String
    let ready: Bool
    let symbol: String

    var body: some View {
        HStack(spacing: 5) { Image(systemName: symbol); Text(title).font(.caption2.weight(.bold)) }
            .foregroundStyle(ready ? Color.green : Color.secondary)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(.white.opacity(0.07), in: Capsule())
    }
}
