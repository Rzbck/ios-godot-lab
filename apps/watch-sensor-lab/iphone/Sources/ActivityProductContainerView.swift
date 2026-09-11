import MapKit
import SwiftUI

struct ActivityProductContainerView: View {
    @EnvironmentObject private var tracker: TrackerModel

    var body: some View {
        if tracker.isActive {
            LiveActivityProductView()
        } else {
            ActivityExperienceView()
        }
    }
}

private struct LiveActivityProductView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case summary = "Résumé"
        case cardio = "Cardio"
        case map = "Carte"
        case terrain = "Terrain"
        case conditions = "Conditions"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .summary: return "gauge.with.dots.needle.67percent"
            case .cardio: return "heart.fill"
            case .map: return "map.fill"
            case .terrain: return "mountain.2.fill"
            case .conditions: return "cloud.sun.fill"
            }
        }
    }

    @EnvironmentObject private var tracker: TrackerModel
    @AppStorage("tracker.map.style") private var mapStyleRaw = TrackerMapStyleChoice.standard.rawValue
    @State private var page: Page = .summary
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followUser = true
    @State private var confirmStop = false

    private var selectedMapStyle: TrackerMapStyleChoice { TrackerMapStyleChoice(rawValue: mapStyleRaw) ?? .standard }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 7)
                    .padding(.bottom, 8)

                pageSelector
                    .padding(.bottom, 8)

                TabView(selection: $page) {
                    summaryPage.tag(Page.summary)
                    cardioPage.tag(Page.cardio)
                    mapPage.tag(Page.map)
                    terrainPage.tag(Page.terrain)
                    conditionsPage.tag(Page.conditions)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
                    .padding(.horizontal, 14)
                    .padding(.top, 9)
                    .padding(.bottom, 7)
                    .background(.ultraThinMaterial)
            }
            .confirmationDialog(
                "Terminer la séance ?",
                isPresented: $confirmStop,
                titleVisibility: .visible
            ) {
                Button("Terminer", role: .destructive) { tracker.stopFromPhone() }
                Button("Annuler", role: .cancel) { }
            }
            .onAppear {
                tracker.requestLocationPermission()
                recenterMap(animated: false)
            }
            .onChange(of: page) { _, newValue in
                if newValue == .map { recenterMap(animated: false) }
            }
            .onChange(of: tracker.route.count) { _, _ in
                guard page == .map, followUser else { return }
                recenterMap(animated: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tracker.isPaused ? Color.orange : Color.mint)
                        .frame(width: 8, height: 8)
                    Text(tracker.isPaused ? "EN PAUSE" : "EN COURS")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.secondary)
                    if tracker.selectedActivity.isAutomatic {
                        Text("AUTO")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.cyan)
                    }
                }
                HStack(spacing: 6) {
                    Image(systemName: tracker.displayActivity.symbol)
                        .foregroundStyle(activityAccent)
                    Text(tracker.displayActivity.label)
                        .font(.headline.weight(.black))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(productDuration(tracker.elapsedSeconds))
                .font(.system(size: 26, weight: .black, design: .rounded))
                .monospacedDigit()
        }
    }

    private var pageSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(availablePages) { candidate in
                    Button {
                        withAnimation(.snappy) { page = candidate }
                    } label: {
                        Label(candidate.rawValue, systemImage: candidate.symbol)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(page == candidate ? Color.black : Color.primary)
                            .padding(.horizontal, 11)
                            .frame(height: 34)
                            .background(page == candidate ? activityAccent : Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var availablePages: [Page] {
        var values: [Page] = [.summary, .cardio]
        if shouldShowMap { values.append(.map) }
        if shouldShowTerrain { values.append(.terrain) }
        values.append(.conditions)
        return values
    }

    private var summaryPage: some View {
        VStack(spacing: 11) {
            NavigationLink {
                LiveMetricDepthView(
                    title: primaryMetricTitle,
                    value: primaryMetricValue,
                    symbol: tracker.displayActivity.symbol,
                    accent: activityAccent,
                    lines: [
                        ("Temps", productDuration(tracker.elapsedSeconds)),
                        (paceOrSpeedTitle, paceOrSpeedValue),
                        ("GPS", gpsValue),
                    ]
                )
            } label: {
                LiveProductHero(title: primaryMetricTitle, value: primaryMetricValue, symbol: tracker.displayActivity.symbol, accent: activityAccent)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                NavigationLink {
                    LiveMetricDepthView(
                        title: "Fréquence cardiaque",
                        value: tracker.heartRate > 0 ? "\(Int(tracker.heartRate.rounded())) bpm" : "—",
                        symbol: "heart.fill",
                        accent: .pink,
                        lines: [
                            ("Moyenne", tracker.averageHeartRate > 0 ? "\(Int(tracker.averageHeartRate.rounded())) bpm" : "—"),
                            ("Énergie", tracker.activeEnergyKcal > 0 ? "\(Int(tracker.activeEnergyKcal.rounded())) kcal" : "—"),
                        ]
                    )
                } label: {
                    LiveProductTile(title: "CŒUR", value: tracker.heartRate > 0 ? "\(Int(tracker.heartRate.rounded()))" : "—", unit: "bpm", symbol: "heart.fill", accent: .pink, disclosure: true)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    LiveMetricDepthView(
                        title: paceOrSpeedTitle.capitalized,
                        value: paceOrSpeedValueWithUnit,
                        symbol: "speedometer",
                        accent: .cyan,
                        lines: [
                            ("Distance", productDistance(tracker.distanceMeters)),
                            ("Cadence", tracker.cadenceSPM > 0 ? "\(Int(tracker.cadenceSPM.rounded()))" : "—"),
                        ]
                    )
                } label: {
                    LiveProductTile(title: paceOrSpeedTitle, value: paceOrSpeedValue, unit: paceOrSpeedUnit, symbol: "speedometer", accent: .cyan, disclosure: true)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                LiveProductTile(title: "ÉNERGIE", value: tracker.activeEnergyKcal > 0 ? "\(Int(tracker.activeEnergyKcal.rounded()))" : "—", unit: "kcal", symbol: "flame.fill", accent: .orange)
                LiveProductTile(title: "D+", value: tracker.elapsedSeconds > 4 ? "+\(Int(tracker.elevationGainMeters.rounded()))" : "—", unit: "m", symbol: "mountain.2.fill", accent: .mint)
            }

            if tracker.selectedActivity.isAutomatic {
                HStack {
                    Label("Détection", systemImage: "wand.and.stars")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(tracker.effectiveActivity.label)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(.cyan.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var cardioPage: some View {
        VStack(spacing: 12) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CARDIO")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.pink)
                    Text(tracker.heartRate > 0 ? "\(Int(tracker.heartRate.rounded()))" : "—")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text("bpm actuel")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "heart.fill")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(.pink)
            }

            HStack(spacing: 10) {
                LiveProductTile(title: "MOYENNE", value: tracker.averageHeartRate > 0 ? "\(Int(tracker.averageHeartRate.rounded()))" : "—", unit: "bpm", symbol: "heart.text.square.fill", accent: .red)
                LiveProductTile(title: "ÉNERGIE", value: tracker.activeEnergyKcal > 0 ? "\(Int(tracker.activeEnergyKcal.rounded()))" : "—", unit: "kcal", symbol: "flame.fill", accent: .orange)
            }

            HStack(spacing: 10) {
                LiveProductTile(title: "CADENCE", value: tracker.cadenceSPM > 0 ? "\(Int(tracker.cadenceSPM.rounded()))" : "—", unit: cadenceUnit, symbol: "metronome.fill", accent: .cyan)
                LiveProductTile(title: "PAS", value: tracker.steps > 0 ? "\(tracker.steps)" : "—", unit: "pas", symbol: "shoeprints.fill", accent: .mint)
            }

            Text("Les zones cardio et l’effort 1–10 sont consolidés après la séance à partir des échantillons enregistrés.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var mapPage: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            UserAnnotation()
            if tracker.route.count > 1 {
                MapPolyline(coordinates: tracker.route)
                    .stroke(activityAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if let first = tracker.route.first {
                Annotation("Départ", coordinate: first) {
                    Image(systemName: "flag.fill")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .background(.black.opacity(0.72), in: Circle())
                        .foregroundStyle(.mint)
                }
            }
        }
        .mapStyle(selectedMapStyle.mapStyle)
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .topTrailing) {
            TrackerMapStyleMenu(
                selection: Binding(
                    get: { selectedMapStyle },
                    set: { mapStyleRaw = $0.rawValue }
                )
            )
            .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            Button { recenterMap(animated: true) } label: {
                Image(systemName: followUser ? "location.fill" : "location")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 46, height: 46)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { _ in followUser = false }
        )
    }

    private var terrainPage: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TERRAIN")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.mint)
                    Text("Relief en direct")
                        .font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: "mountain.2.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.mint)
            }

            HStack(spacing: 10) {
                LiveProductTile(title: "ALTITUDE", value: tracker.elapsedSeconds > 4 ? "\(Int(tracker.altitudeMeters.rounded()))" : "—", unit: "m", symbol: "mountain.2.fill", accent: .mint)
                LiveProductTile(title: "MONTÉE", value: tracker.elapsedSeconds > 4 ? "+\(Int(tracker.elevationGainMeters.rounded()))" : "—", unit: "m", symbol: "arrow.up.right", accent: .green)
            }
            HStack(spacing: 10) {
                LiveProductTile(title: "DESCENTE", value: tracker.elapsedSeconds > 4 ? "-\(Int(tracker.elevationLossMeters.rounded()))" : "—", unit: "m", symbol: "arrow.down.right", accent: .blue)
                LiveProductTile(title: "GPS", value: tracker.horizontalAccuracy >= 0 ? "±\(Int(tracker.horizontalAccuracy.rounded()))" : "—", unit: "m", symbol: "location.fill", accent: gpsAccent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("SURFACE")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Text("Non déterminée en direct")
                    .font(.headline.weight(.bold))
                Text("Route / sentier / gravier ne sera affiché que lorsqu’une vraie source cartographique permet de le déterminer de façon fiable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var conditionsPage: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONDITIONS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.yellow)
                    Text("Contexte de la séance")
                        .font(.title3.weight(.black))
                }
                Spacer()
                Image(systemName: "cloud.sun.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.yellow)
            }

            if let weather = tracker.currentWeather {
                HStack(spacing: 10) {
                    LiveProductTile(title: "TEMP.", value: weather.temperatureC.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", symbol: "thermometer.medium", accent: .orange)
                    LiveProductTile(title: "RESSENTI", value: weather.apparentTemperatureC.map { String(format: "%.1f", $0) } ?? "—", unit: "°C", symbol: "thermometer.sun.fill", accent: .yellow)
                }
                HStack(spacing: 10) {
                    LiveProductTile(title: "VENT", value: weather.windSpeedKPH.map { "\(Int($0.rounded()))" } ?? "—", unit: "km/h", symbol: "wind", accent: .cyan)
                    LiveProductTile(title: "HUMIDITÉ", value: weather.relativeHumidityPercent.map { "\(Int($0.rounded()))" } ?? "—", unit: "%", symbol: "humidity.fill", accent: .blue)
                }
            } else {
                ContentUnavailableView(
                    "Contexte météo en attente",
                    systemImage: "cloud.sun",
                    description: Text("Les conditions apparaissent quand un snapshot météo exploitable est disponible.")
                )
            }

            Toggle(
                isOn: Binding(
                    get: { tracker.autoPauseEnabled },
                    set: { tracker.setAutoPauseEnabled($0) }
                )
            ) {
                Label("Pause automatique", systemImage: "pause.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(.mint)
            .padding(12)
            .background(
                .white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("ÉTAT")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var controls: some View {
        HStack(spacing: 9) {
            Button {
                tracker.isPaused ? tracker.resumeFromPhone() : tracker.pauseFromPhone()
            } label: {
                Label(tracker.isPaused ? "Reprendre" : "Pause", systemImage: tracker.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .tint(tracker.isPaused ? .green : .orange)
            .disabled(tracker.pendingCommand != nil)

            Button(role: .destructive) { confirmStop = true } label: {
                Label("Terminer", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracker.pendingCommand != nil)
        }
    }

    private var primaryMetricTitle: String {
        switch tracker.displayActivity {
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining, .crossTraining, .highIntensityIntervalTraining, .yoga, .mindAndBody, .pilates, .taiChi:
            return "TEMPS ACTIF"
        default:
            return "DISTANCE"
        }
    }

    private var primaryMetricValue: String {
        primaryMetricTitle == "TEMPS ACTIF" ? productDuration(tracker.elapsedSeconds) : productDistance(tracker.distanceMeters)
    }

    private var paceOrSpeedTitle: String {
        switch tracker.displayActivity {
        case .walking, .running, .hiking: return "ALLURE"
        default: return "VITESSE"
        }
    }

    private var paceOrSpeedValue: String {
        guard tracker.gpsSettled else { return "—" }
        switch tracker.displayActivity {
        case .walking, .running, .hiking: return productPace(tracker.currentSpeedMps)
        default: return String(format: "%.1f", tracker.currentSpeedMps * 3.6)
        }
    }

    private var paceOrSpeedUnit: String {
        switch tracker.displayActivity {
        case .walking, .running, .hiking: return "/km"
        default: return "km/h"
        }
    }

    private var paceOrSpeedValueWithUnit: String {
        paceOrSpeedValue == "—" ? "—" : "\(paceOrSpeedValue) \(paceOrSpeedUnit)"
    }

    private var cadenceUnit: String {
        switch tracker.displayActivity {
        case .cycling, .handCycling: return "cadence"
        default: return "pas/min"
        }
    }

    private var gpsValue: String {
        tracker.horizontalAccuracy >= 0 ? "±\(Int(tracker.horizontalAccuracy.rounded())) m" : "Acquisition…"
    }

    private var gpsAccent: Color {
        guard tracker.horizontalAccuracy >= 0 else { return .orange }
        if tracker.horizontalAccuracy < 8 { return .mint }
        if tracker.horizontalAccuracy < 20 { return .yellow }
        return .orange
    }

    private var shouldShowMap: Bool {
        switch tracker.displayActivity {
        case .walking, .running, .hiking, .cycling, .handCycling, .swimBikeRun,
             .crossCountrySkiing, .downhillSkiing, .snowSports, .snowboarding,
             .skatingSports, .wheelchairWalkPace, .wheelchairRunPace,
             .rowing, .paddleSports, .sailing, .surfingSports, .swimming:
            return true
        default:
            return tracker.route.count > 2
        }
    }

    private var shouldShowTerrain: Bool {
        shouldShowMap || tracker.elevationGainMeters > 0 || tracker.elevationLossMeters > 0
    }

    private var activityAccent: Color {
        switch tracker.displayActivity {
        case .walking, .hiking: return .mint
        case .running, .trackAndField: return .orange
        case .cycling, .handCycling: return .yellow
        case .swimming, .rowing, .paddleSports, .sailing, .surfingSports, .waterSports, .waterFitness, .waterPolo, .underwaterDiving: return .blue
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining, .crossTraining, .highIntensityIntervalTraining: return .red
        case .yoga, .mindAndBody, .pilates, .taiChi, .flexibility: return .purple
        default: return .cyan
        }
    }

    private func recenterMap(animated: Bool) {
        followUser = true
        tracker.requestLocationPermission()
        let update = {
            if let coordinate = tracker.currentCoordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 650, longitudinalMeters: 650)
                )
            } else {
                cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            }
        }
        if animated { withAnimation(.easeOut(duration: 0.28), update) } else { update() }
    }
}

private struct LiveProductHero: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            Text(value)
                .font(.system(size: 42, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .padding(16)
        .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct LiveProductTile: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let accent: Color
    var disclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if disclosure {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(size: 25, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.62)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(12)
        .background(accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }
}

private struct LiveMetricDepthView: View {
    let title: String
    let value: String
    let symbol: String
    let accent: Color
    let lines: [(String, String)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(accent)
                    Text(value)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Text(title)
                        .font(.headline.weight(.bold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(17)
                .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                ForEach(Array(lines.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(item.1).fontWeight(.bold).monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(13)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(16)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func productDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}

private func productDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func productPace(_ speedMps: Double) -> String {
    guard speedMps > 0.2 else { return "—" }
    let secondsPerKm = Int(1000 / speedMps)
    return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
}
