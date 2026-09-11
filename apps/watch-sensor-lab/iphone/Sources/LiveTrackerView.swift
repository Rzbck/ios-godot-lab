import MapKit
import SwiftUI

struct LiveTrackerView: View {
    @EnvironmentObject private var tracker: TrackerModel
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followUser = true
    @State private var showHistory = false

    var body: some View {
        ZStack {
            liveMap.ignoresSafeArea()
            LinearGradient(
                colors: [.black.opacity(0.40), .clear, .black.opacity(0.22)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 7)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            sessionPanel
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .sheet(isPresented: $showHistory) {
            ActivityHistoryView()
        }
        .onAppear { tracker.requestLocationPermission() }
        .onChange(of: tracker.route.count) { _, _ in
            guard followUser, let coordinate = tracker.currentCoordinate else { return }
            withAnimation(.easeOut(duration: 0.30)) {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: tracker.isActive ? 700 : 1_400,
                        longitudinalMeters: tracker.isActive ? 700 : 1_400
                    )
                )
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
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: coordinate,
                            latitudinalMeters: 700,
                            longitudinalMeters: 700
                        )
                    )
                }
            } label: {
                Image(systemName: followUser ? "location.fill" : "location")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { _ in followUser = false })
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("WATCH TRACKER")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                Text(tracker.isActive ? tracker.displayActivity.label.uppercased() : "PRÊT")
                    .font(.headline.weight(.heavy))
            }
            Spacer(minLength: 6)

            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Historique des activités")
        }
        .foregroundStyle(.white)
    }

    private var sessionPanel: some View {
        Group {
            if tracker.isActive { activePanel } else { readyPanel }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    private var activePanel: some View {
        VStack(spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Text(tracker.selectedActivity.isAutomatic ? "AUTO" : tracker.displayActivity.label.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                        if tracker.selectedActivity.isAutomatic {
                            Text("· \(tracker.effectiveActivity.label.uppercased())")
                                .font(.caption2.weight(.black))
                                .foregroundStyle(.mint)
                        }
                    }
                    Text(formatDuration(tracker.elapsedSeconds))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                activityStatePill
            }

            compactReadiness

            if tracker.elapsedSeconds < 6 || !tracker.gpsSettled || tracker.heartRate <= 0 {
                acquisitionLine
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CompactMetricCard(
                        title: "DISTANCE",
                        value: tracker.elapsedSeconds >= 5 ? formatDistance(tracker.distanceMeters) : "—",
                        unit: tracker.distanceMeters >= 1000 ? "km" : "m",
                        symbol: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                    CompactMetricCard(
                        title: "VITESSE",
                        value: tracker.gpsSettled ? String(format: "%.1f", tracker.currentSpeedMps * 3.6) : "—",
                        unit: "km/h",
                        symbol: "speedometer"
                    )
                    CompactMetricCard(
                        title: "ALLURE",
                        value: tracker.gpsSettled ? formatPace(tracker.currentSpeedMps) : "—",
                        unit: "/km",
                        symbol: tracker.displayActivity.symbol
                    )
                    CompactMetricCard(
                        title: "CŒUR",
                        value: tracker.heartRate > 0 ? String(format: "%.0f", tracker.heartRate) : "—",
                        unit: "bpm",
                        symbol: "heart.fill",
                        emphasized: tracker.heartRate > 0
                    )
                    CompactMetricCard(
                        title: "CALORIES",
                        value: tracker.activeEnergyKcal > 0 ? String(format: "%.0f", tracker.activeEnergyKcal) : "—",
                        unit: "kcal",
                        symbol: "flame.fill"
                    )
                    CompactMetricCard(
                        title: "CADENCE",
                        value: tracker.cadenceSPM > 0 ? String(format: "%.0f", tracker.cadenceSPM) : "—",
                        unit: "pas/min",
                        symbol: "metronome.fill"
                    )
                    CompactMetricCard(
                        title: "ALTITUDE",
                        value: tracker.elapsedSeconds >= 5 && abs(tracker.altitudeMeters) > 0.5 ? String(format: "%.0f", tracker.altitudeMeters) : "—",
                        unit: "m",
                        symbol: "mountain.2.fill"
                    )
                    CompactMetricCard(
                        title: "DÉNIVELÉ",
                        value: tracker.elapsedSeconds >= 5 ? String(format: "+%.0f", tracker.elevationGainMeters) : "—",
                        unit: "m",
                        symbol: "arrow.up.right"
                    )
                    CompactMetricCard(
                        title: "PAS",
                        value: tracker.steps > 0 ? "\(tracker.steps)" : "—",
                        unit: "pas",
                        symbol: "shoeprints.fill"
                    )
                }
                .padding(.horizontal, 1)
            }

            weatherLine

            HStack(spacing: 9) {
                Button {
                    tracker.isPaused ? tracker.workflowResume() : tracker.workflowPause()
                } label: {
                    Label(
                        tracker.isPaused ? "Reprendre" : "Pause",
                        systemImage: tracker.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(tracker.isPaused ? .green : .orange)
                .disabled(tracker.pendingCommand != nil)

                Button(role: .destructive) {
                    tracker.workflowFinish(
                    disposition: .preserveDetectedSegments,
                    finalActivity: nil
                )
                } label: {
                    Label("Terminer", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(tracker.pendingCommand != nil)
            }

            Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
    }

    private var readyPanel: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACTIVITÉ")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(tracker.selectedActivity.isAutomatic ? "Auto · marche / course / vélo" : tracker.selectedActivity.label)
                        .font(.headline.weight(.heavy))
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: tracker.selectedActivity.symbol)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.mint)
            }

            Menu {
                Section("Automatique") {
                    activityButton(.automatic)
                }
                Section("Multisport") {
                    activityButton(.swimBikeRun)
                }
                Section("Déplacement") {
                    ForEach(
                        [ActivityKind.walking, .running, .hiking, .cycling, .swimming, .rowing, .paddleSports, .crossCountrySkiing, .downhillSkiing, .snowboarding],
                        id: \.self
                    ) { activity in
                        activityButton(activity)
                    }
                }
                Section("Autres sports Apple") {
                    ForEach(
                        ActivityKind.allCases.filter {
                            ![.automatic, .swimBikeRun, .walking, .running, .hiking, .cycling, .swimming, .rowing, .paddleSports, .crossCountrySkiing, .downhillSkiing, .snowboarding].contains($0)
                        }
                    ) { activity in
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
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .padding(.horizontal, 11)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)

            compactReadiness

            Toggle(
                isOn: Binding(
                    get: { tracker.autoPauseEnabled },
                    set: { tracker.workflowSetAutoPauseEnabled($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pause automatique").font(.subheadline.weight(.semibold))
                    Text("Détection adaptée au sport · pause manuelle prioritaire")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.mint)

            Button { tracker.workflowStart() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("DÉMARRER · \(tracker.selectedActivity.label.uppercased())")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            if let summary = tracker.lastSummary {
                Button { showHistory = true } label: {
                    HStack {
                        Label(ActivityKind(rawValue: summary.activity)?.label ?? summary.activity, systemImage: "checkmark.circle.fill")
                        Spacer()
                        Text("\(formatDistance(summary.distanceMeters)) · \(formatDuration(summary.duration))")
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            } else {
                Text(tracker.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Les activités terminées sont conservées dans Historique après les mises à jour de l’app.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var compactReadiness: some View {
        HStack(spacing: 5) {
            CompactReadinessChip(title: "GPS", ready: tracker.horizontalAccuracy >= 0, symbol: "location.fill")
            CompactReadinessChip(title: "WATCH", ready: tracker.watchReachable, symbol: "applewatch")
            CompactReadinessChip(title: "SANTÉ", ready: tracker.healthAuthorized, symbol: "heart.text.square.fill")
        }
    }

    private var acquisitionLine: some View {
        HStack(spacing: 10) {
            if !tracker.gpsSettled {
                Label("GPS en acquisition", systemImage: "location.magnifyingglass")
            }
            if tracker.heartRate <= 0 {
                Label("Cardio en acquisition", systemImage: "heart")
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weatherLine: some View {
        if let weather = tracker.currentWeather {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: "cloud.sun.fill").foregroundStyle(.cyan)
                    if let temperature = weather.temperatureC {
                        Text(String(format: "%.1f °C", temperature)).fontWeight(.bold)
                    }
                    if let apparent = weather.apparentTemperatureC {
                        Text("ress. \(String(format: "%.1f°", apparent))")
                    }
                    if let wind = weather.windSpeedKPH {
                        Text("vent \(String(format: "%.0f", wind)) km/h")
                    }
                    if let direction = weather.windDirectionDegrees {
                        Text("de \(compassDirection(direction))")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let gust = weather.windGustKPH {
                            LiveWeatherChip(symbol: "wind", text: "Raf. \(String(format: "%.0f", gust)) km/h")
                        }
                        if let humidity = weather.relativeHumidityPercent {
                            LiveWeatherChip(symbol: "humidity.fill", text: "\(Int(humidity.rounded())) %")
                        }
                        if let pressure = weather.pressureHPA {
                            LiveWeatherChip(symbol: "gauge.with.dots.needle.50percent", text: "\(Int(pressure.rounded())) hPa")
                        }
                        if let direction = weather.windDirectionDegrees {
                            LiveWeatherChip(symbol: "location.north.fill", text: "\(Int(direction.rounded()))°")
                        }
                        if let component = liveHeadwindComponent(weather: weather) {
                            LiveWeatherChip(
                                symbol: component >= 0 ? "arrow.down" : "arrow.up",
                                text: component >= 0
                                    ? "Face \(String(format: "%.0f", component)) km/h"
                                    : "Arrière \(String(format: "%.0f", abs(component))) km/h"
                            )
                        }
                    }
                }
            }
        } else if tracker.elapsedSeconds > 5 {
            HStack(spacing: 6) {
                Image(systemName: "cloud")
                Text("Contexte météo en acquisition…")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func activityButton(_ activity: ActivityKind) -> some View {
        Button { tracker.workflowSelectActivity(activity) } label: {
            Label(activity.label, systemImage: activity.symbol)
        }
    }

    private var activityStatePill: some View {
        HStack(spacing: 5) {
            Circle().fill(tracker.isPaused ? Color.orange : Color.green).frame(width: 7, height: 7)
            Text(tracker.isPaused ? "PAUSE" : "ACTIF")
                .font(.caption2.weight(.black))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.white.opacity(0.10), in: Capsule())
    }

    private func liveHeadwindComponent(weather: SessionWeatherSnapshot) -> Double? {
        guard let windSpeed = weather.windSpeedKPH,
              let windFrom = weather.windDirectionDegrees,
              tracker.route.count >= 2 else { return nil }
        let from = tracker.route[tracker.route.count - 2]
        let to = tracker.route[tracker.route.count - 1]
        let heading = bearing(from: from, to: to)
        var delta = (heading - windFrom).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return windSpeed * cos(delta * .pi / 180)
    }

    private func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func compassDirection(_ degrees: Double) -> String {
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let labels = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
        let index = Int((normalized + 22.5) / 45.0) % labels.count
        return labels[index]
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

private struct CompactMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var emphasized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(emphasized ? Color.red : Color.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(unit).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(width: 104, alignment: .leading)
        .padding(9)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CompactReadinessChip: View {
    let title: String
    let ready: Bool
    let symbol: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(title).font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(ready ? Color.green : Color.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

private struct LiveWeatherChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.white.opacity(0.06), in: Capsule())
    }
}
