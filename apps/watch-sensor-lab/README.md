# Watch Sensor Lab

Application expérimentale **séparée** de `IOSGodotLab`, conservée dans le même repository mais développée sur sa propre branche/worktree.

## Objectif

Valider la chaîne suivante sans Mac local :

`Windows -> GitHub Actions macOS/Xcode -> app Godot iPhone + app watchOS -> iLoader -> iPhone/Apple Watch -> données Watch vers Godot`

## Règle de séparation

Ne pas modifier, déplacer ou réorganiser l'application `IOSGodotLab` depuis ce chantier. Les branches/worktrees existants restent indépendants.

## Bootstrap actuel

Le premier jalon compile volontairement les deux côtés **séparément** :

- une app Godot iPhone minimale, avec identité Git/SHA visible ;
- une app watchOS SwiftUI minimale utilisant Core Motion et préparant WatchConnectivity ;
- un workflow GitHub Actions dédié qui construit les deux produits sans signature et publie un artifact exact-SHA.

Ce bootstrap **ne prétend pas encore** que l'app Watch est embarquée dans l'IPA iPhone ni qu'iLoader l'installe sur l'Apple Watch. Cette intégration sera le jalon suivant après validation CI.

## Bundle IDs réservés au prototype

- iPhone : `com.rzbck.watchsensorlab`
- Watch : `com.rzbck.watchsensorlab.watchkitapp`

## Outils

- Godot `4.7.2` stable ;
- GitHub Actions `macos-26` ;
- Xcode fourni par le runner ;
- XcodeGen `2.46.0` pour générer le projet watchOS sans Mac local.
