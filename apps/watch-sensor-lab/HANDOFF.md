# HANDOFF — Watch Sensor Lab

Date : **2026-09-09**.

## Objectif

Créer une **nouvelle application** iPhone + Apple Watch, indépendante de `IOSGodotLab`, centrée sur la collecte, la synchronisation et l'enregistrement des données disponibles publiquement sur les deux appareils.

Premier usage produit visé : **tracking / recorder** d'une session réelle avec route, temps, distance, vitesse, altitude et données de mouvement, puis enrichissement progressif avec les données Apple Watch autorisées (par exemple fréquence cardiaque pendant une session HealthKit).

Ce chantier ne doit pas reproduire l'UX, les pages ni la logique produit de `IOSGodotLab`. Seules les méthodes d'infrastructure déjà éprouvées peuvent servir de référence : GitHub Actions macOS, build exact-SHA, IPA unsigned, récupération Windows et installation iLoader.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/watch-sensor-lab` ;
- branche : `feat/watch-sensor-lab-bootstrap-20260909` ;
- worktree Windows : `E:\\_Project\\IOS APP\\ios-godot-lab\\worktrees\\watch-sensor-lab` ;
- base initiale : `main` au SHA `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- HEAD courant : toujours re-fetcher Git/GitHub avant modification.

## Architecture cible

```text
Apple Watch native watchOS
  Core Motion / Core Location / HealthKit selon permissions
                 |
                 | WatchConnectivity
                 v
iPhone native bridge
  Core Motion / Core Location / autres APIs iOS
                 |
                 v
Godot iPhone
  session recorder + visualisation + stockage/export
```

Principe de données : chaque échantillon doit être horodaté et identifier sa source (`iphone`, `watch`, `derived`) afin de pouvoir fusionner proprement les flux.

## Données visées progressivement

### iPhone
- position GPS, précision, altitude ;
- vitesse, précision vitesse, course/cap ;
- accéléromètre, gyroscope, gravity, attitude/device motion ;
- magnétomètre et baromètre/altimètre quand disponibles ;
- informations de session et état appareil utiles au diagnostic.

### Apple Watch
- accéléromètre, gyroscope, device motion ;
- pedometer / cadence / mouvement quand exposés et pertinents ;
- altitude/baromètre quand disponibles ;
- position/vitesse quand disponible et pertinente ;
- fréquence cardiaque et métriques workout via HealthKit uniquement après autorisation utilisateur.

### Dérivées
- distance cumulée ;
- durée ;
- vitesse instantanée/moyenne/max ;
- allure ;
- dénivelé positif/négatif ;
- route / trace ;
- qualité des mesures et trous de données ;
- statistiques de synchronisation Watch <-> iPhone.

`Tout récupérer` signifie : exploiter au maximum les APIs publiques réellement disponibles sur les appareils, avec leurs permissions et limites. Cela ne signifie pas accès arbitraire aux données privées/système.

## État vérifié

- séparation en worktree dédié : **VALIDÉ UTILISATEUR** ;
- branche distante dédiée : **VALIDÉ** ;
- `iphone-lab-v2` non modifié : **VALIDÉ par périmètre Git** ;
- bootstrap iPhone + watchOS au SHA `3a16a663aee99f13ff21759c233ae5a2c056c637` : **BUILD CI VALIDÉ** ;
- export Godot iOS : **PASS** sur ce SHA ;
- build Xcode iPhone unsigned : **PASS** sur ce SHA ;
- build Xcode watchOS unsigned : **PASS** sur ce SHA ;
- aucune validation matérielle iPhone/Watch pour cette nouvelle app à ce stade.

## Intégration companion en cours

Le workflow assemble maintenant le produit final de test sous forme d'une IPA iPhone contenant l'app watchOS dans :

```text
Payload/WatchSensorLab.app/Watch/WatchSensorLabWatch.app
```

Le workflow vérifie avant packaging :

- bundle iPhone : `com.rzbck.watchsensorlab` ;
- bundle Watch : `com.rzbck.watchsensorlab.watchkitapp` ;
- `WKCompanionAppBundleIdentifier` côté Watch = `com.rzbck.watchsensorlab` ;
- `WKRunsIndependentlyOfCompanionApp = false` ;
- présence réelle de l'app Watch dans l'IPA finale ;
- association de l'artifact au SHA exact.

Cette étape reproduit la structure finale d'un companion embarqué mais reste **EXPÉRIMENTALE** tant qu'iLoader n'a pas signé les bundles imbriqués et qu'une vraie Apple Watch n'a pas installé/lancé la companion app.

## Pas encore validé

- CI du nouvel assemblage companion ;
- signature iLoader des bundles imbriqués ;
- installation de l'IPA sur iPhone ;
- apparition/installation de la companion app dans l'app Watch de l'iPhone ;
- lancement réel sur Apple Watch ;
- bridge WatchConnectivity côté iPhone/Godot ;
- données réelles Watch -> iPhone -> Godot ;
- tracking réel sur appareil ;
- HealthKit.

## Prochaine étape exacte

1. obtenir un CI vert pour l'IPA companion intégrée ;
2. récupérer l'IPA exact-SHA sur Windows ;
3. la signer/installer avec iLoader ;
4. vérifier sur l'iPhone si la companion Watch est proposée et installable ;
5. lancer l'app sur la vraie Watch ;
6. si ce jalon matériel passe, implémenter le receiver WatchConnectivity iPhone -> Godot ;
7. ensuite construire le recorder GPS/motion puis HealthKit.

## Ne pas modifier depuis ce chantier

- `iphone-lab-v2` ;
- `feat/iphone-lab-v2-20260908` ;
- le workflow/artifacts/`UPDATE_IOS_LAB.ps1` de cette ancienne application, sauf demande utilisateur explicite distincte.
