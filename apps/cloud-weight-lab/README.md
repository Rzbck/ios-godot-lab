# Cloud Weight Lab

Application iPhone expérimentale qui vise un nuage avec la caméra et affiche en direct une estimation pédagogique de sa masse d'eau condensée.

## V1

- caméra plein écran ;
- analyse locale légère à cadence limitée pour préserver l'iPhone 13 mini ;
- détection automatique d'une zone nuageuse dominante ;
- classification simple `cumulus / stratocumulus / stratus / cirrus` ;
- estimation largeur / volume / masse avec intervalle d'incertitude ;
- aucune vidéo envoyée sur un serveur ;
- UI SwiftUI translucide et entièrement automatique.

La V1 ne prétend pas mesurer la masse réelle du nuage. Elle infère la géométrie et la teneur en eau depuis l'image et des plages météorologiques typiques. L'interface affiche donc toujours une fourchette.

## Architecture

```text
AVFoundation camera
      |
      v
CloudAnalyzer
  Core Image downsample 160×120
  segmentation locale légère (~8 Hz)
      |
      +--> CloudKind + bounding box + confidence
      |
      v
CloudMassEstimator
  angle apparent + hypothèses météo
      |
      v
SwiftUI overlay
  masse médiane + intervalle + confiance
```

Le contrat `CloudFrameAnalysis` permet de remplacer `CloudAnalyzer` par un modèle Core ML de segmentation sans toucher à `CloudMassEstimator` ni à l'interface.

## Build

Le workflow `.github/workflows/cloud-weight-lab-build.yml` :

1. génère le projet Xcode avec XcodeGen ;
2. compile l'app et les tests pour simulateur ;
3. compile l'app iPhone unsigned ;
4. produit un IPA exact-SHA ;
5. publie l'artifact `cloud-weight-lab-<SHA>`.

Sous Windows, `UPDATE_CLOUD_WEIGHT_LAB.ps1` récupère et vérifie l'artifact correspondant exactement au HEAD local avant installation manuelle via iLoader.
