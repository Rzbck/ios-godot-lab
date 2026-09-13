# Watch Sensor Lab — stratégie de test durable

Date de mise en place : 2026-09-13

## Objectif

Réduire au minimum les séances physiques de développement. Une personne ne doit pas marcher, courir ou pédaler pour vérifier une régression de logique, un bouton, une transition d’état ou un cas de concurrence iPhone/Watch.

Le matériel réel reste nécessaire uniquement pour les comportements que Simulator et les doubles de test ne peuvent pas prouver : HealthKit réel, capteurs réels, GPS réel, background/écran verrouillé, installation/signature, mirroring iPhone/Watch et comportement physique de l’Apple Watch.

## Pyramide de validation

### 1. Garde-fous statiques

`CHECK_WORKFLOW_PARITY.py` et `CHECK_PRODUCT_INVARIANTS.py` doivent échouer tôt lorsqu’une surface iPhone/Watch diverge, lorsqu’un ancien ACK implicite revient, ou lorsqu’un noyau déterministe acquiert une dépendance à un framework matériel/UI.

### 2. Noyaux déterministes partagés

La logique qui peut être pure doit vivre hors de HealthKit/CoreMotion/WatchConnectivity/SwiftUI :

- `Shared/TrackerSessionControl.swift` : sérialisation et arbitrage des commandes de session ;
- `Shared/TrackerAutoPolicy.swift` : règles Auto, pause et reprise à partir d’évidence synthétique.

Les adaptateurs iPhone/watchOS traduisent les API Apple vers ces types. Les règles ne doivent pas être recopiées dans les vues ou dans plusieurs modèles.

### 3. XCTest iOS + watchOS

Le workflow `.github/workflows/watch-sensor-lab-tests.yml` exécute la même suite sur un simulateur iPhone et un simulateur Apple Watch courants.

Les tests doivent couvrir au minimum :

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
- GPS faible ou valeurs limites ;
- futures pertes de liaison et retards de commande.

Le format doit rester indépendant du matériel pour être réutilisable par XCTest, UI tests et un futur self-test USB read-only.

### 5. UI automation

Étape suivante : ajouter des `accessibilityIdentifier` stables et des cibles UI-test iPhone/watchOS. Les UI tests démarreront l’application avec un état synthétique et vérifieront les actions de fin sans créer une vraie séance HealthKit.

Exemples d’identifiants prévus :

- `tracker.finish.button`
- `tracker.finish.preserveAuto`
- `tracker.finish.activityPicker`
- `tracker.finish.confirmSingle`
- `tracker.finish.cancel`

### 6. Self-test USB sur appareil

`wsl_diag_v1` reste read-only. Il ne doit pas devenir une télécommande générale des vraies séances.

Un futur self-test appareil devra :

- exécuter uniquement des règles pures/scénarios synthétiques ;
- ne jamais démarrer `HKWorkoutSession` ;
- ne jamais écrire/supprimer HealthKit ;
- ne jamais appeler `deleteAllSessions()` ;
- retourner build SHA + résultats détaillés ;
- être idempotent et ne laisser aucun état après exécution.

Si un jour un test mutable appareil est nécessaire, il utilisera un store séparé et une session explicitement préfixée `automation-`, avec suppression exacte de cette session uniquement.

## CI et artifacts

Deux workflows ont des rôles distincts :

- `watch-sensor-lab-tests.yml` : logique/tests simulateurs, sans IPA ;
- `watch-sensor-lab-bootstrap.yml` : compilation iPhone + watchOS, vérifications produit et packaging exact-SHA.

Un push normal reste CI-only. Une IPA n’est conservée que lorsqu’un candidat appareil est réellement demandé. Les diagnostics et artifacts courts doivent garder une rétention faible.

## Quand demander un test physique

Un test physique n’est demandé que si toutes les couches automatiques pertinentes sont vertes et que la question dépend réellement du matériel.

Avant de demander à l’utilisateur de faire une séance :

1. vérifier les invariants ;
2. lancer les XCTest iOS/watchOS ;
3. rejouer le scénario synthétique correspondant ;
4. vérifier le build exact-SHA ;
5. expliquer précisément ce que seul le matériel peut encore valider.

Une observation physique utilisateur reste la validation finale pour ce qui dépend réellement du device.

## Nettoyage

Ne jamais supprimer des données réelles pour nettoyer des tests.

- GitHub : diagnostics de tests en échec = 1 jour ; candidat IPA = rétention courte existante ;
- Windows : conserver le dernier candidat matériel validé + le candidat courant, puis supprimer les anciens caches après validation ;
- sessions synthétiques : mémoire/store temporaire uniquement ;
- futures sessions appareil `automation-*` : suppression exacte par ID ;
- raw forensics, HANDOFF et séances réelles protégées : jamais touchés par le nettoyage automatique.

## Dette transitoire connue

`SESSION_SYNC_PATCH.py` reste un mécanisme candidat de build tant que le correctif de synchronisation n’a pas été replié dans les sources Swift réelles. Il ne doit pas devenir permanent. La fermeture du chantier exige de déplacer la logique validée dans les sources, faire passer la suite automatique sans patch de build, puis supprimer ce helper.
