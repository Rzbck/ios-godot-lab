# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Créer une application iPhone personnelle, rapide et visuelle qui détecte et détoure automatiquement les nuages dans la caméra, traite plusieurs zones nuageuses distinctes et affiche une estimation pédagogique de leur masse d'eau avec une fourchette explicite.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `feat/cloud-weight-segmentation-v2-20260927` ;
- base V2 : V1 au SHA `1e2ae6a03828f740d3d8b53ad19d9d7950e54372` ;
- dernier SHA applicatif V2 CI validé avant ce HANDOFF : `e1546efb184cef67a16890f2be90d83eec4c5812` ;
- run CI validant ce SHA : `36298404712` ;
- artifact exact-SHA validé : `cloud-weight-lab-e1546efb184cef67a16890f2be90d83eec4c5812` ;
- `main` n'est pas modifié ;
- `apps/watch-sensor-lab` et les autres apps sont hors chantier et ne doivent pas être modifiés ;
- worktree V2 Windows : **pas encore créé/confirmé**. Chemin prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-segmentation-v2` ;
- conteneur local vérifié par l'utilisateur : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree `main` local vérifié : `E:\_Project\IOS APP\ios-godot-lab\main`.

> Toujours re-vérifier le HEAD GitHub et le HEAD local avant toute reprise : le commit contenant ce HANDOFF est postérieur au dernier SHA applicatif cité ci-dessus et déclenche lui-même un build exact-SHA.

## Retour matériel V1 — source de vérité

L'utilisateur a installé et testé la V1 sur **iPhone 13 mini** en visant une **vidéo de nuages** (pas de nuages disponibles en ciel réel au moment du test).

Observation utilisateur :

- le moteur V1 produit un **gros rectangle global** sur une formation de stratocumulus ;
- le rendu est jugé imprécis et visuellement mauvais ;
- il ne correspond pas au besoin convenu de détourage propre ;
- il ne sépare pas plusieurs nuages distincts comme attendu.

Cause racine vérifiée dans le code V1 : `CloudAnalyzer` agrégeait tous les pixels heuristiquement considérés comme nuage et calculait un unique `minX/minY/maxX/maxY`. Une couche nuageuse étendue produisait donc mécaniquement un grand bounding box.

**Conclusion : la segmentation heuristique V1 est rejetée comme expérience principale. Elle ne doit pas être réintroduite silencieusement comme fallback visuel.**

## Architecture V2

```text
AVFoundation camera preview 720p
        |
frame portrait ~5.5 Hz max
        |
Core ML — UCloudNet k=2 daytime
input RGB 304×544
        |
probability mask pixel-by-pixel
        |
threshold + léger nettoyage local
        |
8-connected components
        |
0..8 régions nuageuses distinctes
        |
CloudObservation[]
  bounds + centroid + coverage + confidence
        |
CloudMassEstimator par région
        |
CloudDetection[]
        |
SwiftUI
  masque cyan translucide + contour réel
  labels par nuage + masse
  somme visible + fourchette
```

### Modèle

Source académique : `Att100/UCloudNet`.

Source épinglée :

- commit UCloudNet : `799f25917361663a1ce2cf210c14a01c1ae45f15` ;
- poids : `weights/ucloudnet_k_2_aux_lr_decay_d_epochs_100.pdparam` ;
- Git blob vérifié : `12bc7b57460e1820bc303c7513c8f2eee9b4a47f` ;
- modèle converti en CI vers Core ML MLProgram float16, cible iOS 17 ;
- conversion : PyTorch 2.7 + coremltools 9.0 sous Python 3.13 ;
- le modèle est destiné à la segmentation binaire ciel/nuage. La classification `cumulus / stratocumulus / stratus / cirrus` reste heuristique et n'est pas à confondre avec la segmentation neuronale.

L'usage est un prototype personnel/non commercial. Ne pas réutiliser ce modèle dans un contexte commercial sans re-vérifier précisément les conditions de licence/source.

## Changements V2

- suppression du bounding box global comme rendu principal ;
- aucun fallback heuristique silencieux si le modèle Core ML manque : l'app affiche une erreur ;
- vrai masque de segmentation pixel par pixel ;
- contour visible dérivé du masque ;
- extraction de composantes connexes pour traiter plusieurs régions nuageuses distinctes ;
- jusqu'à 8 composantes conservées, 6 labels affichés ;
- estimation de masse calculée séparément pour chaque observation ;
- prise en compte du taux de remplissage du masque dans le facteur de forme ;
- somme des masses visibles et fourchette globale dans l'UI ;
- cadence d'analyse limitée à environ 0,18 s entre inférences avec garde `analysisInFlight` ;
- modèle embarqué dans le bundle en tant que `CloudSegmentation.mlmodelc` ;
- version app V2 : `0.2.0` / build `2` ;
- pipeline exact-SHA conservé ;
- script `UPDATE_CLOUD_WEIGHT_LAB.ps1` configuré pour la branche V2 et timeout 40 min.

## Validation CI V2

### BUILD CI VALIDÉ — SHA applicatif `e1546efb184cef67a16890f2be90d83eec4c5812`

Run : `36298404712`.

Validé par ce run :

- checkout exact SHA ;
- Python 3.13 épinglé via `actions/setup-python` ;
- téléchargement des poids UCloudNet épinglés ;
- vérification du Git blob des poids ;
- lecture et mapping complet du checkpoint Paddle vers la réimplémentation PyTorch ;
- génération du Core ML `CloudSegmentation.mlpackage` ;
- génération XcodeGen ;
- compilation de l'app et de la cible XCTest via `build-for-testing` ;
- build `Release` iPhone non signé ;
- vérification bundle identifier et permission caméra ;
- vérification que `CloudSegmentation.mlmodelc` est réellement embarqué dans l'app ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Artifact : `cloud-weight-lab-e1546efb184cef67a16890f2be90d83eec4c5812`.

Important : `build-for-testing` **compile** la cible XCTest mais n'exécute pas les tests. Ne pas dire « tests unitaires passés ».

### Échecs CI résolus pendant V2

- `312df34e1271c8b85eb5a824354092943e6c58b5` : échec avant conversion, runner Python 3.14 sans roue `torch==2.7.0` ;
- `bcd238a2097a325aaba72e43fb472be594332faf` : Python 3.13 corrigé, puis échec sur la métadonnée Paddle `StructuredToParameterName@@` ;
- `e1546efb184cef67a16890f2be90d83eec4c5812` : conversion UCloudNet + builds + packaging réussis.

## NON ENCORE VALIDÉ PHYSIQUEMENT EN V2

Ne pas confondre BUILD CI VALIDÉ et comportement validé sur l'iPhone.

La V2 n'a pas encore été installée/testée physiquement. Il faut encore vérifier sur l'iPhone 13 mini :

- qualité réelle du détourage sur la même vidéo de stratocumulus utilisée pour rejeter V1 ;
- alignement exact masque / preview caméra ;
- qualité sur vrais nuages dès que possible ;
- séparation de plusieurs nuages **lorsqu'ils sont réellement disjoints dans le masque** ;
- comportement sur formations nuageuses qui se touchent ;
- stabilité temporelle / scintillement du masque ;
- fréquence d'inférence perçue ;
- charge, chauffe, batterie et mémoire ;
- faux positifs sur bâtiments, montagnes, contre-jour, horizon et coucher de soleil ;
- plausibilité des estimations de masse.

### Limite importante multi-nuages

UCloudNet fait de la **segmentation sémantique**, pas de l'instance segmentation. Les composantes connexes permettent de séparer plusieurs nuages disjoints. Si deux formations se touchent dans le masque, elles peuvent rester une seule composante. Ne pas prétendre que la V2 sait séparer arbitrairement des nuages collés sans validation supplémentaire.

## Limites scientifiques

Une image monoculaire ne donne pas directement la distance, la profondeur ni la teneur réelle en eau/glace d'un nuage. La masse affichée reste une estimation de matière condensée fondée sur :

- angle apparent ;
- famille de nuage estimée ;
- plages typiques d'altitude ;
- profondeur supposée ;
- plage de contenu en eau/glace ;
- facteur de forme dérivé partiellement du masque.

Conserver une fourchette et une confiance ; éviter toute fausse précision.

## Pipeline normal

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

Artifact exact-SHA : `cloud-weight-lab-<SHA>` contenant :

- `CloudWeightLab-<SHA>.ipa` ;
- `CloudWeightLab-<SHA>.ipa.sha256` ;
- `BUILD-METADATA.json`.

Synchronisation Windows depuis le worktree V2 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Le script vérifie branche, HEAD, run exact-SHA, métadonnées et SHA-256 avant de copier dans :

`E:\_Project\IOS APP\ios-godot-lab\artifacts\cloud-weight-lab\<SHA>`

## Prochaine étape exacte

1. vérifier que le HEAD final de `feat/cloud-weight-segmentation-v2-20260927` a une CI verte et un artifact exact-SHA ;
2. depuis `E:\_Project\IOS APP\ios-godot-lab\main`, créer/synchroniser un worktree dédié : `worktrees\cloud-weight-segmentation-v2` ;
3. lancer `apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder` depuis ce worktree ;
4. installer l'IPA exact-SHA avec iLoader ;
5. refaire **d'abord la même vidéo de stratocumulus** pour un vrai avant/après V1→V2 ;
6. observer : détourage, alignement, multi-régions, stabilité et fluidité ;
7. ensuite tester sur vrais nuages dès que la météo le permet ;
8. calibrer seuils / post-traitement / cadence uniquement à partir de ces observations matérielles.

## À ne pas modifier

- `main` sans accord explicite ;
- `apps/watch-sensor-lab` ;
- workflows des autres apps ;
- V1 `feat/cloud-weight-lab-v1-20260926`, conservée comme référence avant/après.
