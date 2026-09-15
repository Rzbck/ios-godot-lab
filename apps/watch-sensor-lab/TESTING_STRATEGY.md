# Watch Sensor Lab — stratégie de test durable

Date de mise en place : 2026-09-13

## Objectif

Réduire au minimum les séances physiques de développement. Une personne ne doit pas marcher, courir ou pédaler pour vérifier une régression de logique, un bouton, une transition d’état ou un cas de concurrence iPhone/Watch.

Le matériel réel reste nécessaire uniquement pour les comportements que Simulator et les doubles de test ne peuvent pas prouver : HealthKit réel, capteurs réels, GPS réel, background/écran verrouillé, installation/signature, mirroring iPhone/Watch et comportement physique de l’Apple Watch.

## Pyramide de validation

### 1. Garde-fous statiques

`CHECK_WORKFLOW_PARITY.py` et `CHECK_PRODUCT_INVARIANTS.py` échouent tôt lorsqu’une surface iPhone/Watch diverge, lorsqu’un ancien ACK implicite revient, ou lorsqu’un noyau déterministe acquiert une dépendance à un framework matériel/UI.

Le garde-fou vérifie également que le self-test USB reste strictement read-only et n’importe ni HealthKit ni WatchConnectivity.

### 2. Noyaux déterministes partagés

La logique qui peut être pure vit hors de HealthKit/CoreMotion/WatchConnectivity/SwiftUI :

- `Shared/TrackerSessionControl.swift` : arbitrage déterministe des commandes de session ;
- `Shared/TrackerAutoPolicy.swift` : règles Auto, pause et reprise à partir d’évidence synthétique.

Les adaptateurs iPhone/watchOS traduisent les API Apple vers ces types. Les règles ne doivent pas être recopiées dans les vues ou plusieurs modèles.

### 3. XCTest iOS + watchOS

Le workflow `.github/workflows/watch-sensor-lab-tests.yml` exécute la même suite sur un simulateur iPhone et un simulateur Apple Watch disponibles sur le runner.

Les tests couvrent notamment :

- fin Auto : conserver les segments ou forcer un sport concret ;
- commandes dupliquées ;
- commande expirée ;
- mauvaise session ;
- révision périmée ;
- pause/reprise dans le mauvais état ;
- classification Auto synthétique ;
- seuils pause/reprise ;
- scénarios de replay en temps virtuel.

Les `.xcresult` ne sont conservés qu’en cas d’échec et pendant 1 jour.

### 4. Replay synthétique accéléré

`Tests/Support/TrackerAutomationScenario.swift` définit un format versionné de scénario. Un scénario contient du temps virtuel et des métriques synthétiques, jamais des attentes réelles.

Les fixtures peuvent simuler en quelques millisecondes :

- marche ;
- course ;
- vélo ;
- marche → course → vélo ;
- arrêt/reprise ;
- GPS/métriques limites ;
- futurs retards/pertes de liaison.

Le format reste indépendant du matériel pour être réutilisable par XCTest, UI tests et outils de self-test.

### 5. Self-test USB read-only

`AutomationSelfTestService.swift` expose `wsl_selftest_v1` sur le port appareil `37992`. Le client Windows est `WSL_SELFTEST.ps1`.

Ce self-test :

- exécute uniquement les politiques déterministes partagées ;
- ne démarre jamais `HKWorkoutSession` ;
- ne lit/écrit/supprime aucune donnée HealthKit ;
- ne touche pas `NativeSessionStore` ;
- n’envoie aucune commande WatchConnectivity ;
- retourne le build SHA et un résultat PASS/FAIL détaillé ;
- ne laisse aucun état après exécution.

`wsl_diag_v1` sur le port `37991` reste séparé et read-only pour l’inspection de l’état réel.

### 6. UI automation

Les cibles UI-test iPhone/watchOS montent les vues SwiftUI de production avec des modèles synthétiques sans dépendance matérielle. La CI exécute séparément les parcours `force`, `preserve` et `cancel` sur chaque plateforme, sans créer de vraie séance HealthKit.

Identifiants réservés :

- `tracker.finish.button`
- `tracker.finish.preserveAuto`
- `tracker.finish.activityPicker`
- `tracker.finish.confirmSingle`
- `tracker.finish.cancel`

### 7. Tests matériels ciblés

Un test physique n’est demandé que si toutes les couches automatiques pertinentes sont vertes et que la question dépend réellement du matériel.

Avant de demander une séance à l’utilisateur :

1. vérifier les invariants statiques ;
2. lancer les XCTest iOS/watchOS ;
3. rejouer le scénario synthétique correspondant ;
4. si l’IPA est nécessaire, compiler le SHA exact avec GitHub Actions ;
5. exécuter le self-test USB read-only sur ce même build ;
6. expliquer précisément ce que seul le matériel peut encore valider.

Une observation physique utilisateur reste la validation finale pour HealthKit réel, capteurs, GPS, background et liaison physique iPhone/Watch.

## CI et artifacts

Deux workflows ont des rôles distincts :

- `watch-sensor-lab-tests.yml` : logique/tests simulateurs, sans IPA ;
- `watch-sensor-lab-bootstrap.yml` : compilation iPhone + watchOS, vérifications produit et packaging exact-SHA.

Les deux workflows appellent exclusivement `APPLY_GENERATED_SOURCE_CHAIN.py` pour préparer les sources, deux fois de suite afin de vérifier l'idempotence de la chaîne complète. Les scripts individuels restent dans les phases de pré-build Xcode comme garde-fous pour les compilations locales directes.

Ils s'exécutent pour les pull requests vers `main` qui touchent cette application ou ses workflows, pour les pushes concernés sur `main`, `feat/watch-sensor-*` et `fix/watch-*`, ainsi que manuellement. Les filtres incluent tous les scripts de génération et l'icône afin qu'une modification de l'entrée du build ne contourne pas la CI.

Un push normal reste CI-only. Une IPA n’est conservée que lorsqu’un candidat appareil est réellement demandé.

## Nettoyage

Ne jamais supprimer des données réelles pour nettoyer des tests.

- GitHub : rapports de tests en échec = 1 jour ; candidat IPA = rétention courte existante ;
- Windows : conserver le dernier candidat matériel validé + le candidat courant, puis supprimer les anciens caches après validation ;
- scénarios synthétiques : mémoire uniquement ;
- self-test USB : aucune donnée persistée ;
- toute future session mutable d’automatisation devra être préfixée `automation-` et supprimée exactement par ID ;
- raw forensics, HANDOFF et séances réelles protégées : jamais touchés par le nettoyage automatique.

## Dette transitoire connue

`APPLY_GENERATED_SOURCE_CHAIN.py` centralise temporairement les transformations de build tant que les correctifs n'ont pas été repliés dans les sources Swift réelles. Il ne doit pas devenir permanent.

La fermeture du chantier exige :

1. déplacer la logique validée dans les sources Swift ;
2. faire consommer le noyau `TrackerSessionControl` par la production ;
3. faire passer la suite automatique sans patch de build ;
4. supprimer `SESSION_SYNC_PATCH.py` ;
5. seulement ensuite effectuer le smoke test matériel final nécessaire.
