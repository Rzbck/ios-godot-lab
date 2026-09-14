# HANDOFF — Auto-pause, Auto-sport et validation finale — 2026-09-14

## Objectif

Rendre le mode Auto réactif sans réglage utilisateur de délai, supprimer le biais initial vers Marche, permettre à GPS/cadence de corriger un signal Core Motion erroné et garantir la correction du sport avant l'enregistrement final.

## Dépôt et candidat exact

- dépôt : `Rzbck/ios-godot-lab`
- application : `apps/watch-sensor-lab`
- branche : `fix/watch-auto-behavior-20260914`
- worktree : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-auto-behavior`
- base indiquée comme physiquement validée par l'utilisateur : `f97aaf09181763d9e816fced23da040d6da6819a`
- candidat applicatif compilé et testé : `bedf8795f3af0f9e5f6ee75e85b582606e28f3d6`

Le commit documentaire contenant ce HANDOFF est postérieur au candidat applicatif. Il ne modifie aucun fichier compilé. Toujours vérifier les HEAD Git/GitHub réels avant reprise.

## Changements du chantier

- un seul contrôle utilisateur `Pause automatique` ; les profils et délais réglables ont disparu de l'interface ;
- démarrage Auto neutre au lieu d'un démarrage artificiel en Marche ;
- fusion Core Motion + GPS + cadence pour Marche, Course et Vélo ;
- GPS/cadence peuvent dépasser un ancien signal Marche lorsque les preuves Course/Vélo sont fortes ;
- réévaluation à chaque donnée GPS/cadence utile, sans attendre un nouvel événement Core Motion ;
- stabilisation Auto ramenée à une fenêtre interne maximale de 2,5 s ;
- pause/reprise automatique générique disponible pour les sports du catalogue ;
- pause impossible au démarrage avant qu'un déplacement réel ait été observé ;
- GPS de reprise maintenu pendant une pause automatique ;
- pause manuelle toujours prioritaire et jamais reprise automatiquement ;
- validation/correction finale existante conservée sur iPhone et Watch ;
- le chemin `forceSingleActivity` réduit le plan Santé complet au sport confirmé avant l'arrêt, au lieu de créer un minuscule segment final ;
- tests de replay alignés sur le runtime : démarrage neutre, fusion GPS/cadence et armement après mouvement réel.

## Incident CI corrigé

Le build `34884175835` échouait dans `Apply Reactive Auto Behavior Patch`, avant compilation Swift. Le garde-fou cherchait une phrase de commentaire continue alors qu'elle était générée sur deux lignes. Le marqueur utilise désormais les deux lignes de code stables :

```text
automaticActivityStartedAt = nil
automaticActivitySeconds = [:]
```

La chaîne `SESSION_SYNC_PATCH.py` puis les patchs de pré-build a été vérifiée en exécution répétée avec `uv`.

## Validation automatisée du candidat

### BUILD CI VALIDÉ

- SHA : `bedf8795f3af0f9e5f6ee75e85b582606e28f3d6`
- workflow : `watch-sensor-lab-bootstrap.yml`
- run : `34886672233`
- résultat : succès complet
- build iPhone unsigned : succès
- build watchOS unsigned : succès
- companion Watch intégrée : succès
- contrôles HealthKit : succès
- IPA exacte empaquetée et publiée : succès

### TESTS CI VALIDÉS

- SHA : `bedf8795f3af0f9e5f6ee75e85b582606e28f3d6`
- workflow : `watch-sensor-lab-tests.yml`
- run : `34886615605`
- résultat : succès complet
- préflight : succès
- contrat iPhone : 44 tests, succès
- contrat Watch : 44 tests, succès
- UI iPhone : force / preserve / cancel, succès
- UI Watch : force / preserve / cancel, succès

## IPA récupérée et vérifiée

- chemin : `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\bedf8795f3af\WatchSensorLab-companion-unsigned-bedf8795f3af.ipa`
- SHA-256 : `12d4c50b4232082803c717023c95504947d2dc9486b1365ca56c005492a9067f`
- metadata locale : `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\LATEST.json`
- récupération effectuée avec `UPDATE_WATCH_SENSOR_LAB.ps1 -ExpectedBranch fix/watch-auto-behavior-20260914 -NoAutoBuild`

## Pas encore validé physiquement

- installation de cette IPA exacte avec iLoader ;
- pause puis reprise automatique en Marche, Course et Vélo réels ;
- absence de faux déclenchement au démarrage ;
- détection Vélo lorsque Core Motion reste sur Marche ;
- correction finale du sport et résultat visible dans Santé/Forme ;
- pertinence de la politique générique pour chaque sport du catalogue, particulièrement les activités sur place ou sans GPS exploitable.

Les délais internes restent des mécanismes de stabilisation : pause 2,0 s, reprise 0,8 s et changement Auto au plus 2,5 s. Ils ne sont plus exposés à l'utilisateur et ne constituent pas, seuls, une validation d'un comportement adaptatif sur le terrain.

## Prochain test exact

1. Installer l'IPA ci-dessus avec le pipeline iLoader existant.
2. Démarrer en Auto et vérifier qu'aucune pause ni Marche ne sont inventées avant le premier déplacement.
3. Tester arrêt/reprise en Marche, Course et Vélo.
4. Faire un court trajet Vélo et vérifier que la séance ne finit pas en Marche.
5. À l'écran final, choisir volontairement un autre sport, valider, puis contrôler le type réellement écrit dans Santé/Forme.
6. Noter le SHA installé et chaque observation matérielle dans ce HANDOFF avant toute promotion.

## Ne pas modifier depuis cette reprise

- ne pas reprendre le chantier de récupération historique clos ;
- ne pas créer un second downloader d'IPA ;
- ne pas modifier les dépôts iLoader/isideload depuis ce chantier produit ;
- ne pas merger dans `main`, publier une release ou promouvoir ce candidat sans accord explicite ;
- ne jamais présenter la CI ou l'IPA récupérée comme une validation matérielle.
