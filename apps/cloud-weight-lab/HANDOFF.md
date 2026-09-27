# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Créer une application iPhone personnelle qui reconnaît uniquement les nuages réellement présents dans le ciel, les détoure en direct et affiche une estimation pédagogique de masse d'eau, tout en restant lisible, stable et mesurable sur l'iPhone 13 mini.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-stability-telemetry-v4-20260927` ;
- base V4 : V3 physiquement testée au SHA `cab5d3d6781dc94fb0612f2efc319dda1a9a5e8b` ;
- dernier SHA applicatif V4 CI validé avant ce HANDOFF : `b3e0c3db1ef98af89a55a647d2c5cf1af8283257` ;
- run CI ayant validé ce SHA : `36302869311` ;
- `main` n'est pas modifié ;
- les autres applications du monorepo sont hors chantier ;
- conteneur Windows connu : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree `main` connu : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V4 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-stability-telemetry-v4`.

Toujours re-vérifier le HEAD GitHub, le HEAD local, le statut du worktree et le run exact-SHA avant toute reprise. Le commit contenant ce HANDOFF est postérieur au SHA applicatif cité ci-dessus : il doit lui aussi avoir une CI complète verte et un artifact exact-SHA avant installation.

## Retours matériels — source de vérité

### V1 rejetée

Test iPhone 13 mini sur vidéo de stratocumulus : gros rectangle global, détourage imprécis et pas de vraie séparation multi-régions.

### V2 rejetée comme version finale

Le détourage UCloudNet fonctionne sur les nuages, mais beaucoup d'objets hors ciel sont détectés comme nuages. Cause racine : UCloudNet était utilisé hors de son domaine d'images de ciel.

### V3 — garde ciel physiquement validé, stabilité rejetée

V3 testée physiquement sur iPhone 13 mini au SHA final `cab5d3d6781dc94fb0612f2efc319dda1a9a5e8b`.

Observation utilisateur :

- **VALIDÉ SUR IPHONE** : lorsque la caméra vise autre chose que le ciel, l'application ne détecte plus ces objets comme nuages ; le garde ciel remplit donc son objectif principal ;
- **BUG/LIMITE** : le calcul paraît lent ;
- **BUG/LIMITE** : masque, labels et valeurs bougent beaucoup d'une analyse à l'autre ;
- **BUG/LIMITE** : la lecture devient difficile et visuellement peu propre ;
- **HYPOTHÈSE À MESURER** : impression que la segmentation oscille localement entre « nuage » et « pas nuage ».

Cause racine vérifiée pour une partie de l'instabilité V3 : aucune stabilisation temporelle. Les observations recevaient à chaque frame des IDs `0,1,2…` après tri des composantes par aire ; deux régions changeant légèrement de taille pouvaient donc échanger leur identité. Centroid, masse, classe et masque étaient publiés bruts à chaque analyse.

La cadence V3 était seulement demandée avec un intervalle minimal de `0,18 s`, sans mesure du temps réel d'inférence, des Hz effectifs, des frames perdues ou de la variation du masque. Ne pas inventer de FPS V3 a posteriori.

## Architecture V4

V4 conserve exactement le principe validé de V3 :

```text
AVFoundation camera preview 720p
        |
SkyWater-Seg / SegFormer MiT-B2 384×384
        +
UCloudNet k=2 daytime 304×544
        |
cloud = UCloudNet >= 0.52 ET sky >= 0.55
si ciel confirmé < 5 % => zéro nuage
        |
composantes connexes
        |
CloudObservation brutes
        |
+---------------- temporal V4 ----------------+
|                                               |
tracking IoU + distance centroid                masque affiché
IDs persistants                                 fenêtre <= 3 masques
lissage géométrie / masse                      vote majoritaire
classe confirmée sur 3 analyses                reset si Δ masque > 18 %
rétention 1 analyse manquante                  rétention max 1 manque
|                                               |
+------------------- SwiftUI -------------------+
        |
HUD diagnostics optionnel + OSLog borné
```

Le modèle ciel et UCloudNet ne sont **pas** allégés dans cette V4. Le but est d'abord de mesurer le coût réel sur l'iPhone avant d'optimiser à l'aveugle et de risquer de perdre le filtrage hors-ciel validé.

## Stabilisation V4

### Suivi des régions

`CloudTemporalStabilizer.swift` :

- association entre analyses par IoU de bounding boxes + distance des centroïdes ;
- IDs persistants indépendants de l'ordre des composantes brutes ;
- distance centroid maximale : `0.22` normalisée ;
- IoU minimal : `0.04` ;
- lissage géométrique : alpha `0.34`, ou `0.68` sur déplacement important ;
- lissage masse/mesures : alpha `0.24`, ou `0.48` sur déplacement important ;
- changement de type de nuage accepté après 3 confirmations ;
- une analyse manquante est tolérée pour éviter un clignotement immédiat ;
- aucun historique non borné.

### Stabilisation visuelle du masque

`CloudOverlayStabilizer.swift` :

- historique maximum de 3 masques binaires ;
- vote majoritaire pixel par pixel après remplissage de la fenêtre ;
- si le masque courant diffère de plus de `18 %` du précédent, historique réinitialisé immédiatement pour éviter une traînée lorsque la caméra bouge franchement ;
- un seul masque manquant peut conserver l'affichage précédent ; au deuxième manque, reset ;
- cette stabilisation concerne l'affichage. La télémétrie compare les masques **bruts** afin de ne pas cacher l'instabilité réelle du modèle.

## Télémétrie V4

`CloudTelemetry.swift` + `CameraService.swift` mesurent maintenant :

- durée moyenne lissée du pipeline d'analyse en millisecondes ;
- cadence effective des analyses en Hz ;
- `Δ MASQUE` : pourcentage de pixels du masque brut qui changent entre deux analyses ;
- couverture nuageuse brute ;
- variation de couverture ;
- nombre de détections brutes puis stabilisées ;
- frames caméra signalées par `AVCaptureVideoDataOutput` via `didDrop` ;
- frames ignorées par le throttle applicatif ;
- état thermique iOS (`nominal`, `fair`, `serious`, `critical`).

Télémétrie volontairement bornée :

- pas d'enregistrement des images ;
- pas d'historique illimité ;
- seulement l'état courant et le masque précédent ;
- une ligne `OSLog` environ toutes les 2 secondes dans le subsystem `com.rzbck.cloudweightlab`, catégorie `telemetry`.

Format OSLog :

```text
pipeline=<ms> hz=<Hz> maskDelta=<%> coverage=<%> coverageDelta=<%> raw=<n> stable=<n> drop=<n> throttle=<n> thermal=<state>
```

Le badge `CORE ML · LIVE` est tactile en V4 et affiche/masque un HUD de diagnostic. Le HUD présente les métriques principales à l'écran ; `drop` est toujours disponible dans OSLog même s'il n'est pas encore affiché comme case dédiée dans le HUD.

## Modèles conservés

### Nuages — UCloudNet

- source : `Att100/UCloudNet` ;
- commit : `799f25917361663a1ce2cf210c14a01c1ae45f15` ;
- poids : `ucloudnet_k_2_aux_lr_decay_d_epochs_100.pdparam` ;
- Git blob : `12bc7b57460e1820bc303c7513c8f2eee9b4a47f` ;
- Core ML : `CloudSegmentation.mlmodelc`.

### Ciel — SkyWater-Seg

- source : `Realcat/skywater_seg` / `Vincentqyw/skywater_seg` ;
- SegFormer MiT-B2, 384×384 ;
- révision poids : `a45ff48a4f924057e9fd947ec736b4098b06e337` ;
- SHA-256 : `bba260c601533e4d34c7891cd055b051c2cd5fd2c22084a35d902bfb43e31341` ;
- Core ML : `SkySegmentation.mlmodelc` ;
- export Core ML via `torch.export` / dialecte ATEN ;
- validation numérique PyTorch ↔ Core ML observée en V3 : erreur absolue max `0.020923`.

## Version V4

- version app : `0.4.0` ;
- build : `4` ;
- pipeline exact-SHA inchangé dans son principe ;
- `UPDATE_CLOUD_WEIGHT_LAB.ps1` vise désormais par défaut `fix/cloud-weight-stability-telemetry-v4-20260927`.

## Validation CI V4

### BUILD CI VALIDÉ — SHA applicatif `b3e0c3db1ef98af89a55a647d2c5cf1af8283257`

Run : `36302869311` — **SUCCESS**.

Validé par ce run :

- checkout exact SHA ;
- génération des deux modèles Core ML épinglés ;
- génération XcodeGen ;
- compilation Swift de l'app et de la cible XCTest via `build-for-testing` ;
- compilation des nouveaux stabilisateurs et de la télémétrie ;
- build iPhone `Release` non signé ;
- vérification bundle identifier et permission caméra ;
- vérification des deux `.mlmodelc` dans l'app ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` compile les tests mais ne les exécute pas. Ne pas dire « tests XCTest passés ».

Les tests ajoutés pour `CloudTemporalStabilizer` vérifient à la compilation la conservation d'identité prévue, le lissage d'un saut de masse et la rétention d'une seule analyse manquante, mais ils ne sont pas exécutés par le workflow actuel.

## NON VALIDÉ PHYSIQUEMENT EN V4

V4 n'est pas encore validée sur l'iPhone.

Test matériel prioritaire, dans cet ordre :

1. installer l'IPA exact-SHA V4 ;
2. refaire d'abord la même scène/vidéo de nuages utilisée avec V3 ;
3. téléphone aussi immobile que possible pendant environ 10–15 s : vérifier si masque, labels et masse sont nettement plus lisibles ;
4. toucher `CORE ML · LIVE` pour afficher le HUD ;
5. relever ou photographier : durée pipeline, Hz, `Δ MASQUE`, couverture, `Δ COUV.`, `BRUT→STABLE`, état thermique et throttle ;
6. bouger ensuite lentement la caméra : vérifier que la stabilisation n'introduit pas de traînée cyan ;
7. tester de nouveau une scène sans ciel pour confirmer qu'aucune régression n'a réintroduit les faux positifs ;
8. laisser tourner 1–2 min pour observer l'état thermique et la cadence.

## Comment interpréter la télémétrie

Ne pas appliquer automatiquement un correctif avant les mesures iPhone.

- pipeline long + Hz faible + `Δ MASQUE` faible : coût des modèles dominant ; prochaine étape = profiler/optimiser le garde ciel ou sa fréquence ;
- pipeline acceptable + `Δ MASQUE` élevé téléphone fixe : instabilité sémantique/seuils ; prochaine étape = mesurer séparément probabilités ciel/nuage et ajouter hystérésis temporelle ;
- `raw` instable mais `stable` constant : tracker efficace, éventuellement améliorer logique split/merge ;
- IDs stables mais masse encore trop mobile : renforcer le lissage des mesures ;
- beaucoup de `drop` : le pipeline capture/inférence ne consomme pas assez vite les frames ;
- thermique `serious`/`critical` rapidement : réduire duty cycle ou coût du garde ciel ;
- filtre hors-ciel qui régresse : préserver V3 et revenir sur l'optimisation responsable plutôt que baisser arbitrairement les seuils.

Étape de diagnostic supplémentaire possible après ce premier test V4 : séparer la durée `sky model` de la durée `UCloudNet` et mesurer la couverture UCloudNet avant/après le garde ciel. Ce n'est volontairement pas encore ajouté : d'abord mesurer la V4 réelle sur l'iPhone.

## Pipeline normal Windows

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

Artifact exact-SHA : `cloud-weight-lab-<SHA>` avec :

- `CloudWeightLab-<SHA>.ipa` ;
- `CloudWeightLab-<SHA>.ipa.sha256` ;
- `BUILD-METADATA.json`.

Depuis le worktree V4 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Le script vérifie branche, HEAD, run exact-SHA, metadata et SHA-256 avant de copier dans :

`E:\_Project\IOS APP\ios-godot-lab\artifacts\cloud-weight-lab\<SHA>`

## Prochaine étape exacte

1. vérifier que le HEAD final contenant ce HANDOFF a une CI complète verte et un artifact exact-SHA ;
2. créer/synchroniser le worktree Windows `worktrees\cloud-weight-stability-telemetry-v4` ;
3. lancer `UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder` ;
4. installer l'IPA exact-SHA avec iLoader ;
5. exécuter le protocole matériel V4 ci-dessus ;
6. utiliser les chiffres du HUD/OSLog pour choisir la prochaine optimisation, sans modifier à l'aveugle les modèles ou les seuils.

## À ne pas modifier

- `main` sans accord explicite ;
- V1/V2/V3, conservées comme références ;
- `apps/watch-sensor-lab` ;
- workflows et applications hors Cloud Weight Lab ;
- les seuils/modèles V3 tant que la télémétrie V4 n'a pas montré précisément ce qui coûte ou oscille.
