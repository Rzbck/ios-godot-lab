# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît uniquement les nuages présents dans le ciel, les détoure, suit plusieurs régions et affiche une estimation pédagogique de masse d'eau. Priorités actuelles : **latence, stabilité temporelle, diagnostic mesurable sur iPhone 13 mini**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-diagnostics-v5-20260927` ;
- base : V4 final `111b5397fcf0292debec786c93ae7d4e52206a68` ;
- dernier SHA applicatif V5 CI validé avant ce HANDOFF : `aebf7186d5de891c2e8a67476ce7d55122752f2b` ;
- run CI : `36305289852` — **SUCCESS** ;
- `main` non modifié ;
- autres apps hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V5 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-diagnostics-v5`.

Toujours re-vérifier branche, HEAD, status local et CI exact-SHA avant toute modification ou installation. Le commit contenant ce HANDOFF est postérieur au SHA applicatif ci-dessus : il doit lui aussi avoir une CI complète verte et un artifact exact-SHA avant test matériel.

## Historique matériel — source de vérité

### V1

Rejetée : gros bounding box global sur stratocumulus, pas de vrai détourage multi-régions.

### V2

Rejetée : UCloudNet détoure des nuages mais produit beaucoup de faux positifs hors ciel.

### V3

**VALIDÉ SUR IPHONE** pour le garde ciel : murs/objets hors ciel ne sont plus détectés comme nuages.

Limites observées : calcul lent, masque/labels/masse instables, lecture difficile.

### V4

Testée physiquement après installation du build V4 distribué depuis le chantier précédent.

Retour utilisateur :

- **AMÉLIORATION** : stabilité visuelle un peu meilleure ;
- **BUG/LIMITE** : latence encore visible ;
- **BUG/LIMITE** : mise à jour perçue comme insuffisamment temps réel ;
- **BUG/LIMITE** : stabilité encore insuffisante ;
- besoin explicite de ne plus travailler à l'aveugle et d'obtenir une télémétrie exploitable ;
- question utilisateur sur le fonctionnement lorsque l'iPhone est tourné.

## Orientation — état réel

V4/V5 restent **portrait uniquement** :

- `project.yml` ne déclare que `UIInterfaceOrientationPortrait` ;
- la preview force `.portrait` ;
- le prétraitement caméra applique une orientation fixe `.right` ;
- paysage non validé et non annoncé comme supporté.

En V5, l'orientation physique est seulement **mesurée dans la télémétrie** (`portrait`, `landscapeLeft`, etc.). Ne pas présenter cela comme une correction du paysage.

Pour une future correction propre, utiliser les API Apple actuelles (`AVCaptureDevice.RotationCoordinator` / `AVCaptureConnection.videoRotationAngle`) et adapter aussi le canvas d'analyse / modèle / overlay ; ne pas corriger uniquement la preview.

## Architecture conservée

```text
AVFoundation 720p preview
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
tracking V4 + lissage géométrie/masse + IDs persistants
        |
masque affiché stabilisé sur fenêtre courte
        |
SwiftUI
```

Les modèles/seuils V3 sont volontairement conservés pour ne pas casser le filtrage hors-ciel déjà validé.

## Changements V5 — diagnostics et latence

Version : `0.5.0` / build `5`.

### Cadence

- intervalle minimal d'analyse : `0.18 s` → `0.10 s` ;
- plafond applicatif théorique : ~5,6 Hz → 10 Hz ;
- ce changement n'impose pas 10 Hz : le débit réel reste limité par le coût des deux modèles ;
- `AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames = true` reste actif pour éviter une file non bornée.

### Mesures par étape

`CloudAnalyzer` mesure maintenant séparément :

- prétraitement (`CVPixelBuffer` + conversion RGB tensor) ;
- inférence SegFormer ciel ;
- inférence UCloudNet ;
- post-traitement (resampling, gate, cleanup, composantes, observations, overlay) ;
- couverture ciel.

`CloudTelemetry` conserve aussi :

- pipeline total ;
- Hz effectifs ;
- variation brute du masque ;
- couverture nuage ;
- brut → stable ;
- frames `didDrop` ;
- throttle applicatif ;
- état thermique ;
- orientation physique.

### Historique borné et confidentialité

- maximum `90` analyses en mémoire ;
- seulement valeurs numériques ;
- **aucune image** ;
- **aucun frame/pixel brut exporté** ;
- **aucune localisation** ;
- **aucun UDID / identifiant appareil** ;
- **aucun upload automatique** ;
- OSLog local seulement ;
- rapport généré localement et copié volontairement par l'utilisateur.

Le HUD V5 possède un bouton **COPIER DIAG**. Le texte commence par `CLOUD_WEIGHT_DIAG_V5` et contient moyennes/p95 + les 20 dernières mesures. L'utilisateur peut le coller dans le chat pour analyse.

## Modèles épinglés

### UCloudNet

- `Att100/UCloudNet` ;
- commit `799f25917361663a1ce2cf210c14a01c1ae45f15` ;
- poids `ucloudnet_k_2_aux_lr_decay_d_epochs_100.pdparam` ;
- blob Git `12bc7b57460e1820bc303c7513c8f2eee9b4a47f` ;
- Core ML `CloudSegmentation.mlmodelc`.

### SkyWater-Seg

- `Realcat/skywater_seg` / `Vincentqyw/skywater_seg` ;
- SegFormer MiT-B2 384×384 ;
- révision `a45ff48a4f924057e9fd947ec736b4098b06e337` ;
- SHA-256 `bba260c601533e4d34c7891cd055b051c2cd5fd2c22084a35d902bfb43e31341` ;
- Core ML `SkySegmentation.mlmodelc`.

## Validation CI V5 applicative

SHA : `aebf7186d5de891c2e8a67476ce7d55122752f2b`

Run : `36305289852` — **SUCCESS**.

Validé :

- checkout exact SHA ;
- génération/vérification des deux modèles Core ML ;
- XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- compilation du profiling V5 et de l'UI `COPIER DIAG` ;
- build iPhone Release non signé ;
- vérification bundle identifier / permission caméra / version ;
- présence des deux `.mlmodelc` ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Attention : `build-for-testing` compile la cible XCTest mais n'exécute pas les tests unitaires.

## NON VALIDÉ PHYSIQUEMENT EN V5

À tester sur iPhone 13 mini :

1. amélioration de réactivité avec plafond 10 Hz ;
2. stabilité réelle du masque et des labels ;
3. coût réel `PREP / CIEL AI / NUAGE AI / POST` ;
4. `Δ MASQUE` téléphone fixe ;
5. `DROP/THR` ;
6. état thermique sur 1–2 min ;
7. conservation du garde hors-ciel ;
8. orientation : seulement observer/logguer ; le paysage n'est pas supporté en V5.

## Lecture du rapport V5

Quelques diagnostics probables :

- `sky_ms_avg` dominant : optimiser fréquence/coût du garde ciel ;
- `preprocess_ms_avg` élevé : remplacer/optimiser la boucle Swift RGB/tensor ;
- `cloud_ms_avg` dominant : alléger UCloudNet / résolution / cadence ;
- pipeline bas mais `mask_delta_pct_p95` élevé téléphone fixe : problème de stabilité sémantique/seuils, ajouter hystérésis/probabilité temporelle ;
- beaucoup de `drop_total` : pipeline trop lent par rapport au flux caméra ;
- beaucoup de `throttle_total` mais peu de drops : limite applicative encore dominante ;
- thermique `serious`/`critical` : réduire duty cycle/coût avant d'augmenter encore la cadence.

Ne modifier modèles, seuils ou résolution qu'après lecture d'un vrai rapport iPhone V5.

## Pipeline Windows

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

Script normal :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Branche attendue par le script : `fix/cloud-weight-diagnostics-v5-20260927`.

Artifact : `cloud-weight-lab-<SHA>` avec IPA, SHA-256 et `BUILD-METADATA.json`.

Destination Windows :

`E:\_Project\IOS APP\ios-godot-lab\artifacts\cloud-weight-lab\<SHA>`

## Prochaine étape exacte

1. vérifier la CI du HEAD final contenant ce HANDOFF ;
2. créer/synchroniser `worktrees\cloud-weight-diagnostics-v5` ;
3. récupérer l'IPA exact-SHA avec le script existant ;
4. installer avec iLoader ;
5. viser le même nuage/scène, d'abord téléphone fixe 15–30 s ;
6. ouvrir le HUD et appuyer sur **COPIER DIAG** ;
7. coller le rapport complet dans le chat ;
8. décider de l'optimisation suivante à partir des timings réels ;
9. traiter le paysage comme un chantier séparé une fois le chemin orientation + modèle/overlay correctement défini.

## À ne pas modifier

- `main` sans accord explicite ;
- V1/V2/V3/V4, conservées comme références ;
- apps/watch-sensor-lab ;
- apps/workflows hors Cloud Weight Lab ;
- modèles/seuils validés V3 avant lecture de la télémétrie V5.
