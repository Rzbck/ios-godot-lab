# HANDOFF — Cloud Weight Lab

Date : **2026-09-26**

## Objectif

Créer une application iPhone personnelle, rapide et visuelle qui détecte automatiquement un nuage dans la caméra et affiche une estimation pédagogique de sa masse d'eau avec une fourchette explicite.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche : `feat/cloud-weight-lab-v1-20260926` ;
- base d'architecture monorepo : `integration/watch-auto-pause-osm-20260916` ;
- base SHA vérifiée : `9e329e6e140daea9c84a971c8bf9bb86f46a47e2` ;
- dernier SHA applicatif CI validé avant ce HANDOFF : `5930ed1baf1aa3e147f6543a19b838c7347d519d` ;
- `main` n'est pas modifié ;
- `apps/watch-sensor-lab` sert uniquement de référence d'infrastructure et ne doit pas être modifiée par ce chantier.

## Architecture V1

```text
SwiftUI
  CameraScreen + overlay temps réel
        |
AVFoundation
  preview fluide 720p
        |
AVCaptureVideoDataOutput (~8 Hz analysés)
        |
CloudAnalyzer
  Core Image 160×120
  segmentation heuristique locale légère
        |
CloudFrameAnalysis
        |
CloudMassEstimator
  angle apparent + plages météo par famille
        |
CloudMassEstimate
  médiane + intervalle + confiance
```

Le contrat `CloudFrameAnalysis` garde le moteur de segmentation interchangeable : un futur modèle Core ML peut remplacer le moteur heuristique sans réécrire l'UI ni l'estimateur.

## Derniers changements

- application SwiftUI plein écran avec preview caméra ;
- détection automatique locale sans serveur ;
- classification simple `cumulus / stratocumulus / stratus / cirrus` ;
- estimation largeur / volume / masse avec intervalle d'incertitude ;
- overlay visuel et carte translucide avec masse, fourchette et confiance ;
- cadence d'analyse limitée à environ 8 Hz sur une image 160×120 pour protéger chauffe et batterie ;
- icône d'application dédiée, générée de manière reproductible au build ;
- workflow GitHub Actions exact-SHA vers IPA unsigned ;
- script Windows `UPDATE_CLOUD_WEIGHT_LAB.ps1` pour récupérer uniquement l'artifact correspondant au HEAD local.

## Validation

### BUILD CI VALIDÉ

Dernier SHA applicatif validé : `5930ed1baf1aa3e147f6543a19b838c7347d519d`.

Workflow run : `36272605972` — **SUCCESS**.

Validé par ce run :

- génération XcodeGen ;
- compilation de l'app et de la cible de tests via `build-for-testing` ;
- compilation `Release` pour iPhone sans signature ;
- présence du bundle identifier `com.rzbck.cloudweightlab` ;
- présence de la déclaration d'accès caméra ;
- génération de l'icône dans l'asset catalog ;
- packaging IPA exact-SHA ;
- upload de l'artifact exact-SHA.

Artifact validé :

`cloud-weight-lab-5930ed1baf1aa3e147f6543a19b838c7347d519d`

Important : `build-for-testing` compile la cible XCTest mais **n'exécute pas les tests**. Ne pas présenter les tests unitaires comme exécutés tant que le workflow n'utilise pas `xcodebuild test`.

### NON VALIDÉ SUR IPHONE

- l'IPA n'a pas encore été récupérée localement avec `UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
- l'IPA n'a pas encore été installée via iLoader ;
- aucun comportement n'est encore validé physiquement sur l'iPhone 13 mini ;
- orientation exacte du cadre de détection sur la preview réelle ;
- qualité de détection sur ciel bleu + cumulus, ciel couvert, contre-jour et coucher de soleil ;
- stabilité visuelle du cadre entre les frames ;
- cadence perçue, chauffe, batterie et mémoire ;
- plausibilité des estimations face à de vrais nuages ;
- modèle Core ML spécialisé.

## Limites connues

Une image unique ne donne pas directement la distance, la profondeur ni la teneur en eau réelle du nuage. La V1 infère ces valeurs à partir de l'angle apparent et de plages typiques par famille de nuage. L'interface affiche donc une plage large et une confiance plutôt qu'une fausse précision.

La segmentation V1 est un moteur heuristique local, pas encore un réseau neuronal. Il est volontairement léger et sert de fallback. Il peut confondre d'autres surfaces claires avec un nuage si la caméra ne vise pas principalement le ciel. La prochaine amélioration logique est un modèle de segmentation Core ML académique/licencié, mais seulement après le premier test réel afin de mesurer ce qui doit réellement être corrigé.

## Historique CI utile

- `d0bd0b6ece4cae87d20d796eacaf43aa70c57813` : premier build échoué sur un problème de visibilité Swift du bridge `UIViewRepresentable` ;
- `c81554f2a6398c47fe90afe0e1fdba0944d706a5` : correction du bridge caméra ;
- `daa9f7b0095d3476f413b8dd11b13063b13b7824` : build complet réussi + correction de la copie wildcard PowerShell ;
- `5930ed1baf1aa3e147f6543a19b838c7347d519d` : build complet réussi avec l'icône finale générée.

## Pipeline normal

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

L'artifact exact-SHA contient :

- `CloudWeightLab-<SHA>.ipa` ;
- `CloudWeightLab-<SHA>.ipa.sha256` ;
- `BUILD-METADATA.json` avec le SHA exact.

Synchronisation Windows :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Le script vérifie branche, HEAD, métadonnées et SHA-256 avant de copier l'IPA dans `artifacts\cloud-weight-lab\<SHA>`.

## Prochaine étape exacte

1. sur Windows, se placer dans le worktree dédié à `feat/cloud-weight-lab-v1-20260926` et vérifier qu'il est au HEAD distant attendu ;
2. lancer `UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder` ;
3. installer l'IPA exact-SHA via iLoader ;
4. tester physiquement sur l'iPhone 13 mini avec au minimum : ciel bleu + cumulus, ciel couvert, contre-jour ;
5. noter orientation du cadre, faux positifs, stabilité, cadence et chauffe ;
6. seulement à partir de ces observations, calibrer l'heuristique ou intégrer un modèle Core ML spécialisé.

## À ne pas modifier sans besoin explicite

- `main` ;
- `apps/watch-sensor-lab` ;
- son workflow et son pipeline ;
- les autres applications du monorepo.
