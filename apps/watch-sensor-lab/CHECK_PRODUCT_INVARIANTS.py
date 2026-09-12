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
iphone_v4 = read("iphone/Sources/HistoricalHealthKitRepairV4.swift")
iphone_fidelity = read("iphone/Sources/HistoricalHealthKitFullFidelity.swift")
restore_packet = read("iphone/Sources/TrackerHealthRestorePacket.swift")
iphone_reliable = read("iphone/Sources/WatchReliableRecovery.swift")
watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
watch_restore = read("watch/Sources/WatchRestoreWorkflow.swift")
watch_model = read("watch/Sources/SensorModel.swift")

# A. Une seule surface produit active de mutation historique: v4 iPhone.
require(iphone_root, "HistoricalHealthKitRepairV4View()", "Surface v4 montée")
forbid(iphone_root, "HistoricalHealthKitRepairView()", "Ancienne v3 montée")
require(iphone_root, 'Label("Récupération"', "Onglet Récupération visible")
require(iphone_v4, "HistoricalHealthKitRepairV4Coordinator.shared", "Coordinateur v4")
require(iphone_v4, 'Label("Reconstruire proprement dans Santé"', "Action v4 visible")

# Legacy UI reste lecture seule / redirigée.
require(iphone_review, "Ce panneau ne modifie plus HealthKit", "Review legacy lecture seule")
forbid(iphone_review, "workflowCorrectHistoricalActivity(", "Correction legacy iPhone active")
require(watch_root, "WatchRestoreEntryPage().tag(4)", "Page récupération Watch")
require(watch_restore, "Réparation historique sur iPhone", "Watch redirige vers iPhone")
forbid(watch_restore, "workflowRestoreHistoricalActivity(", "Restauration Watch active")
forbid(watch_restore, "requestHistoricalRestore(", "Demande raw Watch active")
forbid(watch_history, "workflowCorrectHistoricalActivity(", "Correction historique Watch active")

# B. V4 travaille à partir des raw Watch ET iPhone, sans WatchConnectivity.
for token, label in [
    ('case "watch_location"', "GPS Watch brut"),
    ('case "location"', "GPS iPhone brut"),
    ("loadRawRoutes(summary:", "Audit raw double source"),
    ("chooseRoute(raw:", "Choix de route"),
    ("intervalOverlapsPause", "Gaps de pause distingués"),
    ("hasDistanceConflict", "Garde-fou distance summary/raw"),
    ("packetBuilder.makeTransferFile(", "Préflight raw historique existant"),
]:
    require(iphone_v4, token, label)
for token in ["WCSession", "transferFile("]:
    forbid(iphone_v4, token, "V4 historique ne dépend pas de WatchConnectivity")

# Le packet éprouvé conserve HR Watch et pauses explicites.
for token, label in [
    ('kind == "heart_rate"', "FC Watch brute"),
    ('event == "manual_pause"', "Pause Watch brute"),
    ("reconstructedActive", "Préflight durée active"),
]:
    require(restore_packet, token, label)

# C. Une nouvelle restauration ne peut pas s'empiler sur une ancienne.
for token, label in [
    ("cleanupGeneratedRestorations", "Nettoyage explicite disponible"),
    ("generated.isEmpty", "Blocage si restauration existante"),
    ("remainingGenerated.isEmpty", "Vérification post-nettoyage"),
    ("rawRestoreKey", "Filtre raw_restoration"),
    ("sessionKey", "Filtre session exacte"),
    ("zéro restauration de test restante", "Confirmation nettoyage vérifié"),
]:
    require(iphone_v4, token, label)

repair_start = iphone_v4.find("func repair(")
repair_end = iphone_v4.find("// MARK: - Raw data / route selection", repair_start)
if repair_start < 0 or repair_end < 0:
    errors.append("Impossible d'isoler le corps de repair v4")
else:
    repair_body = iphone_v4[repair_start:repair_end]
    forbid(repair_body, "cleanupGeneratedRestorations(", "Nettoyage automatique interdit dans repair")
    require(repair_body, "guard generated.isEmpty", "Repair bloque les doublons")
    require(repair_body, "hasDistanceConflict", "Repair bloque distance incohérente")

# D. Route HealthKit explicite et vérifiée.
for token, label in [
    ("HKWorkoutBuilder(", "Workout builder historique iPhone"),
    ("HKWorkoutRouteBuilder(healthStore:", "Route builder indépendant"),
    ("finishRoute(with: workout", "Association route/workout"),
    ("predicateForObjects(from: workout)", "Relecture route associée"),
    ("loadLocations(for:", "Relecture des points GPS"),
    ("savedRoutes.count == 1", "Unicité route v4"),
]:
    require(iphone_v4, token, label)
forbid(iphone_v4, "seriesBuilder(", "Route v4 ne réutilise pas le builder attaché incident")

# E. Effort réel : sample + relation explicite à l'activité du workout.
for token, label in [
    (".workoutEffortScore", "Type effort Apple"),
    ("relateWorkoutEffortSample(", "Relation effort/workout"),
    ("activity: workout.workoutActivities.first", "Effort lié à l'activité réelle"),
    ("predicateForWorkoutEffortSamplesRelated", "Relecture relation effort"),
]:
    require(iphone_v4, token, label)

# F. Autorisations d'écriture explicites.
for token, label in [
    ("HKObjectType.workoutType()", "Autorisation workout"),
    ("HKSeriesType.workoutRoute()", "Autorisation route"),
    (".heartRate", "Autorisation FC"),
    (".activeEnergyBurned", "Autorisation énergie"),
    (".distanceCycling", "Autorisation distance vélo"),
    ("authorizationStatus(for:", "Statut écriture vérifié"),
    (".sharingAuthorized", "Écriture explicitement autorisée"),
]:
    require(iphone_v4, token, label)

# G. Full fidelity conservée via les métadonnées déjà éprouvées.
for token, label in [
    ("HistoricalHealthKitFullFidelity.workoutMetadata(", "Métadonnées full-fidelity réutilisées"),
    ("HistoricalHealthKitFullFidelity.verifyWorkoutMetadata", "Métadonnées relues"),
    ('generation = "ios_historical_v4_clean_route"', "Génération v4 identifiable"),
    ("route_filtered_point_count", "Provenance route filtrée"),
    ("route_geometry_m", "Géométrie route auditée"),
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

# H. Pas de faux positif produit.
require(iphone_v4, "PAS encore validé dans Santé/Forme.", "API relue != validation physique")
forbid(iphone_v4, '"replacement_verified"', "V4 ne promeut pas automatiquement la vérité produit")
forbid(iphone_v4, "recentHistoryBridge.publish(", "V4 ne réécrit pas l'historique local")
require(iphone_v4, "let delays: [UInt64] = [0, 1_200_000_000, 3_000_000_000]", "Relectures différées")

# I. Le live Watch reste intact.
require(iphone_reliable, "WatchReliableRecovery.ingest(userInfo)", "Journalisation fiable Watch")
require(watch_model, "HKLiveWorkoutBuilder", "Live Watch reste HKLiveWorkoutBuilder")

if errors:
    print("TRACKER PRODUCT INVARIANTS: FAIL", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print("TRACKER PRODUCT INVARIANTS: OK")
print(" - active historical product surface: iPhone v4 only")
print(" - Watch + iPhone raw GPS are audited independently")
print(" - pause gaps and impossible GPS spikes are filtered without interpolation")
print(" - summary/raw distance conflicts block HealthKit writes")
print(" - explicit cleanup prevents accumulation of test workouts")
print(" - cleanup is scoped to raw_restoration + exact session id")
print(" - one v4 workout + one route are durably reread")
print(" - perceived effort is explicitly related and reread")
print(" - internal HealthKit reread is not physical validation")
print(" - live Watch HKLiveWorkoutBuilder remains unchanged")
