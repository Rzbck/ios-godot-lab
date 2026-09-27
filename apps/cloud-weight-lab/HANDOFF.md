# HANDOFF — Cloud Weight Lab V12 WIP

## Objectif

Application iPhone temps réel qui segmente les nuages, suit des régions persistantes et estime la masse d'eau/glace condensée.

V12 part des problèmes réellement observés sur la session crépuscule V10 et doit :

- ne plus perdre les nuages visibles quand la couleur du ciel change au crépuscule / basse lumière ;
- ne plus utiliser la seule probabilité ADE20K `sky` comme veto absolu ;
- exploiter les classes sémantiques ADE20K pour bloquer arbres/bâtiments/personnes/plantes/murs ;
- stabiliser les décisions du garde ciel dans le temps ;
- enrichir la télémétrie pour expliquer pourquoi une zone est acceptée/refusée ;
- améliorer basse lumière et performances sans casser les comportements déjà validés ;
- rendre la synchronisation diagnostic simple, persistante et robuste sans bouton API à chaque session.

## Dépôt / branche / base

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche V12 : `fix/cloud-weight-twilight-autosync-v12-20260927`
- base V12 : V11 final `c69a673e9dc00355ae744a651341ae5379c9029f`
- checkpoint code V12 avant ce HANDOFF : `9757be7a483d4dae8c21bac8310b5cb714268514`
- worktree Windows prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-twilight-autosync-v12`
- `main` reste hors chantier.

IMPORTANT : le commit contenant ce HANDOFF est postérieur au checkpoint code ci-dessus. À la reprise, vérifier le HEAD réel de la branche et comparer avec `9757be7...` avant toute modification.

## Source matérielle du chantier

Le fichier/session crépuscule analysé provenait encore du build V10 `1a955d01632557f3247bb49c858f8c96f3aeaf27`, pas de V11.

Observation visuelle + télémétrie :

- les nuages gris/blancs restent nettement visibles à l'œil au crépuscule ;
- ADE20K peut pourtant faire tomber `skyCoverage` vers 0–3 % ;
- le code V10/V11 arrêtait alors UCloudNet ou rejetait ses pixels car il exigeait `skyProbability >= 0.55` ;
- quelques instants plus tard la même scène pouvait repasser proche de 100 % de ciel ;
- cela créait des `sky_enter` / `sky_exit` et `mask_jump` très fréquents ;
- ce passage n'était pas principalement un problème de rotation : les échecs observés existaient en paysage stable.

Conclusion : la cause racine est le garde ciel trop brutal, pas l'absence de nuages dans l'image.

## V12 — changements déjà présents sur la branche

La branche est 9 commits devant V11 au checkpoint `9757be7...`.

Fichiers réellement modifiés/ajoutés par rapport à V11 :

- `Tests/CloudGateLogicTests.swift` ajouté ;
- `Tests/SceneSanityGateTests.swift` modifié ;
- `iphone/Sources/CameraService.swift` modifié ;
- `iphone/Sources/CloudAnalyzer.swift` modifié ;
- `iphone/Sources/CloudGateLogic.swift` ajouté ;
- `iphone/Sources/CloudTelemetry.swift` modifié ;
- `iphone/Sources/DiagnosticsKeychain.swift` ajouté ;
- `iphone/Sources/SceneSanityGate.swift` modifié ;
- `tools/build_sky_gate_coreml.py` modifié.

### Garde sémantique ADE20K

La conversion Core ML de SegFormer expose maintenant :

- `sky_probability`
- `blocker_probability`
- `tree_probability`
- `building_probability`
- `person_probability`
- `plant_probability`
- `wall_probability`

Le but est de conserver UCloudNet comme détecteur nuage, mais d'utiliser ADE20K comme contexte sémantique : une probabilité ciel faible ne doit plus suffire à tuer un nuage si la zone n'est pas clairement un obstacle sémantique.

`CloudGateLogic.swift` introduit la logique de garde/hystérésis nécessaire pour réduire le flapping ciel/pas-ciel et gérer le crépuscule.

### Basse lumière

`SceneSanityGate.swift` et `CameraService.swift` ont commencé à être adaptés pour la basse lumière. La stratégie recherchée est :

- ne pas rejeter un crépuscule exploitable comme une vraie nuit noire ;
- conserver des informations exposition/ISO/luminance dans la télémétrie ;
- utiliser les capacités caméra iOS disponibles quand elles existent sans dégrader les scènes normales.

### Télémétrie

`CloudTelemetry.swift` a été étendu pour rendre le garde V12 observable. À la reprise, vérifier exactement les champs présents avant d'en ajouter d'autres. La télémétrie finale doit permettre de diagnostiquer au minimum :

- ciel brut vs décision de ciel effective/stabilisée ;
- blocker sémantique et raison de rejet/acceptation ;
- état basse lumière ;
- ISO / exposition / luminance / clipping / glare ;
- timings preprocess / sky / cloud / post / pipeline ;
- cadence, dropped/throttled frames, thermique ;
- orientation et géométrie/métriques de masse V11.

## CI V12 — ÉTAT ACTUEL

Checkpoint exact : `9757be7a483d4dae8c21bac8310b5cb714268514`.

GitHub Actions :

- run : `36341003690` (#102)
- job : `108680988750`
- conclusion : **FAILURE**

Ce qui a réussi :

- checkout exact SHA ;
- toolchain ;
- Python/XcodeGen ;
- téléchargement/conversion des modèles ;
- nouveau SegFormer ADE20K multi-sorties ;
- validation conversion Core ML : max abs error `0.020121` ;
- génération du projet Xcode.

Ce qui a échoué :

- étape `Compile app and unit tests for simulator` (`build-for-testing`).

Erreurs Swift exactes :

```text
CloudAnalyzer.swift:115:32: error: immutable value 'self.portraitCloudModel' may only be initialized once
CloudAnalyzer.swift:116:33: error: immutable value 'self.landscapeCloudModel' may only be initialized once
```

Les propriétés concernées sont actuellement déclarées :

```swift
private let portraitCloudModel: MLModel?
private let landscapeCloudModel: MLModel?
```

Le code les initialise puis tente de leur réassigner `nil` dans un chemin d'erreur. La prochaine correction doit être minimale : soit rendre ces deux propriétés mutables, soit restructurer proprement l'init sans changer le comportement.

Conséquences :

- pas de build device V12 ;
- pas de vérification bundle finale ;
- pas d'IPA V12 ;
- pas d'artifact V12 ;
- aucun test matériel V12 ;
- XCTest non exécutés ; le workflow utilise seulement `build-for-testing` quand il atteint cette étape.

## Travail V12 encore NON FAIT

Ne pas croire les anciens messages : au checkpoint réel, ces changements ne sont pas encore présents dans le diff V12 :

- `CloudDiagnosticsAPI.swift` n'est pas encore modifié pour utiliser le Keychain ;
- `DiagnosticsKeychain.swift` existe mais n'est pas encore câblé au flux API ;
- le bouton `API` existe encore dans `CameraScreenV6.swift` ;
- `SYNC_CLOUD_WEIGHT_SESSION.ps1` n'a pas encore le workflow autosync final ;
- il peut encore demander l'appairage manuel si le token sauvegardé PC n'est plus valide ;
- il sélectionne encore la dernière session terminée globale, ce qui a déjà récupéré une ancienne V10 au lieu du build courant ;
- son parallélisme par défaut reste 8, ce qui a déjà provoqué un timeout réseau sur une grosse session ;
- `UPDATE_CLOUD_WEIGHT_LAB.ps1` vise encore V11 ;
- `BuildInfo.swift`, `project.yml` et le workflow sont encore en `0.11.0` / build `11` ;
- le workflow stamp/package/metadata reste V11 ;
- le HANDOFF V12 est la première mise à jour documentaire de cette branche.

## Prochaine étape EXACTE

1. Vérifier le HEAD réel de `fix/cloud-weight-twilight-autosync-v12-20260927` et le diff par rapport au checkpoint `9757be7...`.
2. Corriger uniquement les deux erreurs de mutabilité `portraitCloudModel` / `landscapeCloudModel` dans `CloudAnalyzer.swift`.
3. Pousser et attendre la CI exact-SHA. Ne pas continuer de gros refactor tant que `build-for-testing` n'est pas vert.
4. Si la compilation casse encore, récupérer les erreurs Xcode exactes et corriger uniquement celles-ci.
5. Quand le cœur V12 compile :
   - câbler `DiagnosticsKeychain` dans `CloudDiagnosticsAPI` pour un token persistant ;
   - supprimer le besoin de presser `API` à chaque sync et retirer/masquer ce bouton de l'UI normale ;
   - rendre le script Windows auto-discovery + auto-auth ;
   - sélectionner par défaut la dernière session terminée du **build installé/courant**, pas une ancienne version ;
   - rendre les téléchargements reprenables/robustes avec retries et parallélisme raisonnable (2–4 par défaut plutôt que 8 si nécessaire) ;
   - conserver `-SessionId` / `-AllSessions` pour contrôle manuel.
6. Versionner V12 partout : `0.12.0`, build `12`, BuildInfo, `project.yml`, workflow stamp/verify/BUILD-METADATA, UPDATE script branche V12.
7. Faire un dernier build exact-SHA et vérifier l'artifact exact.
8. Installer uniquement cet IPA exact-SHA avec le workflow existant + iLoader.
9. Test matériel jour + crépuscule/basse lumière : ciel bleu, nuages gris, arbre devant ciel, bâtiment/mur, main/peau, glare/soleil/lampes, portrait/paysage, inclinaison CoreMotion.
10. Synchroniser la vraie session V12 puis analyser **MP4/images + telemetry + events + visual index + manifest**, pas seulement les chiffres.

## Performance / parallélisme

Baseline matérielle connue V10 : environ 31–35 ms de pipeline et 25–30 Hz après suppression du throttle fixe ; thermique `fair` après ~108 s sur une session testée.

V12 veut paralléliser intelligemment le travail sémantique et nuage, mais ne pas ajouter un gros modèle supplémentaire sans mesure. Le nouveau SegFormer ADE20K fournit déjà une couche sémantique riche ; mesurer d'abord latence, concurrence Core ML, chauffe, dropped frames et stabilité réelle sur iPhone.

Ne jamais annoncer un gain de performance avant test matériel.

## Estimation de masse

Conserver l'estimateur angle-aware V11 et son incertitude. Une seule caméra RGB ne mesure pas directement la distance, l'altitude de base, la profondeur 3D ou le contenu en eau/glace.

Après validation V12 du garde + CoreMotion, la vraie prochaine amélioration de précision est un contexte météo optionnel : température/point de rosée, cloud base/ceilomètre ou données météo pertinentes pour resserrer la distance/altitude. Ne jamais présenter la masse comme une pesée exacte.

## À ne pas modifier

- `main` ;
- les autres apps du dépôt ;
- le recorder local persistant validé ;
- le workflow exact-SHA / iLoader ;
- les seuils/modeles au hasard sans comparaison avant/après ;
- aucune release/merge main sans accord explicite utilisateur.

## Critères de sortie V12

V12 n'est prête que lorsque :

- CI exact-SHA complète SUCCESS ;
- IPA exact-SHA récupérable ;
- sync ne demande plus le bouton API à chaque fois ;
- sync choisit la bonne version/session ;
- téléchargement long reprend après interruption et ne timeoute pas facilement ;
- télémétrie explique les décisions du garde ;
- crépuscule conserve les nuages visuellement évidents sans réintroduire arbres/bâtiments/personnes ;
- stabilité type/masse V11 et géométrie CoreMotion ne régressent pas ;
- performance/thermique sont mesurées sur iPhone ;
- validation matérielle explicitement distincte de la CI.
