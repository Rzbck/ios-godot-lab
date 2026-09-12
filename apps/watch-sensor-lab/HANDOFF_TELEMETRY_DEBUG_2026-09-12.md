# HANDOFF — Watch Sensor Lab Telemetry / Debug — 2026-09-12

## Objectif

Faire de la télémétrie une infrastructure permanente de Watch Sensor Lab, et non un patch de diagnostic ponctuel. Pendant le développement, un iPhone branché en USB à Windows doit pouvoir fournir en direct les actions utilisateur, transitions d’état, erreurs et snapshots complets utiles au debug, afin d’éviter les captures d’écran et retranscriptions manuelles répétitives.

Chaque nouvelle fonction importante doit étendre la télémétrie correspondante.

## Dépôt / chantier

- dépôt : `Rzbck/ios-godot-lab`
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-healthkit-historical-unification`
- branche : `fix/watch-healthkit-historical-unification-20260912`
- HEAD distant au début de ce handoff : `0200210a5807542d1fc80ce4f23da6785a5b301f`
- dernier SHA contenant le code app télémétrie compilé en CI : `f18cb22a2b8d6cdef6df18f25852c5ac7bae2115`
- CI : run `34687759161`, job `103537648701`, **success complet** : invariants, projet iPhone, build iPhone, build Watch, déclarations HealthKit, assemblage companion, packaging.
- les commits après `f18cb22...` concernent le contrat/documentation et le bridge PowerShell hôte ; avant installation, toujours reprendre le HEAD exact via le workflow `UPDATE_WATCH_SENSOR_LAB.ps1`.

## Architecture télémétrie mise en place

### Core partagé

`Shared/TelemetryShared.swift`

- schéma JSON : `watch_sensor_lab_telemetry_v1`
- marqueur unified log : `WSL_TELEMETRY|`
- types : `lifecycle`, `action`, `event`, `snapshot`, `error`, `relay`
- identité dans chaque record : timestamp, uptime, sequence, boot ID, platform, build SHA
- écriture unified logging + JSONL local borné/rotatif
- la télémétrie ne doit jamais bloquer ni faire échouer le produit
- compilé dans les targets iPhone et Watch via leurs `project.yml`

### iPhone

`iphone/Sources/TrackerTelemetryCoordinator.swift`

- observation centralisée de `TrackerModel` avec Combine, indépendante de la composition SwiftUI
- snapshot `app_state` environ toutes les 2 s + sur transitions importantes
- état couvert : écran/tab, phase/session, activité choisie/effective, durée, distance, vitesse, altitude/dénivelé, FC, énergie, cadence, pas, GPS/route, Watch reachable, autorisation Santé, status/pending command, autopause, finish-review, dernier summary, historique recovery et audits v4

`iphone/Sources/TrackerApp.swift`

- lifecycle app
- changements de tab
- scène active/background
- tap global x/y
- actions sémantiques principales
- summary/post-session

`iphone/Sources/HistoricalManagedWorkoutAudit.swift`

- snapshot `healthkit_managed_workout_audit`
- UUID, session ID, activité HK, source/version, selected activity, initial activity, algo, génération, etc.

### Windows USB

`apps/watch-sensor-lab/LIVE_TELEMETRY.ps1`

Commande normale :

```powershell
.\apps\watch-sensor-lab\LIVE_TELEMETRY.ps1
```

Le script utilise prioritairement :
`E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv\Scripts\python.exe`

Transport : `pymobiledevice3 syslog live -m WSL_TELEMETRY` via USB.

Artefacts hôte :

- `artifacts/watch-sensor-lab/_TELEMETRY/<timestamp>/events.jsonl`
- `artifacts/watch-sensor-lab/_TELEMETRY/LATEST_EVENT.json`
- `artifacts/watch-sensor-lab/_TELEMETRY/LATEST_SNAPSHOT.json`
- `artifacts/watch-sensor-lab/_TELEMETRY/LATEST_STATE.json`

`LATEST_STATE.json` agrège les derniers snapshots nommés pour ne pas perdre, par exemple, l’audit HealthKit lorsqu’un heartbeat `app_state` arrive ensuite.

### Contrat durable

`apps/watch-sensor-lab/TELEMETRY_CONTRACT.md`

Règle produit : une nouvelle fonction ou machine d’état importante n’est pas considérée correctement instrumentée tant que les actions, résultats/erreurs et états durables nécessaires au debug n’ont pas été ajoutés à la télémétrie.

Éviter le spam haute fréquence : les raw capteurs restent dans les flux/raw recorder existants ; la télémétrie expose des transitions et snapshots synthétiques bornés.

## Watch — état actuel

Le core télémétrie partagé compile dans la target Watch, mais le relay direct des interactions UI Watch vers l’iPhone n’est **pas encore physiquement validé ni entièrement câblé**.

Le flux Watch déjà reflété dans `TrackerModel` (workout/metrics/authority/connectivité) apparaît dans les snapshots iPhone. Pour obtenir aussi les actions UI Watch exactes (ex. écran/bouton de confirmation de fin), l’extension suivante doit réutiliser le `WCSessionDelegate` déjà possédé par `SensorModel` et ne jamais installer un second delegate concurrent.

## Observation HealthKit à préserver

L’audit matériel a identifié deux workouts Tracker normaux récents, tous deux Vélo, qui ne sont pas la session historique à restaurer et ne doivent pas être supprimés :

- session `1789198788819`, UUID `71536652-B018-4A94-9E1A-2246E7DB11B6`, Vélo, 12/09/2026 09:39:48, 831 s
- session `1789196258375`, UUID `BAEABB89-8959-4E19-B518-7615A341B992`, Vélo, 12/09/2026 08:57:38, 873 s

Ces deux workouts ont `selected_activity=cycling`, `healthkit_initial_activity=cycling`, algo `tracker-v4-20260910`.

Session historique cible distincte : `1789141684582`.

## Ce qui est validé

- architecture télémétrie iPhone compile
- core partagé compile iPhone + Watch
- CI `f18cb22...` verte intégrale
- bridge PowerShell présent dans le dépôt
- contrat permanent de télémétrie présent

## Ce qui n’est PAS encore validé physiquement

- nouvelle IPA télémétrie installée sur iPhone/Watch
- réception réelle de `WSL_TELEMETRY|...` via `LIVE_TELEMETRY.ps1` sous Windows
- création de `LATEST_STATE.json` pendant une session réelle
- couverture directe des actions UI Watch

## Prochaine étape exacte

1. Synchroniser le worktree avec la branche et récupérer une IPA exact-SHA via `UPDATE_WATCH_SENSOR_LAB.ps1`.
2. Installer par-dessus l’app avec iLoader, sans désinstallation.
3. Garder l’iPhone branché USB, ouvrir l’app, puis lancer `LIVE_TELEMETRY.ps1`.
4. Vérifier physiquement qu’un snapshot `iphone.app_state` arrive toutes les ~2 s et qu’en ouvrant `Récupération`, `iphone.healthkit_managed_workout_audit` apparaît dans `LATEST_STATE.json`.
5. Une fois le bridge validé, l’utiliser comme workflow normal de debug et arrêter de demander des captures d’écran quand l’information est déjà dans la télémétrie.
6. Ensuite étendre le relay Watch pour les actions UI exactes et reprendre le diagnostic Recovery / finish-review depuis les logs structurés.

## Règles / éléments à ne pas modifier

- ne pas supprimer les deux Vélo normaux listés ci-dessus
- ne pas toucher aux raw de la session `1789141684582`
- ne pas créer un deuxième système de transport concurrent si le bridge USB suffit
- ne pas créer un deuxième `WCSessionDelegate` côté Watch
- ne pas loguer secrets/tokens ni des flux capteurs haute fréquence non bornés
- conserver le workflow exact-SHA et iLoader existants
- PowerShell utilisateur : commandes courtes/scripts existants, pas de gros blocs interactifs `& { ... }`
