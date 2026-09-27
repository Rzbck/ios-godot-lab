# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît le ciel, détoure plusieurs nuages, stabilise leurs IDs et affiche une estimation pédagogique de masse d'eau/glace condensée.

Priorité V10 : **rendre les diagnostics autonomes sur l'iPhone pendant une session longue, synchronisables après coup, et mesurer la vraie cadence sans le throttle fixe V9**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-session-recorder-v10-20260927` ;
- base V10 : `e361588d40ba4479eeb3383e6c6e149b82022f94` (V9 final CI + testé physiquement) ;
- SHA applicatif V10 validé CI : `c598bc61ddf8b642a025a73e395959e7806d320c` ;
- run CI applicatif : `36331792121` — **SUCCESS** ;
- version app : `0.10.0` ; build `10` ;
- `main` non modifié ;
- autres applications/workflows hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V10 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-session-recorder-v10`.

Le HEAD contenant ce HANDOFF et les scripts Windows est postérieur au SHA applicatif ci-dessus : **valider CI + artifact exact-SHA du HEAD final avant installation**.

## Source de vérité matérielle jusqu'à V9

V9 final installé/testé : `e361588d40ba4479eeb3383e6c6e149b82022f94`.

Résultats réels de la session V9 fournie par l'utilisateur :

- garde ciel ADE20K nettement meilleur hors ciel ; arbre/bâtiment globalement mieux séparés ;
- soleil direct / flare / reflet de vitre restent une source claire de faux positifs ;
- 824 mesures exploitables ;
- pipeline moyen ≈ `40.7 ms`, P95 ≈ `44.1 ms` ;
- quand les deux IA tournent : prétraitement ≈ `2.7 ms`, SegFormer B0 ciel ≈ `22.6 ms`, UCloudNet ≈ `11.4 ms`, post ≈ `4.5 ms` ;
- cadence réelle ≈ `10.2 Hz` malgré ~40 ms de calcul, car V9 imposait encore `minimumAnalysisInterval = 70 ms` et rejetait typiquement deux frames ;
- thermique observé `nominal` ;
- aucun cas observé `visible tracks > raw detections` : le correctif fantômes V8 fonctionne ;
- les types de nuages peuvent encore osciller ;
- le ring diagnostic V9 (~20 s) et le watcher PC ne conviennent pas à une session longue autonome.

Ces observations matérielles priment sur toute hypothèse.

## Architecture IA conservée

```text
caméra AVFoundation
    |
SegFormer B0 ADE20K 384×384
  sky = classe ADE20K index 2
    +
UCloudNet k=2
  portrait 304×544 / paysage 544×304
    |
cloud = UCloudNet >= 0.52 ET sky >= 0.55
si ciel confirmé < 5 % => zéro nuage
    |
composantes connexes
    |
tracker temporel
    |
overlay + labels
```

V10 ne modifie pas les modèles ni les seuils. Le faux positif glare est **mesuré**, pas encore filtré agressivement.

## Changements V10

### 1. Recorder de session persistant sur iPhone

Nouveau `CloudSessionRecorder` sous `Application Support/CloudWeightSessionsV10`.

Une session démarre avec la caméra et se termine à l'arrêt normal de `CameraService`. Les données restent sur l'iPhone sans PC, Wi-Fi ou API active.

Structure :

```text
session-<epoch>-<build>/
  manifest.json
  events.ndjson
  telemetry/
    telemetry-0001.ndjson
    telemetry-0002.ndjson
    ...
  visual/
    visual.ndjson
    keyframes/*.jpg
    bursts/*.jpg
```

Politique :

- télémétrie numérique à chaque analyse ;
- chunks de `5000` enregistrements ;
- image de timeline ~`1 fps` ;
- burst ~`4 fps` pendant ~`4 s` autour d'événements intéressants ;
- JPEG max `640 px`, qualité ~`0.34` ;
- événements : création/perte de track, saut masque, entrée/sortie ciel, rejet scène, changement thermique, glare/highlights ;
- cap visuel session ~`320 MB` ;
- cap global ~`512 MB`, maximum `8` sessions ;
- sessions anciennes supprimées seulement par la politique de rétention ;
- dossier exclu de la sauvegarde iCloud ;
- au prochain lancement, une session restée `recording` après interruption devient `interrupted` ;
- atteindre le quota visuel stoppe les JPEG mais pas la télémétrie.

Attention : la compression visuelle tourne sur une queue `utility`, mais son coût thermique/CPU/GPU n'est **pas encore validé physiquement**.

### 2. Télémétrie enrichie glare/exposition

Ajouts dans `CloudTelemetrySnapshot` :

- `sceneDarkPercent` ;
- `sceneBrightPercent` ;
- `sceneClippedPercent` ;
- `sceneNeutralHighlightPercent` ;
- `cameraISO` ;
- `cameraExposureMilliseconds` ;
- `cameraExposureTargetOffset`.

Le garde sombre reste conservateur ; V10 ne rejette pas automatiquement une scène uniquement parce qu'elle contient du glare.

### 3. Suppression du throttle fixe 70 ms

`minimumAnalysisInterval` est supprimé.

Reste :

- `analysisInFlight` ;
- `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true`.

But : mesurer la vraie cadence du pipeline séquentiel. Avec les chiffres V9, ~15 Hz est une **hypothèse à vérifier sur iPhone**, pas une validation.

### 4. Couleurs persistantes par track ID

L'overlay et le label utilisent désormais une palette déterministe basée sur `track.id`.

Le type (`Cumulus`, `Cirrus`, etc.) reste affiché mais ne change plus la couleur du nuage quand la classification oscille.

### 5. API locale sessions V10

Ancienne API live conservée pour compatibilité. Nouveaux endpoints authentifiés :

- `GET /api/v1/sessions` ;
- `GET /api/v1/sessions/<id>/manifest` ;
- `GET /api/v1/sessions/<id>/files` ;
- `GET /api/v1/sessions/<id>/file?path=...`.

L'API est utilisée **après** la session. Aucun upload automatique Internet/VPS/GitHub.

## Nouveau workflow Windows post-session

Script :

`apps/cloud-weight-lab/SYNC_CLOUD_WEIGHT_SESSION.ps1`

Usage normal après retour sur le même Wi-Fi :

```powershell
.\apps\cloud-weight-lab\SYNC_CLOUD_WEIGHT_SESSION.ps1 -OpenFolder
```

Comportement prévu :

- découvre/appaire l'iPhone ;
- synchronise la dernière session par défaut ;
- `-SessionId` cible une session ;
- `-AllSessions` synchronise tout ;
- téléchargements parallèles, reprenables par taille ;
- concatène les chunks en `telemetry.ndjson` ;
- produit `diagnostic-preview.mp4` avec les timestamps réels si `ffmpeg` est présent ;
- supprime les JPEG PC après MP4 réussi sauf `-KeepFrames` ;
- supprime les chunks locaux après fusion sauf `-KeepRaw` ;
- ne supprime pas la session source sur l'iPhone.

**Ce script n'a PAS encore été exécuté sur le Windows réel de l'utilisateur.** Ne pas le présenter comme validé avant ce test.

## Pipeline IPA

`UPDATE_CLOUD_WEIGHT_LAB.ps1` vise désormais :

`fix/cloud-weight-session-recorder-v10-20260927`

Commande normale depuis le worktree V10 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Puis installation de l'IPA exact-SHA avec iLoader.

## Validation CI V10 applicative

SHA : `c598bc61ddf8b642a025a73e395959e7806d320c`

Run : `36331792121` — **SUCCESS**.

Validé :

- poids/modèles Core ML épinglés ;
- UCloudNet portrait/paysage + SegFormer B0 ADE20K ;
- XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- build iPhone Release non signé ;
- contrat bundle et trois `.mlmodelc` ;
- packaging IPA exact-SHA ;
- artifact uploadé.

Important : `build-for-testing` compile la cible XCTest mais **n'exécute pas** les tests.

## NON VALIDÉ PHYSIQUEMENT EN V10

- démarrage/fin réelle du recorder sur iPhone ;
- persistance après 5–10 min, puis session longue ;
- récupération d'une session terminée après retour Wi-Fi ;
- `SYNC_CLOUD_WEIGHT_SESSION.ps1` sur Windows réel ;
- MP4 généré avec timings de session ;
- rétention/quota/interruption sur appareil ;
- cadence réelle après suppression du throttle ;
- chauffe/batterie/mémoire avec recorder + JPEG ;
- couleurs de track réellement stables à l'écran ;
- métriques clipped/highlight/ISO/exposure corrélées aux faux positifs soleil/reflet ;
- comportement glare corrigé (V10 mesure, mais ne prétend pas corriger ce défaut) ;
- session d'une heure.

## Test matériel V10 prioritaire

Premier test : **5 à 10 minutes**, pas une heure avant validation du stockage/sync.

1. installer l'IPA exact-SHA V10 ;
2. ouvrir l'app dehors **sans lancer PowerShell** ;
3. filmer vrai ciel, arbres/feuillage, bâtiments, main/peau, plusieurs nuages ;
4. faire pan lent/rapide + portrait/paysage ;
5. si possible inclure une scène lumineuse/reflet sans regarder directement le soleil ;
6. vérifier visuellement stabilité des couleurs/IDs ;
7. quitter l'app pour terminer la session ;
8. revenir sur le même Wi-Fi que le PC ;
9. lancer `SYNC_CLOUD_WEIGHT_SESSION.ps1 -OpenFolder`, toucher `API` seulement si demandé ;
10. vérifier manifest, events, telemetry et MP4 ;
11. seulement après ce test, envisager une session ~1 h.

## Performance suivante — V11 séparée

Ne pas implémenter dans V10.

Après mesure réelle V10 : comparer le pipeline séquentiel V10 à une branche expérimentale où SegFormer B0 et UCloudNet lancent des prédictions Core ML concurrentes sur la même frame.

Les chiffres V9 donnent une borne théorique proche de 30 ms en parallélisme parfait, mais Core ML peut faire entrer les modèles en concurrence sur les mêmes compute units. Mesurer A/B sur iPhone avant toute conclusion.

## Télémétrie globale VPS — chantier futur séparé

L'utilisateur souhaite à terme une couche commune de télémétrie pour plusieurs apps iPhone/autres via son VPS, utilisable hors LAN/4G puis partageable via export ou repo privé.

Hors scope V10. Le format session/chunks V10 est volontairement réutilisable comme base future. Aucun secret ni donnée utilisateur ne doit être poussé dans le repo public.

## À ne pas modifier

- `main` sans accord explicite ;
- les autres apps/workflows ;
- les modèles/seuils avant le test matériel V10 ;
- ne pas fusionner le chantier VPS dans cette branche ;
- ne pas annoncer la cadence ~15 Hz ou la session longue comme validées avant mesure réelle.

## Prochaine étape exacte

1. valider CI complète + artifact du HEAD final contenant ce HANDOFF/scripts ;
2. créer/synchroniser le worktree Windows V10 ;
3. récupérer l'IPA exact-SHA avec `UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
4. installer via iLoader ;
5. effectuer le test autonome 5–10 min ;
6. synchroniser la session après coup avec `SYNC_CLOUD_WEIGHT_SESSION.ps1` ;
7. analyser performance, tracking, glare et fiabilité du recorder ;
8. seulement ensuite ouvrir V11 performance concurrence Core ML.
