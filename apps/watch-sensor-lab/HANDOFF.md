# HANDOFF — Watch Sensor Lab

Date de création : **2026-09-09**.

## Objectif

Créer une nouvelle application iPhone Godot reliée à une Apple Watch, sans modifier l'application `IOSGodotLab` existante.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- branche : `feat/watch-sensor-lab-bootstrap-20260909` ;
- worktree Windows attendu : `E:\\_Project\\IOS APP\\ios-godot-lab\\worktrees\\watch-sensor-lab` ;
- base de branche : `main` au SHA `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- HEAD courant : toujours re-fetcher Git/GitHub avant modification.

## Ce qui est validé

- séparation locale en worktree dédié : **VALIDÉ UTILISATEUR** ;
- branche distante dédiée créée : **VALIDÉ** ;
- aucune modification de `iphone-lab-v2` : **VALIDÉ par périmètre Git**.

## Bootstrap implémenté

- `apps/watch-sensor-lab/godot` : app Godot iPhone minimale ;
- `apps/watch-sensor-lab/watch` : app SwiftUI watchOS minimale ;
- Core Motion : accéléromètre + gyroscope côté Watch ;
- WatchConnectivity : émission préparée côté Watch si le compagnon iPhone est joignable ;
- `.github/workflows/watch-sensor-lab-bootstrap.yml` : build iPhone et Watch séparés, unsigned, exact-SHA.

## PAS encore validé

- CI du bootstrap ;
- build iPhone réel ;
- build watchOS réel ;
- receiver WatchConnectivity dans Godot/iOS ;
- embarquement de l'app watchOS dans l'IPA iPhone ;
- signature iLoader des bundles imbriqués ;
- installation de la companion app sur Apple Watch ;
- données réelles Apple Watch -> iPhone -> Godot.

## Prochaine étape exacte

1. synchroniser le worktree local par fast-forward strict ;
2. vérifier le HEAD et le status CLEAN ;
3. observer le workflow `Watch Sensor Lab bootstrap` pour ce SHA exact ;
4. corriger uniquement les erreurs de bootstrap jusqu'à obtenir un build CI vert ;
5. ensuite seulement intégrer le bridge iOS WatchConnectivity et l'embarquement watchOS dans l'IPA.

## Ne pas modifier

- le worktree `iphone-lab-v2` ;
- sa branche `feat/iphone-lab-v2-20260908` ;
- son workflow, ses artifacts ou `UPDATE_IOS_LAB.ps1` depuis ce chantier.
