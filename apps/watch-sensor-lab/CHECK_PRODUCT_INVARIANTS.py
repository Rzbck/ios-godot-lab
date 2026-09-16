#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent


def read(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


errors: list[str] = []


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        errors.append(f"{label}: token absent: {token}")


def forbid(text: str, token: str, label: str) -> None:
    if token in text:
        errors.append(f"{label}: token interdit encore présent: {token}")


iphone_root = read("iphone/Sources/TrackerApp.swift")
iphone_review = read("iphone/Sources/SessionReviewTimeline.swift")
iphone_v4 = "\n".join([
    read("iphone/Sources/HistoricalHealthKitRepairV4.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4RouteData.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4RouteSegments.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4HealthCreate.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4HealthVerify.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4HealthHelpers.swift"),
    read("iphone/Sources/HistoricalHealthKitRepairV4View.swift"),
])
iphone_hk_audit = read("iphone/Sources/HistoricalManagedWorkoutAudit.swift")
iphone_fidelity = read("iphone/Sources/HistoricalHealthKitFullFidelity.swift")
restore_packet = read("iphone/Sources/TrackerHealthRestorePacket.swift")
iphone_reliable = read("iphone/Sources/WatchReliableRecovery.swift")
route_probe = read("iphone/Sources/HistoricalRouteDiagnosticProbe.swift")
diagnostic_api = read("iphone/Sources/DiagnosticService.swift")
diagnostic_client = read("WSL.ps1")
watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
watch_restore = read("watch/Sources/WatchRestoreWorkflow.swift")
watch_model = read("watch/Sources/SensorModel.swift")

# A. Une seule surface produit active de mutation historique: v4 iPhone.
require(iphone_root, "HistoricalRecoveryDiagnosticHostView()", "Hôte récupération diagnostique monté")
require(iphone_hk_audit, "HistoricalHealthKitRepairV4View()", "Surface v4 montée dans l'hôte")
forbid(iphone_root, "HistoricalHealthKitRepairView()", "Ancienne v3 montée")
require(iphone_root, 'Label("Récupération"', "Onglet Récupération visible")
require(iphone_v4, "HistoricalHealthKitRepairV4Coordinator.shared", "Coordinateur v4")
require(iphone_v4, '"Reconstruire proprement dans Santé"', "Action v4 visible")

# Le dossier forensic actif doit être récupérable sans retaper l'ID ni la distance.
for token, label in [
    ('sessionID: "1789374106082"', "Preset forensic session exacte"),
    ("authoritativeDistanceMeters: 9052.45442214305", "Preset forensic distance exacte"),
    ("targetActivity: .cycling", "Preset forensic sport cible"),
    ('Label("Dossiers de récupération"', "Surface dossiers de récupération"),
    ("loadRecoveryPreset", "Chargement dossier en un geste"),
    ("orphanCoordinator.inspect()", "Inspection automatique lecture seule"),
    ('"Détails / saisie manuelle avancée"', "Saisie manuelle reléguée en avancé"),
]:
    require(iphone_v4, token, label)

# Diagnostic d'un workout normal Tracker: strictement lecture seule.
for token, label in [
    ("HistoricalManagedWorkoutAudit", "Audit workout Tracker non-restauration"),
    ("HKSampleQuery", "Audit HealthKit par requête"),
    ("sourceRevision.source.bundleIdentifier", "Audit source du workout"),
    ("selected_activity", "Audit activité sélectionnée live"),
    ("healthkit_initial_activity", "Audit activité HealthKit initiale"),
]:
    require(iphone_hk_audit, token, label)
for token in ["healthStore.delete(", "healthStore.save(", "HKWorkoutBuilder(", "HKWorkoutRouteBuilder("]:
    forbid(iphone_hk_audit, token, "Audit HealthKit doit rester lecture seule")

# Legacy UI historique ne remonte pas comme second chemin de mutation.
require(iphone_review, "Ce panneau ne modifie plus HealthKit", "Review legacy lecture seule")
forbid(iphone_review, "workflowCorrectHistoricalActivity(", "Correction legacy iPhone active")
require(watch_restore, "Réparation historique sur iPhone", "Watch redirige vers iPhone")
forbid(watch_restore, "workflowRestoreHistoricalActivity(", "Restauration Watch active")
forbid(watch_restore, "requestHistoricalRestore(", "Demande raw Watch active")
forbid(watch_history, "workflowCorrectHistoricalActivity(", "Correction historique Watch active")

# B. Raw Watch + iPhone, compteurs et pauses restent les sources de vérité.
for token, label in [
    ('case "watch_location"', "GPS Watch brut"),
    ('case "location"', "GPS iPhone brut"),
    ("loadRawRoutes(summary:", "Audit raw double source"),
    ("chooseRoute(", "Choix de route"),
    ("counterAgrees", "Validation compteur raw"),
    ("distanceReferenceSource", "Source de distance explicite"),
    ("intervalOverlapsPause", "Pauses distinguées"),
    ("hasDistanceConflict", "Garde-fou distance"),
    ("packetBuilder.makeTransferFile(", "Préflight raw historique"),
]:
    require(iphone_v4, token, label)
for token in ["WCSession", "transferFile("]:
    forbid(iphone_v4, token, "V4 historique ne dépend pas de WatchConnectivity")
for token, label in [
    ('kind == "heart_rate"', "FC Watch brute"),
    ('event == "manual_pause"', "Pause Watch brute"),
    ("reconstructedActive", "Préflight durée active"),
]:
    require(restore_packet, token, label)

# C. Une seule restauration et nettoyage exact-session.
for token, label in [
    ("cleanupGeneratedRestorations", "Nettoyage explicite disponible"),
    ("guard generated.isEmpty", "Repair bloque les doublons"),
    ("remainingGenerated.isEmpty", "Vérification post-nettoyage"),
    ("rawRestoreKey", "Filtre raw_restoration"),
    ("sessionKey", "Filtre session exacte"),
    ("zéro restauration de test restante", "Confirmation nettoyage vérifié"),
]:
    require(iphone_v4, token, label)

repair_start = iphone_v4.find("func repair(")
repair_end = iphone_v4.find("// MARK: - Raw data / route selection", repair_start)
if repair_start < 0 or repair_end < 0:
    errors.append("Impossible d'isoler repair v4")
else:
    repair_body = iphone_v4[repair_start:repair_end]
    forbid(repair_body, "cleanupGeneratedRestorations(", "Nettoyage automatique interdit dans repair")
    require(repair_body, "hasDistanceConflict", "Repair exige une distance raw autoritaire")
    require(repair_body, "hasSevereRouteCounterConflict", "Repair garde le veto route/compteur")
    require(repair_body, "segmentRouteForHealthKit", "Repair segmente la route avant écriture")

# D. Route finale: revenir à la reconstruction riche et couper les raccords impossibles,
# au lieu de supprimer des minutes entières de coordonnées post-pause.
for token in ["counterPostPauseReacquisitionFilter", "earliestCounterStableSuffixStart", "postPauseSegmentHasCounterConflict"]:
    forbid(iphone_v4, token, "Filtre post-pause agressif interdit dans candidat final")
for token, label in [
    ("counterAwareFilter", "Débruitage compteur local conservé"),
    ("nextRaw.timestamp - lastAccepted.timestamp > 3.0", "Débruitage ne crée pas de gros trou"),
    ("mergeActiveGaps", "Fusion des vrais trous raw"),
    ("primaryRawPoints", "Fusion distingue trou raw et trou de filtre"),
    ("segmentRouteForHealthKit", "Segmentation HealthKit des discontinuités"),
    ("isHardRouteDiscontinuity", "Détection de raccord physiquement impossible"),
    ("segmentedGeometry", "Géométrie sans raccord entre segments"),
    ('"com.rzbck.watchsensorlab.route_segment_index"', "Index de segment durable"),
    ('"com.rzbck.watchsensorlab.route_segment_count"', "Nombre de segments durable"),
    ("createdRoutes", "Plusieurs routes HealthKit prises en charge"),
    ("savedRoutes.count == expectedRouteCount", "Tous les segments sont relus"),
    ("Set(savedRoutes.map(\\.uuid)) == routeUUIDs", "Identité exacte des segments relue"),
    ("finishRoute(with: workout", "Chaque route est associée au workout"),
    ("no_interpolation", "Stratégie sans interpolation déclarée"),
]:
    require(iphone_v4, token, label)
forbid(iphone_v4, "savedRoutes.count == 1", "Le candidat final ne doit plus imposer une route unique")

# E. Correctif 0,99 km: les scalaires connus sont répartis uniquement sur les
# intervalles ACTIFS; HealthKit ne doit plus proratiser un sample couvrant tout le mur.
for token, label in [
    ("activeIntervals(payload:", "Construction intervalles actifs"),
    ("makeDistributedQuantitySamples", "Répartition des totaux par intervalle actif"),
    ('"active_interval_duration_weighted_totals"', "Stratégie scalaire durable"),
    ("assertBuilderTotals", "Statistiques builder vérifiées avant finish"),
    ("builder.statistics(for: type)", "Statistique builder HealthKit"),
    ("verifyWorkoutStatistics", "Statistiques du workout final relues"),
    ("workout.statistics(for: type)", "Statistique finale HealthKit"),
    ("distance workout HealthKit absente", "Distance finale obligatoire"),
]:
    require(iphone_v4, token, label)

# F. Effort: pour un workout simple, relation au niveau workout (activity:nil),
# puis relecture par le helper qui utilise le même prédicat.
require(iphone_v4, "HistoricalHealthKitFullFidelity.savePerceivedEffort(", "Écriture effort via helper éprouvé")
require(iphone_v4, "HistoricalHealthKitFullFidelity.verifyPerceivedEffort(", "Relecture effort via helper éprouvé")
require(iphone_fidelity, "activity: nil", "Effort relié au workout simple")
require(iphone_fidelity, "predicateForWorkoutEffortSamplesRelated", "Relecture relation effort")
forbid(iphone_v4, "activity: workout.workoutActivities.first", "Relation effort activité spécifique retirée du v4")

# G. Source application: HealthKit doit attribuer le workout au bundle réellement installé.
for token, label in [
    ("workout.sourceRevision.source.bundleIdentifier", "Source HealthKit relue"),
    ("Bundle.main.bundleIdentifier", "Bundle app attendu"),
    ("source HealthKit inattendue", "Échec si attribution incorrecte"),
]:
    require(iphone_v4, token, label)
# Le brand forcé a déjà produit un titre Watch Tracker à la place de Vélo: interdit.
forbid(iphone_v4, "HKMetadataKeyWorkoutBrandName:", "Brand name forcé interdit dans v4")
forbid(iphone_fidelity, "HKMetadataKeyWorkoutBrandName:", "Brand name forcé interdit dans helper")
require(
    iphone_v4,
    "sanitized.removeValue(forKey: HKMetadataKeyWorkoutBrandName)",
    "Brand supprimé centralement avant écriture HealthKit",
)

# H. Route + quantités + full fidelity restent vérifiées.
for token, label in [
    ("HKWorkoutBuilder(", "Workout builder historique iPhone"),
    ("HKWorkoutRouteBuilder(healthStore:", "Route builder indépendant"),
    ("predicateForObjects(from: workout)", "Relecture routes associées"),
    ("loadLocations(for:", "Relecture points GPS"),
    ("verifyQuantitySamples(", "Relecture quantités générées"),
    ("HistoricalHealthKitFullFidelity.workoutMetadata(", "Métadonnées full fidelity"),
    ("HistoricalHealthKitFullFidelity.verifyWorkoutMetadata", "Métadonnées full fidelity relues"),
    ('generation = "ios_historical_v4_segmented_route"', "Génération finale identifiable"),
]:
    require(iphone_v4, token, label)
for token, label in [
    ("HKMetadataKeyAverageSpeed", "Vitesse moyenne"),
    ("HKMetadataKeyMaximumSpeed", "Vitesse maximale"),
    ("HKMetadataKeyElevationAscended", "Dénivelé positif"),
    ("HKMetadataKeyElevationDescended", "Dénivelé négatif"),
    ("HKMetadataKeyWeatherTemperature", "Météo"),
]:
    require(iphone_fidelity, token, label)

# I. L'API relue n'est jamais présentée comme validation produit physique.
require(iphone_v4, "PAS encore validé dans Santé/Forme.", "API relue != validation physique")
forbid(iphone_v4, '"replacement_verified"', "Pas de promotion automatique de vérité produit")
forbid(iphone_v4, "recentHistoryBridge.publish(", "V4 ne réécrit pas l'historique local")
require(iphone_v4, "let delays: [UInt64] = [0, 1_200_000_000, 3_000_000_000]", "Relectures différées")

# J. Le live Watch reste intact.
require(iphone_reliable, "WatchReliableRecovery.ingest(userInfo)", "Journalisation fiable Watch")
require(watch_model, "HKLiveWorkoutBuilder", "Live Watch reste HKLiveWorkoutBuilder")

# K. API diagnostic USB lecture seule et forensic raw conservé.
for token, label in [
    ("DiagnosticService.shared.start(tracker: tracker)", "API diagnostic démarrée avec TrackerModel"),
    ("DiagnosticService.shared.stop()", "API diagnostic arrêtée hors premier plan"),
]:
    require(iphone_root, token, label)
for token, label in [
    ('protocolName = "wsl_diag_v1"', "Version protocole diagnostic"),
    ("devicePort: UInt16 = 37991", "Port diagnostic stable"),
    ('case "recovery"', "Endpoint recovery"),
    ("recovery.inspect(sessionID: sessionID)", "Recovery réutilise inspection lecture seule"),
    ("HistoricalRouteDiagnosticProbe().inspect", "Forensic GPS/compteur brut"),
    ('"route_diagnostics"', "Fenêtres forensic exposées"),
    ("isDisallowedNetworkPath", "Wi-Fi/cellulaire refusés"),
    ('"read_only": true', "Contrat lecture seule"),
]:
    require(diagnostic_api, token, label)
for token in ["cleanupGeneratedRestorations(", "repair(", "healthStore.delete(", "healthStore.save(", "HKWorkoutBuilder(", "HKWorkoutRouteBuilder("]:
    forbid(diagnostic_api, token, "API diagnostic ne doit muter aucun objet Santé")
for token, label in [
    ("HistoricalRouteDiagnosticProbe", "Probe forensic"),
    ('source: "WATCH"', "GPS Watch inspecté"),
    ('source: "IPHONE"', "GPS iPhone inspecté"),
    ("counterEstimate", "Compteur Watch interpolé de façon bornée"),
    ("bridge_outside_counter_budget", "Cause non-filtrable visible"),
    ("path_excess_m", "Excès route/compteur visible"),
]:
    require(route_probe, token, label)
for token in ["HealthKit", "healthStore", "HKWorkout", "HKSample", "delete(", "save("]:
    forbid(route_probe, token, "Probe forensic indépendant de HealthKit")
for token, label in [
    ("pymobiledevice3", "Client Windows réutilise pymobiledevice3"),
    ("usbmux", "Transport USB/usbmux"),
    ("wsl_diag_v1", "Protocole client partagé"),
    ("ROUTE DIAGNOSTICS (READ-ONLY)", "Forensic affiché dans le terminal"),
    ("finally", "Forward usbmux nettoyé"),
]:
    require(diagnostic_client, token, label)

if errors:
    print("TRACKER PRODUCT INVARIANTS: FAIL", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print("TRACKER PRODUCT INVARIANTS: OK")
print(" - active historical mutation surface: iPhone v4 only")
print(" - known forensic recovery can be loaded without manual IDs")
print(" - historical cleanup remains exact-session and explicit")
print(" - richer pre-aggressive route selection is preserved")
print(" - impossible joins are split into independent HealthKit route samples")
print(" - no GPS coordinate is fabricated or interpolated")
print(" - scalar distance/energy totals are confined to active intervals")
print(" - builder and final workout statistics must equal Tracker totals")
print(" - perceived effort is related and reread at workout level")
print(" - generated workout source bundle must match the installed app")
print(" - no forced workout brand can replace the visible activity type")
print(" - internal HealthKit reread is not physical validation")
print(" - live Watch HKLiveWorkoutBuilder remains unchanged")
print(" - USB diagnostic API and raw route forensic remain read-only")
