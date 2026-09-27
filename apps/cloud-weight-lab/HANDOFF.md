# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît uniquement les nuages réellement présents dans le ciel, détoure plusieurs régions, les suit temporellement et affiche une estimation pédagogique de masse d'eau/ glace condensée. Priorités V6 : **rotation portrait/paysage correcte, UI discrète, lecture visuelle différenciée, diagnostic local récupérable directement depuis Windows sans copier-coller**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-ux-visual-v6-20260927` ;
- base fonctionnelle précédente : V5 CI validée au SHA `9d6db7547d1bb0042f00f84804364a3304f2e990` ;
- dernier SHA applicatif V6 CI validé avant ce HANDOFF : `e85470c1d2671477b970cd0cd98df0bd90ec3146` ;
- run CI : `36313670173` — **SUCCESS** ;
- artifact de ce SHA : `cloud-weight-lab-e85470c1d2671477b970cd0cd98df0bd90ec3146` ;
- `main` non modifié ;
- autres applications du monorepo hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V6 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-ux-visual-v6`.

Toujours re-vérifier branche, HEAD, status local et CI exact-SHA avant installation. Le commit contenant ce HANDOFF est postérieur au SHA applicatif ci-dessus : **il doit lui aussi avoir une CI complète verte et un artifact exact-SHA avant test matériel**.

## Historique matériel — source de vérité

- **V1 rejetée** : gros bounding box global, pas de vrai détourage multi-régions.
- **V2 rejetée** : UCloudNet détourait les nuages mais produisait des faux positifs hors ciel.
- **V3 validée pour le garde ciel** : les objets hors ciel ne sont plus détectés comme nuages ; latence/instabilité encore mauvaises.
- **V4 testée** : stabilisation améliorée mais encore latente et difficile à lire.
- **V5 testée** : impression d'amélioration, mais l'app restait portrait-only, UI diagnostic trop présente et workflow `COPIER DIAG` rejeté par l'utilisateur.

Observations utilisateur les plus récentes à préserver :

- le garde ciel fonctionne suffisamment bien pour ne plus détecter normalement murs/sol/autres objets comme nuages ;
- la latence et la stabilité restent à mesurer/optimiser sur appareil ;
- l'interface doit rester très discrète ;
- les régions/types de nuages doivent être différenciables visuellement ;
- l'utilisateur veut récupérer télémétrie + captures par PowerShell, pas copier/coller du texte depuis l'app ;
- le dépôt étant public, aucune donnée diagnostic de l'iPhone ne doit être envoyée automatiquement vers GitHub/Internet.

## Architecture V6

### Segmentation

La logique validée V3/V4 est conservée :

```text
caméra AVFoundation
    |
SkyWater SegFormer MiT-B2 384×384
    +
UCloudNet k=2
    |
cloud = UCloudNet >= 0.52 ET sky >= 0.55
si ciel confirmé < 5 % => zéro nuage
    |
composantes connexes
    |
tracking temporel V4
    |
overlay + labels compacts V6
```

V6 embarque **deux variantes Core ML UCloudNet construites à partir des mêmes poids** :

- portrait : `CloudSegmentation.mlmodelc`, entrée 304×544 ;
- paysage : `CloudSegmentationLandscape.mlmodelc`, entrée 544×304 ;
- garde ciel : `SkySegmentation.mlmodelc`, 384×384.

Le but du second UCloudNet n'est pas de changer le modèle scientifique, mais d'éviter de déformer artificiellement le canvas lorsqu'on tourne l'iPhone.

### Rotation

- `UISupportedInterfaceOrientations` autorise portrait, landscape left et landscape right ;
- preview et sortie vidéo utilisent `AVCaptureDevice.RotationCoordinator` / `videoRotationAngle` ;
- le choix portrait/paysage de l'analyse se fait selon les dimensions réellement fournies après rotation ;
- le masque, les centroïdes et les labels doivent être physiquement vérifiés dans les trois orientations avant de considérer cette partie validée.

### UI / couleurs

`CameraScreenV6.swift` est l'écran actif.

- UI réduite à de petites capsules ;
- aucun bouton `COPIER DIAG` ;
- en haut : nom app, Hz/ms, bouton API ;
- en bas : masse totale, nombre de nuages, couverture ciel/nuage ;
- labels très compacts avec ID stable + type + masse ;
- couleurs sémantiques : cumulus cyan, stratocumulus orange, stratus violet, cirrus vert, inconnu blanc ;
- `CloudOverlayStabilizer` conserve maintenant la couleur courante au lieu de recréer systématiquement un masque cyan.

La classification de type reste heuristique à partir de couverture, aspect ratio, luminosité/saturation. **Ne pas présenter le type de nuage comme une classification scientifique validée.**

## Diagnostic local V6

### Principe de confidentialité

Aucun diagnostic n'est uploadé automatiquement vers GitHub, un serveur externe ou ChatGPT.

Les données restent localement sur l'iPhone et sont exposées uniquement par une petite API HTTP locale sur le LAN :

- port : `8765` ;
- Bonjour : `_cloudweight._tcp` ;
- `/api/v1/health` est public mais ne contient que l'identité/version/état d'appairage ;
- les endpoints télémétrie/captures exigent un jeton Bearer ;
- l'appairage est explicitement armé depuis le petit bouton `API` de l'app ;
- le jeton est conservé côté Windows sous `%LOCALAPPDATA%\CloudWeightLab\diagnostics-session.json`, jamais dans Git ;
- les captures peuvent contenir ce que voit la caméra : **ne jamais les publier automatiquement dans le repo public**.

### Stockage borné iPhone

`CloudDiagnosticsStore.swift` :

- historique télémétrie max : 180 mesures ;
- snapshots max : 12 ;
- intervalle snapshot : environ 2 s uniquement pendant une session appairée ;
- taille max : 640 px ;
- JPEG qualité ~0,45 ;
- expiration automatique : environ 10 min ;
- stockage temporaire ;
- compression JPEG exécutée sur une queue utility séparée afin de ne pas bloquer volontairement l'analyse IA.

### Récupération Windows

Script :

```powershell
.\apps\cloud-weight-lab\PULL_CLOUD_WEIGHT_DIAG.ps1 -OpenFolder
```

Fonctionnement :

1. réutilise une session locale valide si disponible ;
2. sinon cherche l'API Cloud Weight sur le LAN local ;
3. demande à l'utilisateur de toucher le petit bouton `API` sur l'iPhone ;
4. appaire et stocke le jeton uniquement dans `%LOCALAPPDATA%` ;
5. récupère `status.json`, `telemetry.json`, `snapshots.json` et les JPEG temporaires ;
6. écrit le résultat sous `artifacts\cloud-weight-lab\diagnostics\<timestamp>-<build>`.

Option utile après récupération :

```powershell
.\apps\cloud-weight-lab\PULL_CLOUD_WEIGHT_DIAG.ps1 -ClearRemoteSnapshots -OpenFolder
```

La récupération Windows supprime donc le besoin de recopier manuellement les métriques depuis l'iPhone. Elle **ne donne pas automatiquement accès aux fichiers à ChatGPT** : si une analyse visuelle est nécessaire, fournir le dossier/les JPEG récupérés dans le chat.

## Version V6

- version app : `0.6.0` ;
- build : `6` ;
- script IPA `UPDATE_CLOUD_WEIGHT_LAB.ps1` vise `fix/cloud-weight-ux-visual-v6-20260927` ;
- workflow : `.github/workflows/cloud-weight-lab-build.yml`.

## Validation CI V6

### BUILD CI VALIDÉ — SHA applicatif `e85470c1d2671477b970cd0cd98df0bd90ec3146`

Run : `36313670173` — **SUCCESS**.

Validé par ce run :

- checkout exact SHA ;
- génération UCloudNet portrait ;
- génération UCloudNet paysage ;
- génération du garde ciel SkyWater ;
- génération XcodeGen ;
- compilation Swift de l'app et de la cible XCTest via `build-for-testing` ;
- compilation de `CameraScreenV6`, API locale, stockage borné, rotation coordinator et télémétrie ;
- build iPhone Release non signé ;
- vérification du contrat bundle ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` compile la cible XCTest mais **n'exécute pas les tests**. Ne pas dire « tests XCTest passés ».

## NON VALIDÉ PHYSIQUEMENT EN V6

À ce stade, ne pas annoncer comme validé sur iPhone :

- rotation réelle portrait → paysage gauche/droite ;
- alignement preview / masque / labels après rotation ;
- qualité réelle du modèle paysage ;
- couleurs et stabilité visuelle des différents nuages ;
- API LAN et autorisation Réseau local sur l'iPhone réel ;
- appairage PowerShell ;
- récupération JSON/JPEG ;
- expiration/nettoyage réel des snapshots ;
- impact perf des snapshots lorsque l'API est appairée ;
- latence/Hz/stabilité de V6 sur iPhone 13 mini.

## Test matériel prioritaire V6

1. installer l'IPA exact-SHA finale ;
2. au premier lancement, autoriser caméra et réseau local si iOS le demande ;
3. vérifier une scène sans ciel : aucune régression de faux positifs ;
4. viser des nuages en portrait et observer UI/couleurs/labels ;
5. tourner en paysage gauche puis droite : vérifier rotation + alignement du masque ;
6. laisser l'app viser une scène nuageuse environ 20–30 s ;
7. depuis Windows, lancer `PULL_CLOUD_WEIGHT_DIAG.ps1 -OpenFolder` ;
8. quand le script le demande, toucher `API` sur l'iPhone ;
9. vérifier que JSON + JPEG sont récupérés ;
10. utiliser ces données pour l'optimisation suivante au lieu de modifier les seuils à l'aveugle.

## Pipeline normal Windows / IPA

Depuis le worktree V6 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Le script vérifie branche, HEAD, run exact-SHA, metadata et SHA-256 avant copie sous :

`E:\_Project\IOS APP\ios-godot-lab\artifacts\cloud-weight-lab\<SHA>`

Puis installation via iLoader.

## Prochaine étape exacte

1. valider la CI complète du commit final contenant ce HANDOFF ;
2. vérifier que la branche pointe exactement sur ce SHA ;
3. récupérer l'IPA exact-SHA via le script Windows ;
4. installer avec iLoader ;
5. réaliser le protocole V6 ci-dessus ;
6. récupérer les diagnostics via PowerShell ;
7. analyser les mesures/captures avant toute optimisation de seuil, modèle ou cadence.

## À ne pas modifier

- `main` sans accord explicite ;
- V1–V5, conservées comme références ;
- `apps/watch-sensor-lab` et autres apps ;
- garde ciel validé sans données matérielles justifiant une modification ;
- ne jamais automatiser l'upload des captures/tokens vers le repo public.
