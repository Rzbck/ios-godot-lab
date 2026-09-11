import MapKit
import SwiftUI

struct ActivityExperienceView: View {
    @EnvironmentObject private var tracker: TrackerModel

    var body: some View {
        Group {
            if tracker.isActive {
                LiveActivityExperienceView()
            } else {
                IdleActivityExperienceView()
            }
        }
    }
}

private struct IdleActivityExperienceView: View {
    @EnvironmentObject private var tracker: TrackerModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    launcherCard
                    readinessCard
                    quickSettingsCard
                }
                .padding(16)
                .padding(.bottom, 20)
            }
            .navigationTitle("Activité")
            .onAppear { tracker.requestLocationPermission() }
        }
    }

    private var launcherCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRÊT À DÉMARRER")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Text(tracker.selectedActivity.label)
                        .font(.title.weight(.bold))
                    if tracker.selectedActivity.isAutomatic {
                        Text("Auto laisse la Watch identifier prudemment marche, course ou vélo. La randonnée reste un choix manuel tant qu’aucune source de terrain fiable ne la confirme.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: tracker.selectedActivity.symbol)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.mint)
            }

            Menu {
                Section("Recommandé") {
                    activityButton(.automatic)
                    activityButton(.walking)
                    activityButton(.running)
                    activityButton(.cycling)
                    activityButton(.hiking)
                    activityButton(.swimBikeRun)
                }
                Section("Tous les sports") {
                    ForEach(ActivityKind.allCases.filter {
                        ![.automatic, .walking, .running, .cycling, .hiking, .swimBikeRun].contains($0)
                    }) { activity in
                        activityButton(activity)
                    }
                }
            } label: {
                HStack {
                    Label(tracker.selectedActivity.label, systemImage: tracker.selectedActivity.symbol)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }
                .font(.headline)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button { tracker.workflowStart() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                    Text("DÉMARRER")
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(tracker.pendingCommand != nil)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PRÉPARATION", systemImage: "checkmark.circle")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ActivityReadinessPill(title: "Watch", ready: tracker.watchReachable, symbol: "applewatch")
                ActivityReadinessPill(title: "GPS", ready: tracker.horizontalAccuracy >= 0, symbol: "location.fill")
                ActivityReadinessPill(title: "Santé", ready: tracker.healthAuthorized, symbol: "heart.text.square.fill")
            }

            Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var quickSettingsCard: some View {
        Toggle(
            isOn: Binding(
                get: { tracker.autoPauseEnabled },
                set: { tracker.workflowSetAutoPauseEnabled($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pause automatique").font(.headline)
                Text("Réglage rapide synchronisé avec la Watch. Les options avancées restent côté iPhone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.mint)
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func activityButton(_ activity: ActivityKind) -> some View {
        Button { tracker.workflowSelectActivity(activity) } label: {
            Label(activity.label, systemImage: activity.symbol)
        }
    }
}

private struct LiveActivityExperienceView: View {
    enum Section: String, CaseIterable, Identifiable {
        case summary = "Résumé"
        case map = "Carte"
        case details = "Détails"
        var id: String { rawValue }
    }

    @EnvironmentObject private var tracker: TrackerModel
    @State private var section: Section = .summary
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followUser = true
    @State private var showFinishReview = false
    @State private var finishActivity: ActivityKind = .walking

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                liveHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)

                Picker("Vue activité", selection: $section) {
                    ForEach(Section.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                Group {
                    switch section {
                    case .summary:
                        summaryView
                    case .map:
                        mapView
                    case .details:
                        detailsView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controls
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.ultraThinMaterial)
            }
            .onAppear {
                tracker.requestLocationPermission()
                recenterMap(animated: false)
            }
            .onChange(of: section) { _, newSection in
                if newSection == .map { recenterMap(animated: false) }
            }
            .onChange(of: tracker.route.count) { _, _ in
                guard followUser, section == .map else { return }
                recenterMap(animated: true)
            }
        }
    }

    private var liveHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tracker.isPaused ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(tracker.isPaused ? "EN PAUSE" : "EN COURS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(tracker.displayActivity.label)
                        .font(.title3.weight(.bold))
                    if tracker.selectedActivity.isAutomatic {
                        Text("AUTO")
                            .font(.caption2.weight(.black))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.mint.opacity(0.16), in: Capsule())
                            .foregroundStyle(.mint)
                    }
                }
            }
            Spacer()
            Text(liveDuration(tracker.elapsedSeconds))
                .font(.system(size: 28, weight: .black, design: .rounded))
                .monospacedDigit()
        }
    }

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 12) {
                LiveHeroMetric(
                    title: "DISTANCE",
                    value: tracker.elapsedSeconds >= 5 ? liveDistance(tracker.distanceMeters) : "—",
                    symbol: "point.topleft.down.to.point.bottomright.curvepath"
                )

                HStack(spacing: 10) {
                    LiveMetricTile(
                        title: "CŒUR",
                        value: tracker.heartRate > 0 ? String(format: "%.0f", tracker.heartRate) : "—",
                        unit: "bpm",
                        symbol: "heart.fill"
                    )
                    LiveMetricTile(
                        title: paceOrSpeedTitle,
                        value: paceOrSpeedValue,
                        unit: paceOrSpeedUnit,
                        symbol: tracker.displayActivity.symbol
                    )
                }

                HStack(spacing: 10) {
                    LiveMetricTile(
                        title: "CALORIES",
                        value: tracker.activeEnergyKcal > 0 ? String(format: "%.0f", tracker.activeEnergyKcal) : "—",
                        unit: "kcal",
                        symbol: "flame.fill"
                    )
                    LiveMetricTile(
                        title: "DÉNIVELÉ",
                        value: tracker.elapsedSeconds >= 5 ? String(format: "+%.0f", tracker.elevationGainMeters) : "—",
                        unit: "m",
                        symbol: "mountain.2.fill"
                    )
                }

                if !tracker.gpsSettled || tracker.heartRate <= 0 {
                    HStack(spacing: 12) {
                        if !tracker.gpsSettled {
                            Label("GPS en acquisition", systemImage: "location.magnifyingglass")
                        }
                        if tracker.heartRate <= 0 {
                            Label("Cardio en acquisition", systemImage: "heart")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if tracker.selectedActivity.isAutomatic {
                    HStack {
                        Label("Détection active", systemImage: "wand.and.stars")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(tracker.effectiveActivity.label)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.mint)
                    }
                    .padding(14)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var mapView: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
            UserAnnotation()
            if tracker.route.count > 1 {
                MapPolyline(coordinates: tracker.route)
                    .stroke(.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
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
        .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                recenterMap(animated: true)
            } label: {
                Image(systemName: followUser ? "location.fill" : "location")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Recentrer sur ma position")
            .padding(14)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 12).onChanged { _ in
                followUser = false
            }
        )
    }

    private var detailsView: some View {
        ScrollView {
            VStack(spacing: 12) {
                detailSection("EFFORT", symbol: "waveform.path.ecg") {
                    DetailLine(label: "FC actuelle", value: tracker.heartRate > 0 ? String(format: "%.0f bpm", tracker.heartRate) : "—")
                    DetailLine(label: "FC moyenne", value: tracker.averageHeartRate > 0 ? String(format: "%.0f bpm", tracker.averageHeartRate) : "—")
                    DetailLine(label: "Calories actives", value: tracker.activeEnergyKcal > 0 ? String(format: "%.0f kcal", tracker.activeEnergyKcal) : "—")
                    DetailLine(label: "Cadence", value: tracker.cadenceSPM > 0 ? String(format: "%.0f pas/min", tracker.cadenceSPM) : "—")
                    DetailLine(label: "Pas", value: tracker.steps > 0 ? "\(tracker.steps)" : "—")
                }

                detailSection("TERRAIN / GPS", symbol: "mountain.2.fill") {
                    DetailLine(label: "Vitesse", value: tracker.gpsSettled ? String(format: "%.1f km/h", tracker.currentSpeedMps * 3.6) : "—")
                    DetailLine(label: "Altitude", value: tracker.elapsedSeconds >= 5 ? String(format: "%.0f m", tracker.altitudeMeters) : "—")
                    DetailLine(label: "Montée", value: tracker.elapsedSeconds >= 5 ? String(format: "+%.0f m", tracker.elevationGainMeters) : "—")
                    DetailLine(label: "Descente", value: tracker.elapsedSeconds >= 5 ? String(format: "-%.0f m", tracker.elevationLossMeters) : "—")
                    DetailLine(label: "Précision GPS", value: tracker.horizontalAccuracy >= 0 ? String(format: "±%.0f m", tracker.horizontalAccuracy) : "Acquisition…")
                }

                if let weather = tracker.currentWeather {
                    detailSection("CONDITIONS", symbol: "cloud.sun.fill") {
                        if let temperature = weather.temperatureC {
                            DetailLine(label: "Température", value: String(format: "%.1f °C", temperature))
                        }
                        if let apparent = weather.apparentTemperatureC {
                            DetailLine(label: "Ressenti", value: String(format: "%.1f °C", apparent))
                        }
                        if let wind = weather.windSpeedKPH {
                            DetailLine(label: "Vent", value: String(format: "%.0f km/h", wind))
                        }
                        if let humidity = weather.relativeHumidityPercent {
                            DetailLine(label: "Humidité", value: String(format: "%.0f %%", humidity))
                        }
                    }
                }

                Text(tracker.pendingCommand == nil ? tracker.statusMessage : "En attente de confirmation de la Watch…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 18)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
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
                if tracker.workflowFinishReview.required {
                    finishActivity = tracker.workflowFinishReview.suggestedActivity
                    showFinishReview = true
                } else {
                    tracker.workflowFinish(
                        disposition: .preserveDetectedSegments
                    )
                }
            } label: {
                Label("Terminer", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(tracker.pendingCommand != nil)

            .sheet(isPresented: $showFinishReview) {
                PhoneFinishActivityReview(
                    selection: $finishActivity,
                    suggested: tracker.workflowFinishReview.suggestedActivity,
                    preserveAuto: {
                        tracker.workflowFinish(
                            disposition: .preserveDetectedSegments
                        )
                        showFinishReview = false
                    },
                    confirmSingle: {
                        tracker.workflowFinish(
                            disposition: .forceSingleActivity,
                            finalActivity: finishActivity
                        )
                        showFinishReview = false
                    }
                )
            }
        }
    }

    private var paceOrSpeedTitle: String {
        switch tracker.displayActivity {
        case .walking, .running, .hiking:
            return "ALLURE"
        default:
            return "VITESSE"
        }
    }

    private var paceOrSpeedValue: String {
        guard tracker.gpsSettled else { return "—" }
        switch tracker.displayActivity {
        case .walking, .running, .hiking:
            return livePace(tracker.currentSpeedMps)
        default:
            return String(format: "%.1f", tracker.currentSpeedMps * 3.6)
        }
    }

    private var paceOrSpeedUnit: String {
        switch tracker.displayActivity {
        case .walking, .running, .hiking:
            return "/km"
        default:
            return "km/h"
        }
    }

    private func recenterMap(animated: Bool) {
        followUser = true
        tracker.requestLocationPermission()

        let update = {
            if let coordinate = tracker.currentCoordinate {
                cameraPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        latitudinalMeters: 600,
                        longitudinalMeters: 600
                    )
                )
            } else {
                cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            }
        }

        if animated {
            withAnimation(.easeOut(duration: 0.28), update)
        } else {
            update()
        }
    }

    private func detailSection<Content: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(16)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ActivityReadinessPill: View {
    let title: String
    let ready: Bool
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ready ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(ready ? Color.green.opacity(0.12) : Color.white.opacity(0.05), in: Capsule())
    }
}


private struct PhoneFinishActivityReview: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: ActivityKind

    let suggested: ActivityKind
    let preserveAuto: () -> Void
    let confirmSingle: () -> Void

    private var activities: [ActivityKind] {
        ActivityKind.allCases.filter { !$0.isAutomatic }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Détection automatique") {
                    Button {
                        preserveAuto()
                    } label: {
                        Label(
                            "Conserver les segments détectés",
                            systemImage: "wand.and.stars"
                        )
                    }

                    Text(
                        "Conserve tous les changements de sport réellement détectés pendant la séance."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Forcer un seul sport") {
                    Picker("Activité", selection: $selection) {
                        ForEach(activities) { activity in
                            Label(
                                activity.label,
                                systemImage: activity.symbol
                            )
                            .tag(activity)
                        }
                    }

                    Text("Suggestion Auto : \(suggested.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        confirmSingle()
                    } label: {
                        Label(
                            "Enregistrer comme \(selection.label)",
                            systemImage: "checkmark.circle.fill"
                        )
                    }
                }
            }
            .navigationTitle("Terminer la séance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct LiveHeroMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct LiveMetricTile: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .leading)
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }
}

private func liveDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
}

private func liveDistance(_ meters: Double) -> String {
    meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
}

private func livePace(_ speedMps: Double) -> String {
    guard speedMps > 0.2 else { return "—" }
    let secondsPerKm = Int(1000 / speedMps)
    return String(format: "%d:%02d", secondsPerKm / 60, secondsPerKm % 60)
}
