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
- bootstrap Godot parse/import au SHA `56dd48bfe822e916a177f1e79f5c9adb05a1cbb7` : **CI PASS** ;
- premier export iOS au même SHA : **FAIL** avant Xcode à cause d'une configuration d'export ;
- partie watchOS non atteinte dans ce run.

## Correction en cours

Le premier export iOS n'avait aucune icône de base. L'exporteur iOS de Godot retombe sur `application/config/icon`; un chemin vide/invalide produit une erreur de configuration. Une icône propre à Watch Sensor Lab est ajoutée et référencée explicitement dans le projet/preset.

## Pas encore validé

- nouvel export iOS après correction ;
- build iPhone Xcode ;
- build watchOS ;
- bridge WatchConnectivity côté iPhone/Godot ;
- empaquetage companion Watch dans l'IPA ;
- signature iLoader des bundles imbriqués ;
- installation réelle sur Apple Watch ;
- données réelles Watch -> iPhone -> Godot ;
- tracking réel sur appareil.

## Prochaine étape exacte

1. obtenir un CI bootstrap vert pour iPhone et watchOS séparément ;
2. intégrer la companion watchOS dans l'app iPhone ;
3. produire une IPA exact-SHA contenant les deux ;
4. tester signature/installation avec iLoader ;
5. valider WatchConnectivity sur appareils réels ;
6. seulement ensuite construire le recorder GPS/motion puis HealthKit.

## Ne pas modifier depuis ce chantier

- `iphone-lab-v2` ;
- `feat/iphone-lab-v2-20260908` ;
- le workflow/artifacts/`UPDATE_IOS_LAB.ps1` de cette ancienne application, sauf demande utilisateur explicite distincte.
