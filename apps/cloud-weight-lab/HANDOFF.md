# HANDOFF — Cloud Weight Lab V12 WIP

## Objectif

Application iPhone temps réel qui segmente les nuages, suit des régions persistantes et estime la masse d'eau/glace condensée.

V12 traite les problèmes réellement observés au crépuscule et dans le workflow diagnostic :

- conserver les nuages visibles lorsque la couleur/luminance du ciel change ;
- ne plus utiliser `sky_probability` ADE20K comme veto absolu ;
- utiliser ADE20K comme couche sémantique anti-faux-positifs (arbres, bâtiments, personnes, plantes, murs) ;
- stabiliser le garde ciel dans le temps ;
- enrichir la télémétrie pour expliquer chaque décision ;
- gérer basse lumière sans casser le jour ;
- paralléliser intelligemment SegFormer/UCloudNet et mesurer le gain réel ;
- rendre la synchro Windows automatique, persistante, reprenable et liée au bon build.

## Dépôt / branche / état Git

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche : `fix/cloud-weight-twilight-autosync-v12-20260927`
- base V12 : V11 final `c69a673e9dc00355ae744a651341ae5379c9029f`
- checkpoint code V12 actuel : `c1fa3ae023bbd386e6494245e5e33939a2d741a7`
- HEAD juste avant la présente correction documentaire : `9089dfbf3001b3047bb07a1662a05e164b468ae6` (docs seulement, parent = checkpoint code ci-dessus)
- worktree Windows attendu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-twilight-autosync-v12`
- `main` reste hors chantier.

À la reprise : vérifier le HEAD réel de la branche, le worktree et `git status` avant toute modification. Le commit contenant ce HANDOFF est nécessairement postérieur au checkpoint code.

## Source matérielle du chantier

La session crépuscule analysée provenait du build V10 `1a955d01632557f3247bb49c858f8c96f3aeaf27`, pas de V11/V12.

Observation image/MP4 + télémétrie :

- les gros nuages gris/blancs restaient visiblement présents ;
- ADE20K pouvait pourtant faire tomber le ciel brut vers ~0–3 % ;
- l'ancien garde coupait alors UCloudNet ou rejetait ses pixels car il exigeait `skyProbability >= 0.55` ;
- quelques instants plus tard la même scène pouvait remonter proche de 100 % de ciel ;
- cela provoquait `sky_enter` / `sky_exit` / `mask_jump` très fréquents ;
- le passage problématique existait avec orientation paysage stable : ce n'était pas principalement un bug de rotation.

Cause racine retenue : garde ciel trop brutal pour crépuscule/basse lumière.

## V12 — changements réellement présents au checkpoint code `c1fa3ae...`

### Garde sémantique ADE20K

Le SegFormer B0 ADE20K converti Core ML expose maintenant :

- `sky_probability`
- `blocker_probability`
- `tree_probability`
- `building_probability`
- `person_probability`
- `plant_probability`
- `wall_probability`

UCloudNet reste le détecteur de nuages. ADE20K devient une couche de contexte sémantique : une faible probabilité `sky` ne suffit plus à elle seule à tuer un nuage si la zone n'est pas clairement un obstacle.

`CloudGateLogic.swift` ajoute l'hystérésis et la logique crépuscule nécessaires pour éviter le flapping ciel/pas-ciel.

### Parallélisme

`CloudAnalyzer.swift` possède deux files dédiées :

- `cloudweight.inference.sky`
- `cloudweight.inference.cloud`

SegFormer et UCloudNet sont lancés en parallèle puis synchronisés. `ParallelInferenceResults` protège les résultats avec un `NSLock` pour éviter les mutations concurrentes non sûres.

Ne pas annoncer de gain matériel avant mesure iPhone.

### Basse lumière

`SceneSanityGate.swift` / `CameraService.swift` ont été adaptés pour distinguer crépuscule exploitable et scène réellement trop sombre. La télémétrie conserve luminance, ISO, exposition, clipping/glare et état low-light. Toute capacité caméra basse lumière doit rester conditionnelle au support réel du device.

### Télémétrie

V12 étend la télémétrie afin de rendre le garde observable : ciel brut/effectif, blocker sémantique, état/reason du garde, low-light, timings sky/cloud/wall, overlap parallèle, pipeline, cadence, dropped/throttled frames, thermique, orientation, exposition/ISO/luminance/glare, plus les métriques géométriques/masse V11 dans les détections persistantes.

### Sync/API — DÉJÀ IMPLÉMENTÉE dans le code actuel

Contrairement au premier brouillon de HANDOFF, ces changements sont bien présents :

- `DiagnosticsKeychain.swift` existe ;
- `CloudDiagnosticsAPI` charge/sauvegarde un bearer token persistant dans le Keychain ;
- première connexion locale : claim automatique, sans bouton physique ;
- redémarrage app : le token est rechargé ;
- API v3 annonce `persistent_keychain_first_claim` ;
- le bouton `API` a été retiré de `CameraScreenV6` et remplacé par un indicateur non interactif ;
- `SYNC_CLOUD_WEIGHT_SESSION.ps1` réutilise le token PC, redécouvre l'IP si nécessaire, et tente l'appairage automatique ;
- sélection par défaut : dernière session terminée du build actuellement installé ;
- `-AnyBuild`, `-SessionId`, `-AllSessions` restent disponibles ;
- téléchargements : `.part`, reprise par taille, retries, timeout 60 s ;
- parallélisme par défaut ramené à 3, `RetryCount=4` ;
- après téléchargement d'une session terminée, le script valide les nombres telemetry/events/visual contre le manifest ;
- `SYNC-REPORT.json` est produit ;
- MP4 construit seulement si les frames référencées sont réellement présentes.

Ces changements sont **code présents mais pas encore validés physiquement**, car V12 ne compile pas encore complètement.

## Versioning V12 — déjà présent

- `BuildInfo.swift` : `0.12.0`
- `iphone/project.yml` : `0.12.0`, build `12`
- `UPDATE_CLOUD_WEIGHT_LAB.ps1` cible la branche V12
- workflow stamp/verify/package a été adapté à V12

Toujours vérifier ces fichiers contre le HEAD réel avant installation.

## CI V12 — dernier résultat connu

Checkpoint code exact : `c1fa3ae023bbd386e6494245e5e33939a2d741a7`.

GitHub Actions :

- run : `36347243683` (#103)
- job : `108698693276`
- conclusion : **FAILURE**
- étape : `Compile app and unit tests for simulator` (`build-for-testing`)

Réussis avant l'échec :

- checkout exact SHA ;
- toolchain / Python / XcodeGen ;
- téléchargement et conversion des 3 modèles ;
- SegFormer ADE20K multi-sorties ;
- génération du projet Xcode.

Blocage Swift exact encore présent au checkpoint :

```text
CloudAnalyzer.swift:126:32: error: immutable value 'self.portraitCloudModel' may only be initialized once
CloudAnalyzer.swift:127:33: error: immutable value 'self.landscapeCloudModel' may only be initialized once
```

Les propriétés sont encore déclarées :

```swift
private let portraitCloudModel: MLModel?
private let landscapeCloudModel: MLModel?
```

et l'initializer leur affecte les modèles dans le `do`, puis tente de leur réassigner `nil` dans le `catch`.

Le log a aussi signalé auparavant des warnings Swift concurrency sur mutation de résultats capturés ; le checkpoint `c1fa3ae...` introduit `ParallelInferenceResults` avec lock pour cette partie. Ne pas supposer que ces warnings sont résolus tant qu'une nouvelle CI n'est pas passée jusque-là.

Conséquences actuelles :

- aucun build device V12 validé ;
- aucune vérification bundle V12 finale ;
- aucune IPA/artifact V12 validé ;
- aucun test matériel V12 ;
- XCTest non exécutés. Le workflow utilise `build-for-testing`, donc la cible de tests est seulement compilée lorsqu'il atteint cette étape.

## Prochaine étape EXACTE

1. Vérifier HEAD/worktree/status et lire ce HANDOFF.
2. Vérifier le dernier run CI exact-SHA, car le commit documentaire du HANDOFF peut avoir déclenché un run plus récent sans changer le code.
3. Corriger **uniquement** le problème d'initialisation de `portraitCloudModel` / `landscapeCloudModel` dans `CloudAnalyzer.init()` (solution propre : initialisation locale unique puis affectation finale, ou autre correction minimale équivalente).
4. Pousser cette correction seule et attendre la CI exact-SHA complète.
5. Si elle échoue, lire les erreurs Xcode exactes et corriger uniquement celles-ci. Pas de gros refactor tant que CI rouge.
6. Quand CI complète SUCCESS : vérifier chaque étape, artifact exact-SHA et métadonnées.
7. Depuis le worktree V12, utiliser le workflow existant `UPDATE_CLOUD_WEIGHT_LAB.ps1`, puis iLoader.
8. Test matériel V12 :
   - jour/ciel bleu ;
   - nuages gris/blancs ;
   - crépuscule/basse lumière ;
   - arbre devant ciel ;
   - bâtiment/mur ;
   - personne/main/peau ;
   - soleil/glare/lampes ;
   - portrait/paysage ;
   - inclinaisons CoreMotion avec même nuage ;
   - session assez longue pour observer thermique/cadence.
9. Tester la synchro réelle sans bouton API, fermeture/réouverture app, changement d'IP éventuel, récupération correcte du build courant et reprise après interruption réseau.
10. Analyser réellement le MP4/images avec telemetry + events + visual index + manifest + `SYNC-REPORT.json` avant de retoucher les seuils.

## Fichiers diagnostic à partager après test

Normalement :

- `manifest.json`
- `telemetry.ndjson`
- `events.ndjson`
- `visual/visual.ndjson`
- `SYNC-REPORT.json`
- `diagnostic-preview.mp4`

Pas besoin du dossier JPEG si le MP4 a été créé et validé.

## Performance

Baseline matérielle V10 connue : pipeline typique ~31–35 ms, environ 25–30 Hz ; thermique passé `nominal -> fair` après ~108 s sur une session testée.

V12 ajoute la concurrence SegFormer/UCloudNet. Mesurer sur iPhone :

- `skyInferenceMilliseconds`
- `cloudInferenceMilliseconds`
- `inferenceWallMilliseconds`
- overlap parallèle
- pipeline total / P95
- effective Hz
- dropped/throttled frames
- thermal state

Ne jamais annoncer un gain avant hardware.

## Estimation de masse

Conserver l'estimateur angle-aware V11 : FOV caméra + CoreMotion + taille angulaire + priors altitude/profondeur/LWC avec fourchette d'incertitude.

Une caméra RGB seule ne fournit toujours pas directement distance, altitude de base, profondeur 3D ou contenu en eau/glace. Après stabilisation/validation V12, la prochaine amélioration scientifique importante sera un contexte météo optionnel : température/point de rosée, cloud-base/ceilomètre ou données météo pertinentes pour resserrer la distance/altitude.

Ne jamais présenter la masse comme une pesée exacte.

## À ne pas modifier

- `main` ;
- les autres apps ;
- le recorder local persistant validé ;
- le workflow exact-SHA / iLoader ;
- les seuils/modèles au hasard sans données avant/après ;
- aucune release / merge main sans accord explicite utilisateur.

## Critères de sortie V12

V12 n'est prête que lorsque :

- CI exact-SHA complète SUCCESS ;
- IPA exact-SHA récupérable ;
- sync sans bouton API réellement validée ;
- bonne session/build sélectionnée ;
- téléchargement long/reprise validés ;
- telemetry complète et cohérente ;
- crépuscule conserve les nuages évidents sans réintroduire arbres/bâtiments/personnes ;
- stabilité type/masse V11 et géométrie CoreMotion sans régression ;
- performance/thermique mesurées sur iPhone ;
- validation matérielle explicitement séparée de la CI.
