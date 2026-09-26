# HANDOFF — Cloud Weight Lab

Date : **2026-09-26**

## Objectif

Créer une application iPhone personnelle, rapide et visuelle qui détecte automatiquement un nuage dans la caméra et affiche une estimation de sa masse d'eau avec une fourchette explicite.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche : `feat/cloud-weight-lab-v1-20260926` ;
- base choisie pour conserver l'architecture monorepo `apps/*` : `integration/watch-auto-pause-osm-20260916` ;
- base SHA vérifiée : `9e329e6e140daea9c84a971c8bf9bb86f46a47e2` ;
- `main` n'est pas modifié ;
- `apps/watch-sensor-lab` est une référence d'infrastructure uniquement et ne doit pas être modifiée par ce chantier.

## Architecture V1

```text
SwiftUI
  CameraScreen + overlay temps réel
        |
AVFoundation
  preview fluide
        |
AVCaptureVideoDataOutput (~8 Hz analysés)
        |
CloudAnalyzer
  Core Image 160×120
  masque léger ciel/nuage
        |
CloudFrameAnalysis
        |
CloudMassEstimator
  taille angulaire + plages météo
        |
CloudMassEstimate
  médiane + intervalle + confiance
```

## État

### IMPLÉMENTÉ MAIS NON VALIDÉ UTILISATEUR

- UI caméra plein écran ;
- analyse locale sans serveur ;
- détection d'une zone nuageuse dominante ;
- classification heuristique des familles de nuages ;
- estimation de masse avec intervalle ;
- tests unitaires de l'estimateur ;
- workflow exact-SHA vers IPA unsigned ;
- script Windows de récupération exact-SHA.

### PAS ENCORE VALIDÉ

- compilation CI du premier commit de cette branche ;
- installation via iLoader ;
- orientation du cadre sur caméra réelle ;
- qualité de détection en ciel bleu, couvert, contre-jour et coucher de soleil ;
- performance/chauffe réelle sur iPhone 13 mini ;
- modèle Core ML spécialisé.

## Limites connues

La profondeur, la distance réelle et la teneur en eau du nuage ne sont pas observables directement depuis une image unique. La V1 affiche volontairement une plage large et marque le résultat comme estimation pédagogique.

La segmentation V1 n'est pas encore un réseau neuronal. Elle sert de moteur léger fonctionnel et de fallback. La prochaine amélioration prévue est un modèle de segmentation Core ML académique/licencié, sans modifier le contrat de données ni l'UI.

## Pipeline

Workflow : `.github/workflows/cloud-weight-lab-build.yml`.

Artifact attendu : `cloud-weight-lab-<SHA>` contenant :

- `CloudWeightLab-<SHA>.ipa` ;
- son `.sha256` ;
- `BUILD-METADATA.json` avec le SHA exact.

Synchronisation Windows : `apps/cloud-weight-lab/UPDATE_CLOUD_WEIGHT_LAB.ps1`.

## Prochaine étape exacte

1. vérifier la CI du HEAD de `feat/cloud-weight-lab-v1-20260926` ;
2. corriger uniquement les erreurs de compilation éventuelles ;
3. récupérer l'IPA exact-SHA avec `UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
4. installer via iLoader ;
5. faire un premier test physique en pointant plusieurs vrais nuages ;
6. seulement après ce test, calibrer la segmentation et intégrer un modèle Core ML si nécessaire.
