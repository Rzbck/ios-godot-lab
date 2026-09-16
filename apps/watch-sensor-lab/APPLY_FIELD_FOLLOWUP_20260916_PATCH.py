#!/usr/bin/env python3
"""Apply field-test follow-up fixes from physical session 1789561072024.

This patch intentionally runs after the reactivity/haptics patch.

Goals:
- keep brisk walking around 1.7-1.9 m/s and ~100-120 steps/min classified as walking;
- fix local active duration when a workout is ended while already paused;
- remove the competing top OSM bar and feed OSM into the existing iPhone Terrain/Map UI;
- persistently expose OSM in History, with presented distances normalized to the canonical Tracker distance;
- mirror only compact current OSM context to Watch and show it in the existing Route/Terrain page;
- keep Overpass/network work on iPhone only.

The patch is idempotent and fail-closed so CI/Xcode can safely run the complete
source-generation chain repeatedly.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
POLICY = ROOT / "Shared/TrackerAutoPolicy.swift"
FINISH_POLICY = ROOT / "Shared/TrackerFinishPersistencePolicy.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"
WATCH_HISTORY = ROOT / "watch/Sources/WatchRecentHistory.swift"
WATCH_VIEW = ROOT / "watch/Sources/WatchActiveWorkoutView.swift"
TRACKER_APP = ROOT / "iphone/Sources/TrackerApp.swift"
PRODUCT = ROOT / "iphone/Sources/ActivityProductContainerView.swift"
HISTORY = ROOT / "iphone/Sources/ActivityHistoryView.swift"
OSM = ROOT / "iphone/Sources/OSMSurfaceContext.swift"
AUTO_TESTS = ROOT / "Tests/TrackerAutoPolicyTests.swift"
FINISH_TESTS = ROOT / "Tests/TrackerFinishPersistencePolicyTests.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


policy = POLICY.read_text(encoding="utf-8")
finish_policy = FINISH_POLICY.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")
watch_history = WATCH_HISTORY.read_text(encoding="utf-8")
watch_view = WATCH_VIEW.read_text(encoding="utf-8")
tracker_app = TRACKER_APP.read_text(encoding="utf-8")
product = PRODUCT.read_text(encoding="utf-8")
history = HISTORY.read_text(encoding="utf-8")
osm = OSM.read_text(encoding="utf-8")
auto_tests = AUTO_TESTS.read_text(encoding="utf-8")
finish_tests = FINISH_TESTS.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Auto sport: the physical field walk proved 1.70-1.79 m/s at ~104-106 spm
# can be brisk walking. Keep trusted Core Motion running semantic evidence, but
# make the sensor-only fallback substantially more conservative.
# ---------------------------------------------------------------------------
policy = replace_once_or_present(
    policy,
    '''        if speed >= 1.7, cadence >= 95 {\n            return TrackerAutoDecision(\n                activity: .running,\n                confidence: motionTrusted ? confidence : "capteurs",\n                provenance: "GPS + cadence · course",\n                dwellSeconds: 2.0\n            )\n        }\n''',
    '''        // FIELD_1789561072024_BRISK_WALK_GUARD\n        // Fast walking crossed the former 1.7 m/s + 95 spm fallback twice.\n        // Require a gait cadence much closer to the walk/run transition before\n        // sensor-only evidence can promote walking to running. Trusted Core\n        // Motion running evidence above remains the stronger semantic path.\n        if speed >= 1.90, cadence >= 130 {\n            return TrackerAutoDecision(\n                activity: .running,\n                confidence: motionTrusted ? confidence : "capteurs",\n                provenance: "GPS + cadence · course",\n                dwellSeconds: 3.0\n            )\n        }\n''',
    "// FIELD_1789561072024_BRISK_WALK_GUARD",
    "brisk-walk running fallback",
)

auto_tests = replace_once_or_present(
    auto_tests,
    '''    func testSensorFallbackCanClassifyWalkingWithoutCoreMotionLabel() {\n''',
    '''    func testFieldBriskWalkingDoesNotBecomeRunningFromLowCadence() { // FIELD_1789561072024_BRISK_WALK_TEST\n        let firstFalseRun = TrackerAutoPolicy.decision(\n            from: TrackerMotionEvidence(confidence: .low),\n            speedMps: 1.79,\n            cadenceSPM: 104.5\n        )\n        let secondFalseRun = TrackerAutoPolicy.decision(\n            from: TrackerMotionEvidence(confidence: .low),\n            speedMps: 1.72,\n            cadenceSPM: 106\n        )\n        let clearSensorRun = TrackerAutoPolicy.decision(\n            from: TrackerMotionEvidence(confidence: .low),\n            speedMps: 2.05,\n            cadenceSPM: 135\n        )\n\n        XCTAssertEqual(firstFalseRun?.activity, .walking)\n        XCTAssertEqual(secondFalseRun?.activity, .walking)\n        XCTAssertEqual(clearSensorRun?.activity, .running)\n        XCTAssertEqual(clearSensorRun?.provenance, "GPS + cadence · course")\n    }\n\n    func testSensorFallbackCanClassifyWalkingWithoutCoreMotionLabel() {\n''',
    "// FIELD_1789561072024_BRISK_WALK_TEST",
    "brisk-walk regression test",
)

# ---------------------------------------------------------------------------
# Finish timing: when stopping in paused state, the old code first added the
# final pause to pausedDuration, then refreshElapsed() still used pausedAt as the
# end bound. That subtracted the same final pause twice.
# ---------------------------------------------------------------------------
finish_policy = replace_once_or_present(
    finish_policy,
    '''    static func shouldSchedulePendingPlans(\n''',
    '''    static func activeDuration(\n        startedAt: Date?,\n        endedAt: Date,\n        pausedDuration: TimeInterval\n    ) -> TimeInterval { // FIELD_1789561072024_FINISH_DURATION_POLICY\n        guard let startedAt else { return 0 }\n        return max(0, endedAt.timeIntervalSince(startedAt) - max(0, pausedDuration))\n    }\n\n    static func shouldSchedulePendingPlans(\n''',
    "// FIELD_1789561072024_FINISH_DURATION_POLICY",
    "finish active duration policy",
)

watch = replace_once_or_present(
    watch,
    '''        let end = Date()\n        if phase == .paused, let pausedAt { pausedDuration += end.timeIntervalSince(pausedAt) }\n        refreshElapsed()\n''',
    '''        let end = Date()\n        if phase == .paused, let pausedAt {\n            pausedDuration += end.timeIntervalSince(pausedAt)\n            self.pausedAt = nil // FIELD_1789561072024_STOP_WHILE_PAUSED_DURATION\n        }\n        elapsedSeconds = TrackerFinishPersistencePolicy.activeDuration(\n            startedAt: startedAt,\n            endedAt: end,\n            pausedDuration: pausedDuration\n        )\n''',
    "// FIELD_1789561072024_STOP_WHILE_PAUSED_DURATION",
    "stop while paused duration repair",
)

finish_tests = replace_once_or_present(
    finish_tests,
    '''    func testNoPendingPlanDoesNotSchedule() {\n''',
    '''    func testEndingWhilePausedSubtractsFinalPauseExactlyOnce() { // FIELD_1789561072024_FINISH_DURATION_TEST\n        let started = Date(timeIntervalSince1970: 1_000)\n        let ended = Date(timeIntervalSince1970: 1_100)\n\n        XCTAssertEqual(\n            TrackerFinishPersistencePolicy.activeDuration(\n                startedAt: started,\n                endedAt: ended,\n                pausedDuration: 30\n            ),\n            70,\n            accuracy: 0.0001\n        )\n    }\n\n    func testNoPendingPlanDoesNotSchedule() {\n''',
    "// FIELD_1789561072024_FINISH_DURATION_TEST",
    "finish duration regression test",
)

# ---------------------------------------------------------------------------
# iPhone root: remove the separate top OSM bar. OSM remains active through the
# existing begin/ingest/finish observers and is rendered in the product pages.
# ---------------------------------------------------------------------------
tracker_app = replace_once_or_present(
    tracker_app,
    '''        rootTabs\n            .safeAreaInset(edge: .top, spacing: 0) {\n                if tracker.isActive, selection == .activity, osmSurfaceEnabled {\n                    OSMLiveSurfaceBar()\n                }\n            }\n            .simultaneousGesture(\n''',
    '''        rootTabs\n            // FIELD_1789561072024_OSM_USE_EXISTING_PRODUCT_SLOTS\n            .simultaneousGesture(\n''',
    "// FIELD_1789561072024_OSM_USE_EXISTING_PRODUCT_SLOTS",
    "remove competing top OSM bar",
)

# ---------------------------------------------------------------------------
# iPhone live product: use existing Terrain > SURFACE slot and existing map.
# ---------------------------------------------------------------------------
product = replace_once_or_present(
    product,
    '''    @EnvironmentObject private var tracker: TrackerModel\n    @AppStorage("tracker.map.style") private var mapStyleRaw = TrackerMapStyleChoice.standard.rawValue\n''',
    '''    @EnvironmentObject private var tracker: TrackerModel\n    @ObservedObject private var osmContext = OSMRouteContextService.shared // FIELD_1789561072024_PRODUCT_OSM_CONTEXT\n    @AppStorage("tracker.map.style") private var mapStyleRaw = TrackerMapStyleChoice.standard.rawValue\n''',
    "// FIELD_1789561072024_PRODUCT_OSM_CONTEXT",
    "live product OSM observer",
)

product = replace_once_or_present(
    product,
    '''            if tracker.route.count > 1 {\n                MapPolyline(coordinates: tracker.route)\n                    .stroke(activityAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))\n            }\n''',
    '''            if osmContext.liveSegments.isEmpty { // FIELD_1789561072024_PRODUCT_OSM_MAP\n                if tracker.route.count > 1 {\n                    MapPolyline(coordinates: tracker.route)\n                        .stroke(activityAccent, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))\n                }\n            } else {\n                if tracker.route.count > 1 {\n                    MapPolyline(coordinates: tracker.route)\n                        .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))\n                }\n                ForEach(osmContext.liveSegments.filter { $0.mapCoordinates.count > 1 }) { segment in\n                    MapPolyline(coordinates: segment.mapCoordinates)\n                        .stroke(\n                            OSMSurfaceVocabulary.color(for: segment.surfaceKey),\n                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)\n                        )\n                }\n            }\n''',
    "// FIELD_1789561072024_PRODUCT_OSM_MAP",
    "existing live map OSM segments",
)

product = replace_once_or_present(
    product,
    '''            VStack(alignment: .leading, spacing: 5) {\n                Text("SURFACE")\n                    .font(.caption2.weight(.black))\n                    .foregroundStyle(.secondary)\n                Text("Non déterminée en direct")\n                    .font(.headline.weight(.bold))\n                Text("Route / sentier / gravier ne sera affiché que lorsqu’une vraie source cartographique permet de le déterminer de façon fiable.")\n                    .font(.caption)\n                    .foregroundStyle(.secondary)\n            }\n            .frame(maxWidth: .infinity, alignment: .leading)\n            .padding(14)\n            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))\n''',
    '''            VStack(alignment: .leading, spacing: 5) { // FIELD_1789561072024_PRODUCT_OSM_SURFACE_SLOT\n                HStack {\n                    Text("SURFACE")\n                        .font(.caption2.weight(.black))\n                        .foregroundStyle(.secondary)\n                    Spacer()\n                    Text("OSM")\n                        .font(.system(size: 9, weight: .black))\n                        .foregroundStyle(.mint)\n                }\n                if let match = osmContext.currentMatch {\n                    HStack(spacing: 8) {\n                        Circle()\n                            .fill(OSMSurfaceVocabulary.color(for: match.surfaceKey))\n                            .frame(width: 9, height: 9)\n                        Text(match.surfaceLabel)\n                            .font(.headline.weight(.bold))\n                    }\n                    Text("\\(match.highwayLabel) · confiance \\(Int((match.confidence * 100).rounded())) %")\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                } else {\n                    Text("Recherche OSM…")\n                        .font(.headline.weight(.bold))\n                    Text(osmContext.networkState)\n                        .font(.caption)\n                        .foregroundStyle(.secondary)\n                }\n            }\n            .frame(maxWidth: .infinity, alignment: .leading)\n            .padding(14)\n            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18, style: .continuous))\n''',
    "// FIELD_1789561072024_PRODUCT_OSM_SURFACE_SLOT",
    "existing Terrain surface slot",
)

# ---------------------------------------------------------------------------
# OSM service: mirror compact current context to Watch, never Overpass data or
# route geometry. Also normalize distances in the transient post-workout detail.
# ---------------------------------------------------------------------------
osm = replace_once_or_present(
    osm,
    '''import SwiftUI\n''',
    '''import SwiftUI\nimport WatchConnectivity // FIELD_1789561072024_OSM_WATCH_BRIDGE_IMPORT\n''',
    "// FIELD_1789561072024_OSM_WATCH_BRIDGE_IMPORT",
    "OSM Watch bridge import",
)

osm = replace_once_or_present(
    osm,
    '''    private var lastPersistAt = Date.distantPast\n\n    private init() {}\n''',
    '''    private var lastPersistAt = Date.distantPast\n    private var lastWatchContextSignature = "" // FIELD_1789561072024_OSM_WATCH_BRIDGE_STATE\n    private var lastWatchContextSentAt = Date.distantPast\n\n    private init() {}\n''',
    "// FIELD_1789561072024_OSM_WATCH_BRIDGE_STATE",
    "OSM Watch bridge state",
)

osm = replace_once_or_present(
    osm,
    '''        lastPersistAt = .distantPast\n        networkState = "OSM · recherche du revêtement"\n''',
    '''        lastPersistAt = .distantPast\n        lastWatchContextSignature = ""\n        lastWatchContextSentAt = .distantPast\n        networkState = "OSM · recherche du revêtement"\n        publishWatchContext(nil, force: true) // FIELD_1789561072024_OSM_WATCH_CLEAR\n''',
    "// FIELD_1789561072024_OSM_WATCH_CLEAR",
    "clear Watch OSM context on new session",
)

osm = replace_once_or_present(
    osm,
    '''            currentMatch = match\n            lastMatchedLocation = location\n''',
    '''            currentMatch = match\n            publishWatchContext(match) // FIELD_1789561072024_OSM_WATCH_LIVE\n            lastMatchedLocation = location\n''',
    "// FIELD_1789561072024_OSM_WATCH_LIVE",
    "publish live OSM context",
)

osm = replace_once_or_present(
    osm,
    '''                    self.transitionIfNeeded(to: match, at: location)\n                    self.currentMatch = match\n''',
    '''                    self.transitionIfNeeded(to: match, at: location)\n                    self.currentMatch = match\n                    self.publishWatchContext(match) // FIELD_1789561072024_OSM_WATCH_AFTER_FETCH\n''',
    "// FIELD_1789561072024_OSM_WATCH_AFTER_FETCH",
    "publish fetched OSM context",
)

osm = replace_once_or_present(
    osm,
    '''    private func persist(generatedAt: Date) {\n''',
    '''    private func publishWatchContext(\n        _ match: OSMSurfaceMatch?,\n        force: Bool = false\n    ) { // FIELD_1789561072024_OSM_WATCH_BRIDGE_METHOD\n        guard WCSession.isSupported(), !sessionID.isEmpty else { return }\n        let session = WCSession.default\n        guard session.activationState == .activated else { return }\n\n        let surfaceKey = match?.surfaceKey ?? "unknown"\n        let highway = match?.highway.lowercased() ?? "unknown"\n        let confidencePercent = Int(((match?.confidence ?? 0) * 100).rounded())\n        let signature = "\\(surfaceKey)|\\(highway)|\\(confidencePercent)"\n        let now = Date()\n        let changed = signature != lastWatchContextSignature\n        let periodicReachableRefresh = session.isReachable\n            && now.timeIntervalSince(lastWatchContextSentAt) >= 30\n        guard force || changed || periodicReachableRefresh else { return }\n\n        let payload: [String: Any] = [\n            "type": "tracker_osm_context_v1",\n            "session_id": sessionID,\n            "available": match != nil,\n            "surface_key": surfaceKey,\n            "surface_label": match?.surfaceLabel ?? "Inconnu",\n            "highway_label": match?.highwayLabel ?? "Type de voie inconnu",\n            "confidence": match?.confidence ?? 0,\n            "timestamp": now.timeIntervalSince1970,\n        ]\n\n        if session.isReachable {\n            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)\n        } else if changed || force {\n            session.transferUserInfo(payload)\n        }\n\n        lastWatchContextSignature = signature\n        lastWatchContextSentAt = now\n    }\n\n    private func persist(generatedAt: Date) {\n''',
    "// FIELD_1789561072024_OSM_WATCH_BRIDGE_METHOD",
    "OSM compact Watch bridge",
)

osm = replace_once_or_present(
    osm,
    '''                    OSMSummaryCompactBar(snapshot: snapshot)\n''',
    '''                    OSMSummaryCompactBar(\n                        snapshot: snapshot,\n                        referenceDistanceMeters: summary.distanceMeters\n                    ) // FIELD_1789561072024_OSM_CANONICAL_SUMMARY_DISTANCE\n''',
    "// FIELD_1789561072024_OSM_CANONICAL_SUMMARY_DISTANCE",
    "post summary canonical distance input",
)

osm = replace_once_or_present(
    osm,
    '''private struct OSMSummaryCompactBar: View {\n    let snapshot: OSMRouteContextSnapshot\n    @State private var showDetail = false\n''',
    '''private struct OSMSummaryCompactBar: View {\n    let snapshot: OSMRouteContextSnapshot\n    let referenceDistanceMeters: Double // FIELD_1789561072024_OSM_COMPACT_REFERENCE_DISTANCE\n    @State private var showDetail = false\n''',
    "// FIELD_1789561072024_OSM_COMPACT_REFERENCE_DISTANCE",
    "compact OSM canonical distance",
)

osm = replace_once_or_present(
    osm,
    '''            OSMSummaryDetailView(snapshot: snapshot)\n''',
    '''            OSMSummaryDetailView(\n                snapshot: snapshot,\n                referenceDistanceMeters: referenceDistanceMeters\n            ) // FIELD_1789561072024_OSM_DETAIL_REFERENCE_DISTANCE\n''',
    "// FIELD_1789561072024_OSM_DETAIL_REFERENCE_DISTANCE",
    "OSM detail canonical distance",
)

osm = replace_once_or_present(
    osm,
    '''private struct OSMSummaryDetailView: View {\n    let snapshot: OSMRouteContextSnapshot\n    @Environment(\\.dismiss) private var dismiss\n''',
    '''private struct OSMSummaryDetailView: View {\n    let snapshot: OSMRouteContextSnapshot\n    let referenceDistanceMeters: Double // FIELD_1789561072024_OSM_DETAIL_REFERENCE_STATE\n    @Environment(\\.dismiss) private var dismiss\n''',
    "// FIELD_1789561072024_OSM_DETAIL_REFERENCE_STATE",
    "OSM detail reference state",
)

osm = replace_once_or_present(
    osm,
    '''    private func breakdown(title: String, values: [OSMContextBreakdown], colored: Bool) -> some View {\n        VStack(alignment: .leading, spacing: 10) {\n''',
    '''    private var normalizedDistanceScale: Double { // FIELD_1789561072024_OSM_NORMALIZED_DISTANCE_SCALE\n        let raw = snapshot.totalDistanceMeters\n        guard raw > 0, referenceDistanceMeters > 0 else { return 1 }\n        return referenceDistanceMeters / raw\n    }\n\n    private func breakdown(title: String, values: [OSMContextBreakdown], colored: Bool) -> some View {\n        VStack(alignment: .leading, spacing: 10) {\n''',
    "// FIELD_1789561072024_OSM_NORMALIZED_DISTANCE_SCALE",
    "OSM normalized detail scale",
)

osm = replace_once_or_present(
    osm,
    '''                        Text(String(format: "%.2f km", value.distanceMeters / 1000))\n''',
    '''                        Text(String(format: "%.2f km", value.distanceMeters * normalizedDistanceScale / 1000)) // FIELD_1789561072024_OSM_NORMALIZED_BREAKDOWN_DISTANCE\n''',
    "// FIELD_1789561072024_OSM_NORMALIZED_BREAKDOWN_DISTANCE",
    "OSM normalized breakdown distance",
)

# ---------------------------------------------------------------------------
# History: persisted OSM must remain discoverable after a Watch-side finish.
# ---------------------------------------------------------------------------
history = replace_once_or_present(
    history,
    '''    @State private var comparableSummaries: [TrackerSummary] = []\n    @State private var technicalTraceExpanded = false\n''',
    '''    @State private var comparableSummaries: [TrackerSummary] = []\n    @State private var osmSnapshot: OSMRouteContextSnapshot? // FIELD_1789561072024_HISTORY_OSM_STATE\n    @State private var technicalTraceExpanded = false\n''',
    "// FIELD_1789561072024_HISTORY_OSM_STATE",
    "History OSM state",
)

history = replace_once_or_present(
    history,
    '''                if route.count > 1 {\n                    routeCard\n                }\n\n                ActivityReviewCard(summary: summary) { saved in\n''',
    '''                if route.count > 1 || (osmSnapshot?.segments.contains { $0.mapCoordinates.count > 1 } ?? false) {\n                    routeCard\n                }\n\n                if let osmSnapshot { // FIELD_1789561072024_HISTORY_OSM_CARD_PLACEMENT\n                    osmSummaryCard(osmSnapshot)\n                }\n\n                ActivityReviewCard(summary: summary) { saved in\n''',
    "// FIELD_1789561072024_HISTORY_OSM_CARD_PLACEMENT",
    "History OSM card placement",
)

history = replace_once_or_present(
    history,
    '''    private var routeCard: some View {\n        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {\n            MapPolyline(coordinates: route)\n                .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))\n            if let first = route.first {\n''',
    '''    private var routeCard: some View {\n        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {\n            if let osmSnapshot, !osmSnapshot.segments.isEmpty { // FIELD_1789561072024_HISTORY_OSM_MAP\n                if route.count > 1 {\n                    MapPolyline(coordinates: route)\n                        .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))\n                }\n                ForEach(osmSnapshot.segments.filter { $0.mapCoordinates.count > 1 }) { segment in\n                    MapPolyline(coordinates: segment.mapCoordinates)\n                        .stroke(\n                            OSMSurfaceVocabulary.color(for: segment.surfaceKey),\n                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)\n                        )\n                }\n            } else if route.count > 1 {\n                MapPolyline(coordinates: route)\n                    .stroke(.mint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))\n            }\n            if let first = route.first {\n''',
    "// FIELD_1789561072024_HISTORY_OSM_MAP",
    "History OSM colored map",
)

history = replace_once_or_present(
    history,
    '''    @ViewBuilder\n    private var weatherSection: some View {\n''',
    '''    private func osmSummaryCard(_ snapshot: OSMRouteContextSnapshot) -> some View { // FIELD_1789561072024_HISTORY_OSM_SUMMARY\n        let rawTotal = max(1, snapshot.totalDistanceMeters)\n        let normalizedScale = summary.distanceMeters > 0\n            ? summary.distanceMeters / rawTotal\n            : 1\n        let coverage = min(1, snapshot.knownSurfaceDistanceMeters / rawTotal)\n        let effort = OSMSurfaceEffortAnalyzer().analyze(summary: summary)\n\n        return VStack(alignment: .leading, spacing: 11) {\n            HStack {\n                Label("ROUTE / REVÊTEMENT · OSM", systemImage: "road.lanes")\n                    .font(.caption.weight(.black))\n                    .foregroundStyle(.secondary)\n                Spacer()\n                Text("\\(Int((coverage * 100).rounded())) % renseigné")\n                    .font(.caption2.weight(.bold))\n                    .foregroundStyle(.mint)\n            }\n\n            HStack {\n                Text("Impact effort")\n                    .font(.caption)\n                    .foregroundStyle(.secondary)\n                Spacer()\n                Text("+\\(String(format: "%.2f", effort.contribution))")\n                    .font(.caption.monospacedDigit().weight(.bold))\n                    .foregroundStyle(.orange)\n            }\n\n            Text("REVÊTEMENTS")\n                .font(.caption2.weight(.black))\n                .foregroundStyle(.secondary)\n            ForEach(Array(snapshot.surfaceBreakdown.prefix(4))) { item in\n                HStack(spacing: 8) {\n                    Circle()\n                        .fill(OSMSurfaceVocabulary.color(for: item.key))\n                        .frame(width: 8, height: 8)\n                    Text(item.label)\n                        .font(.caption.weight(.semibold))\n                    Spacer()\n                    Text(String(format: "%.2f km", item.distanceMeters * normalizedScale / 1000))\n                        .font(.caption.monospacedDigit())\n                    Text("\\(Int((item.distanceMeters / rawTotal * 100).rounded())) %")\n                        .font(.caption2)\n                        .foregroundStyle(.secondary)\n                        .frame(width: 34, alignment: .trailing)\n                }\n            }\n\n            Text("TYPES DE VOIE")\n                .font(.caption2.weight(.black))\n                .foregroundStyle(.secondary)\n                .padding(.top, 2)\n            ForEach(Array(snapshot.highwayBreakdown.prefix(3))) { item in\n                HStack {\n                    Text(item.label)\n                        .font(.caption.weight(.semibold))\n                    Spacer()\n                    Text("\\(Int((item.distanceMeters / rawTotal * 100).rounded())) %")\n                        .font(.caption2.monospacedDigit())\n                        .foregroundStyle(.secondary)\n                }\n            }\n\n            Text(snapshot.attribution)\n                .font(.caption2)\n                .foregroundStyle(.tertiary)\n        }\n        .frame(maxWidth: .infinity, alignment: .leading)\n        .padding(14)\n        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))\n    }\n\n    @ViewBuilder\n    private var weatherSection: some View {\n''',
    "// FIELD_1789561072024_HISTORY_OSM_SUMMARY",
    "History OSM summary card",
)

history = replace_once_or_present(
    history,
    '''            let loadedRoute = store.loadRoute(sessionID: sessionID)\n            let loadedTimeline = timelineLoader.load(sessionID: sessionID)\n            DispatchQueue.main.async {\n                route = loadedRoute\n                timeline = loadedTimeline\n''',
    '''            let loadedRoute = store.loadRoute(sessionID: sessionID)\n            let loadedTimeline = timelineLoader.load(sessionID: sessionID)\n            let loadedOSM = OSMRouteContextStore.load(sessionID: sessionID) // FIELD_1789561072024_HISTORY_OSM_LOAD\n            DispatchQueue.main.async {\n                route = loadedRoute\n                timeline = loadedTimeline\n                osmSnapshot = loadedOSM\n''',
    "// FIELD_1789561072024_HISTORY_OSM_LOAD",
    "History OSM persistence load",
)

# ---------------------------------------------------------------------------
# Watch runtime + existing Route/Terrain page. Only compact context crosses WC.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''    @Published private(set) var autoProvenance = "En attente"\n\n    @Published private(set) var accelX = 0.0\n''',
    '''    @Published private(set) var autoProvenance = "En attente"\n    @Published private(set) var osmContextAvailable = false // FIELD_1789561072024_WATCH_OSM_STATE\n    @Published private(set) var osmSurfaceLabel = "Inconnu"\n    @Published private(set) var osmHighwayLabel = "Type de voie inconnu"\n    @Published private(set) var osmConfidence = 0.0\n\n    @Published private(set) var accelX = 0.0\n''',
    "// FIELD_1789561072024_WATCH_OSM_STATE",
    "Watch OSM published state",
)

watch = replace_once_or_present(
    watch,
    '''        autoProvenance = selectedActivity.isAutomatic ? "En attente" : "Choix utilisateur"\n        if !keepActivity {\n''',
    '''        autoProvenance = selectedActivity.isAutomatic ? "En attente" : "Choix utilisateur"\n        osmContextAvailable = false // FIELD_1789561072024_WATCH_OSM_RESET\n        osmSurfaceLabel = "Inconnu"\n        osmHighwayLabel = "Type de voie inconnu"\n        osmConfidence = 0\n        if !keepActivity {\n''',
    "// FIELD_1789561072024_WATCH_OSM_RESET",
    "Watch OSM reset",
)

# ---------------------------------------------------------------------------
# Watch queued WC payloads: SensorModel is the WCSession delegate, therefore
# didReceiveUserInfo must exist exactly once. Merge recent-history ingestion
# and OSM reception into that single callback.
# ---------------------------------------------------------------------------
watch_userinfo_base = '''    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }\n    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }\n'''

watch_userinfo_legacy_osm = '''    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }\n    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }\n    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receiveWC(userInfo) } // FIELD_1789561072024_WATCH_OSM_USERINFO\n'''

watch_userinfo_merged = '''    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }\n    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }\n    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) { // FIELD_1789561072024_WATCH_USERINFO_MERGED\n        _ = WatchRecentHistoryStore.shared.ingest(userInfo)\n        receiveWC(userInfo)\n    }\n'''

if "// FIELD_1789561072024_WATCH_USERINFO_MERGED" not in watch:
    if "// FIELD_1789561072024_WATCH_OSM_USERINFO" in watch:
        count = watch.count(watch_userinfo_legacy_osm)
        if count != 1:
            raise SystemExit(
                f"legacy OSM userInfo migration: expected one match, got {count}"
            )
        watch = watch.replace(
            watch_userinfo_legacy_osm,
            watch_userinfo_merged,
            1,
        )
    else:
        count = watch.count(watch_userinfo_base)
        if count != 1:
            raise SystemExit(
                f"merged userInfo insertion: expected one match, got {count}"
            )
        watch = watch.replace(
            watch_userinfo_base,
            watch_userinfo_merged,
            1,
        )

legacy_history_delegate = '''extension SensorModel {\n    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {\n        _ = WatchRecentHistoryStore.shared.ingest(userInfo)\n    }\n}\n\n'''

if legacy_history_delegate in watch_history:
    count = watch_history.count(legacy_history_delegate)
    if count != 1:
        raise SystemExit(
            f"recent-history delegate migration: expected one match, got {count}"
        )
    watch_history = watch_history.replace(
        legacy_history_delegate,
        "",
        1,
    )
elif "didReceiveUserInfo userInfo" in watch_history:
    raise SystemExit(
        "WatchRecentHistory.swift contains an unknown didReceiveUserInfo implementation"
    )


watch = replace_once_or_present(
    watch,
    '''    private func receiveWC(_ payload: [String: Any]) {\n        if payload["type"] as? String == "tracker_preferences_v4" {\n''',
    '''    private func handleOSMContext(_ payload: [String: Any]) { // FIELD_1789561072024_WATCH_OSM_HANDLER\n        let targetSession = payload["session_id"] as? String ?? ""\n        guard running, !sessionID.isEmpty, targetSession == sessionID else { return }\n\n        let available = payload["available"] as? Bool ?? false\n        osmContextAvailable = available\n        osmSurfaceLabel = payload["surface_label"] as? String ?? "Inconnu"\n        osmHighwayLabel = payload["highway_label"] as? String ?? "Type de voie inconnu"\n        if let confidence = payload["confidence"] as? Double {\n            osmConfidence = confidence\n        } else if let confidence = payload["confidence"] as? NSNumber {\n            osmConfidence = confidence.doubleValue\n        } else {\n            osmConfidence = 0\n        }\n    }\n\n    private func receiveWC(_ payload: [String: Any]) {\n        if payload["type"] as? String == "tracker_osm_context_v1" {\n            DispatchQueue.main.async { [weak self] in self?.handleOSMContext(payload) }\n            return\n        }\n\n        if payload["type"] as? String == "tracker_preferences_v4" {\n''',
    "// FIELD_1789561072024_WATCH_OSM_HANDLER",
    "Watch OSM WC handler",
)

watch_view = replace_once_or_present(
    watch_view,
    '''            HStack(spacing: 8) {\n                CompactTerrainValue(title: "ALT", value: model.elapsedSeconds > 4 ? "\\(Int(model.altitudeMeters)) m" : "—")\n                CompactTerrainValue(title: "D+", value: model.elapsedSeconds > 4 ? "+\\(Int(model.elevationGainMeters)) m" : "—")\n                CompactTerrainValue(title: "GPS", value: model.horizontalAccuracy >= 0 ? "±\\(Int(model.horizontalAccuracy)) m" : "—")\n            }\n''',
    '''            VStack(alignment: .leading, spacing: 2) { // FIELD_1789561072024_WATCH_OSM_TERRAIN_UI\n                HStack(spacing: 5) {\n                    Image(systemName: "road.lanes")\n                        .foregroundStyle(model.osmContextAvailable ? Color.mint : Color.secondary)\n                    Text(model.osmContextAvailable ? model.osmSurfaceLabel : "OSM · en attente")\n                        .font(.system(size: 9, weight: .bold))\n                        .lineLimit(1)\n                    Spacer()\n                    if model.osmContextAvailable {\n                        Text("\\(Int((model.osmConfidence * 100).rounded())) %")\n                            .font(.system(size: 8, weight: .semibold))\n                            .foregroundStyle(.secondary)\n                    }\n                }\n                if model.osmContextAvailable {\n                    Text(model.osmHighwayLabel)\n                        .font(.system(size: 8))\n                        .foregroundStyle(.secondary)\n                        .lineLimit(1)\n                }\n            }\n            .frame(maxWidth: .infinity, alignment: .leading)\n\n            HStack(spacing: 8) {\n                CompactTerrainValue(title: "ALT", value: model.elapsedSeconds > 4 ? "\\(Int(model.altitudeMeters)) m" : "—")\n                CompactTerrainValue(title: "D+", value: model.elapsedSeconds > 4 ? "+\\(Int(model.elevationGainMeters)) m" : "—")\n                CompactTerrainValue(title: "GPS", value: model.horizontalAccuracy >= 0 ? "±\\(Int(model.horizontalAccuracy)) m" : "—")\n            }\n''',
    "// FIELD_1789561072024_WATCH_OSM_TERRAIN_UI",
    "Watch Route/Terrain OSM UI",
)

# ---------------------------------------------------------------------------
# Fail closed if any key product/field marker is missing after transformation.
# ---------------------------------------------------------------------------
watch_userinfo_delegate_count = (
    watch.count("didReceiveUserInfo userInfo: [String: Any]")
    + watch_history.count("didReceiveUserInfo userInfo: [String: Any]")
)
if watch_userinfo_delegate_count != 1:
    raise SystemExit(
        f"Watch didReceiveUserInfo invariant failed: {watch_userinfo_delegate_count} implementations"
    )

required = {
    "policy": ["FIELD_1789561072024_BRISK_WALK_GUARD"],
    "finish_policy": ["FIELD_1789561072024_FINISH_DURATION_POLICY"],
    "watch": [
        "FIELD_1789561072024_STOP_WHILE_PAUSED_DURATION",
        "FIELD_1789561072024_WATCH_OSM_STATE",
        "FIELD_1789561072024_WATCH_OSM_HANDLER",
        "FIELD_1789561072024_WATCH_USERINFO_MERGED",
    ],
    "watch_view": ["FIELD_1789561072024_WATCH_OSM_TERRAIN_UI"],
    "tracker_app": ["FIELD_1789561072024_OSM_USE_EXISTING_PRODUCT_SLOTS"],
    "product": [
        "FIELD_1789561072024_PRODUCT_OSM_CONTEXT",
        "FIELD_1789561072024_PRODUCT_OSM_MAP",
        "FIELD_1789561072024_PRODUCT_OSM_SURFACE_SLOT",
    ],
    "history": [
        "FIELD_1789561072024_HISTORY_OSM_STATE",
        "FIELD_1789561072024_HISTORY_OSM_MAP",
        "FIELD_1789561072024_HISTORY_OSM_SUMMARY",
        "FIELD_1789561072024_HISTORY_OSM_LOAD",
    ],
    "osm": [
        "FIELD_1789561072024_OSM_WATCH_BRIDGE_METHOD",
        "FIELD_1789561072024_OSM_CANONICAL_SUMMARY_DISTANCE",
        "FIELD_1789561072024_OSM_NORMALIZED_BREAKDOWN_DISTANCE",
    ],
    "auto_tests": ["FIELD_1789561072024_BRISK_WALK_TEST"],
    "finish_tests": ["FIELD_1789561072024_FINISH_DURATION_TEST"],
}

texts = {
    "policy": policy,
    "finish_policy": finish_policy,
    "watch": watch,
    "watch_view": watch_view,
    "tracker_app": tracker_app,
    "product": product,
    "history": history,
    "osm": osm,
    "auto_tests": auto_tests,
    "finish_tests": finish_tests,
}

for name, markers in required.items():
    for marker in markers:
        if marker not in texts[name]:
            raise SystemExit(f"{name}: required marker missing: {marker}")

POLICY.write_text(policy, encoding="utf-8")
FINISH_POLICY.write_text(finish_policy, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
WATCH_HISTORY.write_text(watch_history, encoding="utf-8")
WATCH_VIEW.write_text(watch_view, encoding="utf-8")
TRACKER_APP.write_text(tracker_app, encoding="utf-8")
PRODUCT.write_text(product, encoding="utf-8")
HISTORY.write_text(history, encoding="utf-8")
OSM.write_text(osm, encoding="utf-8")
AUTO_TESTS.write_text(auto_tests, encoding="utf-8")
FINISH_TESTS.write_text(finish_tests, encoding="utf-8")

print("FIELD FOLLOWUP 20260916 PATCH: OK")
