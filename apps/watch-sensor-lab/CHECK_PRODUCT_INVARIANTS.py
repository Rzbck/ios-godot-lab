#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent

def read(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")

errors = []

def require(text: str, token: str, label: str):
    if token not in text:
        errors.append(f"{label}: token absent: {token}")

iphone_root = read("iphone/Sources/TrackerApp.swift")
iphone_history = read("iphone/Sources/HealthWorkoutHistory.swift")
iphone_review = read("iphone/Sources/SessionReviewTimeline.swift")
iphone_model = read("iphone/Sources/TrackerModel.swift")
phone_bridge = read("iphone/Sources/PhoneRecentHistoryBridge.swift")

watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
reconciler = read("watch/Sources/WatchAutoHealthReconciler.swift")

# ------------------------------------------------------------
# A. Les surfaces doivent être RÉELLEMENT montées.
# ------------------------------------------------------------

require(
    iphone_root,
    "HistoryEntryView()",
    "Route iPhone historique"
)

require(
    iphone_history,
    "HealthWorkoutHistoryView()",
    "Entrée historique iPhone"
)

require(
    iphone_history,
    "ActivityReviewCard(",
    "Correction historique dans la fiche iPhone active"
)

require(
    iphone_review,
    "tracker.workflowCorrectHistoricalActivity(",
    "Action correction iPhone"
)

require(
    watch_root,
    "WatchVisualRecentPage(showHistory: $showHistory)",
    "Route Watch récentes"
)

require(
    watch_root,
    "WatchRecentHistoryView()",
    "Historique Watch monté"
)

require(
    watch_history,
    "model.workflowCorrectHistoricalActivity(",
    "Action correction Watch"
)

# ------------------------------------------------------------
# B. Une correction confirmée doit converger sur les 2 devices.
# ------------------------------------------------------------

require(
    watch_history,
    "func applyConfirmedActivity(",
    "Mise à jour locale Watch après correction"
)

require(
    reconciler,
    "WatchRecentHistoryStore.shared",
    "Reconciler -> historique Watch"
)

require(
    iphone_model,
    "recentHistoryBridge.publish(",
    "iPhone republie après résultat Watch"
)

require(
    phone_bridge,
    "healthBySession",
    "Digest Watch utilise aussi la vérité HealthKit"
)

require(
    iphone_model,
    '"replacement_verified"',
    "Persistance correction iPhone"
)

# ------------------------------------------------------------
# C. Transaction HealthKit :
#    créer -> relire/vérifier -> seulement ensuite supprimer.
# ------------------------------------------------------------

marker = "private func repairHistoricalActivityTransaction("
start = reconciler.find(marker)

if start < 0:
    errors.append("Transaction correction HealthKit absente")
else:
    tx = reconciler[start:]

    create = tx.find(
        "createHistoricalCorrectionWorkout("
    )

    verify = tx.find(
        "let verifiedWorkouts"
    )

    delete_original = tx.find(
        "try await deleteObjects(sourceWorkouts)"
    )

    rollback = tx.find(
        "try? await deleteObjects(replacementObjects)"
    )

    if min(create, verify, delete_original, rollback) < 0:
        errors.append(
            "Transaction HealthKit incomplète "
            "(create/verify/delete/rollback)"
        )
    elif not (
        create < verify < delete_original
    ):
        errors.append(
            "Ordre transactionnel invalide : "
            "la suppression précède la vérification"
        )

# ------------------------------------------------------------
# D. Les deux appareils doivent appeler le workflow COMMUN.
# ------------------------------------------------------------

for text, name in [
    (iphone_review, "iPhone"),
    (watch_history, "Watch"),
]:
    require(
        text,
        "workflowCorrectHistoricalActivity",
        f"Workflow commun {name}"
    )

if errors:
    print(
        "TRACKER PRODUCT INVARIANTS: FAIL",
        file=sys.stderr
    )

    for error in errors:
        print(f" - {error}", file=sys.stderr)

    sys.exit(1)

print("TRACKER PRODUCT INVARIANTS: OK")
print(" - mounted iPhone historical correction")
print(" - mounted Watch historical correction")
print(" - cross-device correction convergence")
print(" - HealthKit create/verify/delete ordering")
