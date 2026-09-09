# Watch Sensor Lab

Nouvelle application expérimentale **indépendante** de `IOSGodotLab`, conservée dans le même repository mais développée dans son propre dossier, sa propre branche et son propre worktree.

## Vision produit

Construire une application iPhone + Apple Watch qui enregistre et fusionne les données disponibles sur les deux appareils pendant une session.

Premier usage concret : un **tracker/recorder** capable d'enregistrer une trace avec temps, distance, vitesse, altitude et mouvement, puis d'ajouter progressivement les données Apple Watch autorisées comme la fréquence cardiaque pendant un workout.

Ce projet ne reprend ni l'interface ni les pages d'`IOSGodotLab`. Il réutilise seulement l'infrastructure déjà éprouvée quand elle est pertinente : Windows -> GitHub Actions macOS/Xcode -> build exact-SHA -> IPA unsigned -> iLoader.

## Architecture cible

```text
Apple Watch / watchOS native
    Core Motion / Core Location / HealthKit
                 |
                 | WatchConnectivity
                 v
iPhone native bridge
    Core Motion / Core Location / APIs iOS
                 |
                 v
Godot iPhone
    recorder + timeline + carte + statistiques + export
```

Chaque donnée enregistrée devra porter au minimum : timestamp, source (`iphone` / `watch` / `derived`), type de mesure, valeur et qualité/précision quand l'API la fournit.

## Capacités visées

- GPS / route / altitude / vitesse / course ;
- accélération, gyro, gravity, attitude/device motion ;
- magnétomètre, pédomètre et baromètre selon disponibilité ;
- fréquence cardiaque et métriques workout via HealthKit avec consentement ;
- distance, vitesse moyenne/max, allure, dénivelé et autres métriques dérivées ;
- enregistrement local de sessions puis export ultérieur.

Le périmètre exact dépendra des APIs publiques Apple, du modèle des appareils et des permissions utilisateur.

## Bootstrap actuel

Premier jalon volontairement minimal :

- une app Godot iPhone indépendante ;
- une app SwiftUI watchOS indépendante avec Core Motion et préparation WatchConnectivity ;
- un workflow GitHub Actions dédié qui compile les deux produits séparément sans signature et avec identité exact-SHA.

L'embarquement réel de l'app Watch dans l'IPA iPhone et l'installation via iLoader sur l'Apple Watch seront validés dans un jalon distinct.

## Bundle IDs du prototype

- iPhone : `com.rzbck.watchsensorlab`
- Watch : `com.rzbck.watchsensorlab.watchkitapp`

## Outils

- Godot `4.7.2` stable ;
- GitHub Actions `macos-26` ;
- Xcode fourni par le runner ;
- XcodeGen `2.46.0` pour générer le projet watchOS sans Mac local.
