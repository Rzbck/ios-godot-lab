# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Créer une application iPhone personnelle qui détecte uniquement des nuages réellement présents dans le ciel, les détoure en masque, traite plusieurs régions nuageuses distinctes et affiche une estimation pédagogique de leur masse d'eau avec une fourchette explicite.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-sky-gate-v3-20260927` ;
- base V3 : V2 au SHA physiquement testé `c959cc6512f8e12251561d05793b3bc8c294a517` ;
- dernier SHA applicatif V3 CI validé avant ce HANDOFF : `0bee985bb2279c0f2a9d81fedaa028e403a5d51d` ;
- run CI validant ce SHA : `36300729912` ;
- `main` n'est pas modifié ;
- les autres apps du monorepo sont hors chantier ;
- conteneur Windows connu : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree `main` connu : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V3 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-sky-gate-v3`.

Toujours re-vérifier le HEAD GitHub, le HEAD local, le statut du worktree et le run exact-SHA avant toute reprise. Le commit qui modifie ce HANDOFF est postérieur au SHA applicatif ci-dessus et doit lui aussi avoir une CI verte avant installation.

## Retours matériels — source de vérité

### V1 rejetée

Testée par l'utilisateur sur iPhone 13 mini avec une vidéo de stratocumulus : gros rectangle global, détourage imprécis et absence de vraie séparation multi-nuages.

Cause racine : l'heuristique V1 agrégeait les pixels candidats et calculait un unique bounding box global.

### V2 rejetée comme version finale

V2 physiquement testée au SHA `c959cc6512f8e12251561d05793b3bc8c294a517`.

Observation utilisateur : le détourage UCloudNet fonctionne sur les nuages, mais lorsque la caméra vise autre chose que le ciel, l'app détecte beaucoup d'objets non nuageux comme des nuages.

Cause racine vérifiée : UCloudNet était appliqué directement à chaque frame. C'est un modèle de segmentation nuage/ciel spécialisé pour des images de ciel ; hors domaine, il peut produire de fortes probabilités sur murs, bâtiments, objets, végétation, etc. Baisser simplement le seuil risquerait de supprimer de vrais nuages sans résoudre la cause.

Conclusion : V3 ajoute une validation sémantique du ciel en amont. La V2 reste une référence avant/après et ne doit pas être présentée comme corrigée physiquement.

## Architecture V3

```text
AVFoundation camera preview 720p
        |
frame portrait, analyse sérialisée
        |
        +-------------------------------+
        |                               |
SkyWater-Seg / SegFormer MiT-B2       UCloudNet k=2 daytime
sky/background gate                   cloud probability
384×384 RGB tensor                    304×544 RGB image
        |                               |
        +---------- intersection --------+
                   |
cloud = UCloudNet >= 0.52
        ET sky >= 0.55
                   |
si couverture ciel confirmée < 5 %
=> aucune détection nuage
                   |
nettoyage local + composantes connexes
                   |
0..8 CloudObservation
                   |
CloudMassEstimator par région
                   |
SwiftUI : masque cyan + contours + labels + masse
```

Le garde ciel agit pixel par pixel : une zone ne peut être affichée comme nuage que si le second modèle la classe également comme ciel.

## Modèles épinglés

### Nuages — UCloudNet

- source : `Att100/UCloudNet` ;
- commit : `799f25917361663a1ce2cf210c14a01c1ae45f15` ;
- poids : `ucloudnet_k_2_aux_lr_decay_d_epochs_100.pdparam` ;
- Git blob vérifié : `12bc7b57460e1820bc303c7513c8f2eee9b4a47f` ;
- sortie Core ML : `CloudSegmentation.mlmodelc` ;
- cible : iOS 17, MLProgram float16.

### Ciel — SkyWater-Seg

- source modèle : `Realcat/skywater_seg` / code `Vincentqyw/skywater_seg` ;
- architecture : SegFormer MiT-B2, 4 classes (`background`, `sky`, `water`, `person`) ;
- licence annoncée : MIT ;
- révision poids épinglée : `a45ff48a4f924057e9fd947ec736b4098b06e337` ;
- SHA-256 `model.safetensors` : `bba260c601533e4d34c7891cd055b051c2cd5fd2c22084a35d902bfb43e31341` ;
- sortie Core ML : `SkySegmentation.mlmodelc` ;
- export : `torch.export` abaissé au dialecte ATEN via `.run_decompositions({})` puis Core ML Tools 9 ;
- entrée iPhone : tenseur RGB float32 NCHW `1×3×384×384` dans `[0,1]` ;
- validation numérique PyTorch ↔ Core ML en CI : erreur absolue max observée `0.020923`, sous le seuil de rejet `0.08`.

## Changements V3

- ajout d'un second modèle dédié à la reconnaissance du ciel ;
- intersection du masque UCloudNet avec le masque ciel ;
- rejet global si moins de 5 % de la frame est reconnue comme ciel ;
- conservation du vrai masque nuage et des composantes multiples de V2 ;
- aucun retour au bounding box ou à l'heuristique V1 ;
- tests ajoutés pour vérifier que des probabilités nuage hors zone ciel sont rejetées ;
- version app : `0.3.0` / build `3` ;
- workflow exact-SHA conserve vérification des poids, compilation Core ML, compilation Swift, bundle iPhone et packaging IPA ;
- `UPDATE_CLOUD_WEIGHT_LAB.ps1` vise par défaut `fix/cloud-weight-sky-gate-v3-20260927`.

## Validation CI V3

### BUILD CI VALIDÉ — SHA `0bee985bb2279c0f2a9d81fedaa028e403a5d51d`

Run : `36300729912` — **SUCCESS**.

Validé par ce run :

- checkout exact SHA ;
- Python 3.13 ;
- téléchargement/vérification des poids UCloudNet ;
- téléchargement/vérification SHA-256 des poids SkyWater-Seg ;
- conversion UCloudNet → Core ML ;
- conversion SegFormer ciel → Core ML via `torch.export` / ATEN ;
- validation numérique du modèle ciel Core ML contre PyTorch ;
- génération XcodeGen ;
- compilation app + cible XCTest via `build-for-testing` ;
- build Release non signé pour iPhone ;
- vérification bundle identifier et permission caméra ;
- vérification que `CloudSegmentation.mlmodelc` et `SkySegmentation.mlmodelc` sont tous les deux réellement embarqués ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` **compile** la cible XCTest mais n'exécute pas les tests unitaires. Ne pas dire que les tests XCTest ont été exécutés.

### Échecs V3 résolus

- `ccbd978340d31e6b53bf82fa38f95a8167fa46c6` : TorchScript/Core ML bloqué sur une opération `int` du SegFormer ;
- `cf2c3aa21398ae3644193fd0b9454e804a3e4247` : passage à `torch.export`, mais graphe au dialecte `TRAINING` ;
- `eac72e3bfe1111f606c113bda99e752207c35215` : conversion des deux modèles réussie, puis compilation Swift échouée sur l'initialisation des deux `MLModel` et le nouveau type `.int8` de `MLMultiArray` ;
- `0bee985bb2279c0f2a9d81fedaa028e403a5d51d` : correction de l'initialisation atomique des deux modèles + prise en charge `.int8`, pipeline complet réussi.

## NON VALIDÉ PHYSIQUEMENT EN V3

Aucun comportement V3 n'est encore validé sur l'iPhone 13 mini.

Tests matériels prioritaires :

1. viser uniquement un mur / meuble / sol / écran : **attendu = zéro nuage** ;
2. viser une scène mixte bâtiment + ciel : **attendu = aucune détection sur le bâtiment, masque seulement dans la zone ciel** ;
3. ciel bleu sans nuage : **attendu = zéro nuage** ;
4. refaire la même vidéo de stratocumulus utilisée sur V1/V2 : vérifier que le garde ciel ne supprime pas les vrais nuages ;
5. plusieurs nuages réellement séparés : vérifier les composantes distinctes ;
6. observer stabilité du masque, latence, cadence, chauffe et batterie.

Le second SegFormer est nettement plus lourd que UCloudNet. Une CI verte ne valide donc pas la fluidité ni la chauffe sur iPhone. Une observation matérielle de cadence insuffisante devra conduire à profiler/optimiser le garde ciel, pas à le supprimer silencieusement.

## Limites connues

- le garde ciel peut encore faire des erreurs de segmentation, notamment sur reflets, horizon, conditions lumineuses extrêmes ou scènes atypiques ;
- UCloudNet reste une segmentation sémantique, pas une instance segmentation : deux nuages qui se touchent dans le masque peuvent rester une seule composante ;
- la classification `cumulus / stratocumulus / stratus / cirrus` reste heuristique ;
- une image monoculaire ne donne pas directement distance, profondeur ni teneur réelle en eau/glace : la masse reste une estimation avec fourchette et confiance.

## Pipeline normal

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

Artifact exact-SHA : `cloud-weight-lab-<SHA>` contenant :

- `CloudWeightLab-<SHA>.ipa` ;
- `CloudWeightLab-<SHA>.ipa.sha256` ;
- `BUILD-METADATA.json`.

Depuis le worktree V3 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Le script vérifie branche, HEAD, run exact-SHA, métadonnées et SHA-256 avant de copier l'IPA dans :

`E:\_Project\IOS APP\ios-godot-lab\artifacts\cloud-weight-lab\<SHA>`

## Prochaine étape exacte

1. vérifier que le commit final contenant ce HANDOFF a une CI complète verte et son artifact exact-SHA ;
2. créer/synchroniser le worktree Windows `worktrees\cloud-weight-sky-gate-v3` sur la branche V3 ;
3. lancer `UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder` ;
4. installer l'IPA exact-SHA via iLoader ;
5. faire d'abord les tests négatifs hors ciel, puis la scène mixte, puis la même vidéo de stratocumulus ;
6. noter faux positifs, faux négatifs, alignement, multi-régions, fluidité et chauffe ;
7. calibrer uniquement à partir de ces observations physiques.

## À ne pas modifier

- `main` sans accord explicite ;
- V1 et V2, conservées comme références avant/après ;
- `apps/watch-sensor-lab` ;
- workflows et applications hors Cloud Weight Lab.
