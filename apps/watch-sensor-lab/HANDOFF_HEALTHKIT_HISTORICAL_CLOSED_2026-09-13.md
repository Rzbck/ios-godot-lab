# HANDOFF — Historical HealthKit reconstruction — CLOSED — 2026-09-13

## Statut

Chantier clos et accepté par l’utilisateur après validation matérielle sur iPhone.

La reconstruction historique de la session `1789141684582` est considérée **validée pour la carte / distance / type / effort**, avec une limite résiduelle connue : **l’icône de l’application n’est toujours pas affichée dans Santé/Forme**. Cette limite est acceptée pour clôturer le chantier et passer au chantier produit suivant.

## Dépôt / worktree / branche

- dépôt : `Rzbck/ios-godot-lab`
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-healthkit-historical-unification`
- branche : `fix/watch-healthkit-historical-unification-20260912`
- **SHA applicatif physiquement testé et accepté** : `4e22a2a9a41d62fb29f686a8092a5ebf69bcb647`
- build iPhone/Watch : `6`
- version : `0.4.0`
- CI exact-SHA : run `34747676612`, job `103698498096`, succès complet

Ne pas confondre le futur HEAD documentaire de la branche avec le SHA applicatif réellement installé et testé ci-dessus.

## Validation matérielle finale

Session cible : `1789141684582`.

Résultat accepté :

- type HealthKit : `cycling` / raw `13` / Vélo ;
- distance HealthKit relue : `2801.38591338122 m` (~`2.80 km`) ;
- effort Apple relié : `3/10` ;
- source HealthKit : `Watch Tracker` ;
- bundle source : `com.rzbck.watchsensorlab.59858TV9N2` ;
- source version : `6` ;
- bundle source correspond au bundle installé ;
- 6 `HKWorkoutRoute` sauvegardées ;
- 441 positions sauvegardées ;
- géométrie sauvegardée : ~`3124.06 m` ;
- le segment de réacquisition GPS parasite autour de `15:53:47–15:53:52Z` a été retiré du tracé écrit ;
- utilisateur : **carte bonne / grand trait rouge parasite corrigé** ;
- diagnostic USB après écriture : `internally_verified=True` ;
- `WSL.ps1 errors -Limit 50` : aucun enregistrement.

## Limite acceptée

L’icône de l’application reste absente dans Santé/Forme malgré :

- `AppIcon` présent et déclaré dans le bundle ;
- `CFBundleIcons` / dictionnaire d’icône principal présents ;
- workout écrit par le bon bundle ;
- source HealthKit versionnée en build `6`.

Ne pas réintroduire `HKMetadataKeyWorkoutBrandName: "Watch Tracker"` pour tenter de forcer une identité visuelle : cet ancien essai faisait afficher `Watch Tracker` à la place du type `Vélo`.

Le problème d’icône est classé comme limite visuelle non bloquante pour ce chantier.

## Correctif déterminant

Le correctif final ne supprime plus de gros morceaux de route. Il conserve la route riche et traite spécifiquement la fausse réacquisition GPS stationnaire :

- GPS iPhone initialement imprécis (~35 m) ;
- déplacement géométrique artificiel d’environ 76.8 m ;
- compteur `distance_m` figé ;
- vitesse nulle pendant le recalage ;
- précision qui converge ensuite vers ~3.6 m.

Le préfixe de réacquisition fautif est exclu au stade de segmentation HealthKit, sans altérer le scalaire de distance et sans supprimer le reste du segment.

## À préserver

- ne jamais modifier les raw/snapshot de `1789141684582` ;
- ne pas supprimer les deux workouts réels `1789198788819` et `1789196258375` ;
- garder le pipeline exact-SHA `UPDATE_WATCH_SENSOR_LAB.ps1` + iLoader ;
- garder l’API diagnostic USB en lecture seule ;
- ne pas revenir au filtre global agressif de `f9b4...` ou à la quarantaine de segment entière de `c105...` ;
- ne pas réouvrir le problème d’icône sauf demande explicite de l’utilisateur.

## Prochain chantier prévu

Passer au chantier produit suivant, dans cet ordre :

1. **synchronisation / fin de séance iPhone + Apple Watch** pour qu’un seul état fasse autorité et éviter toute concurrence entre les deux appareils ;
2. UI de confirmation de fin de séance ;
3. mode `Auto` / détection et sélection d’activité ;
4. réutiliser ensuite les enseignements compteur/GPS/segmentation dans le tracking live, sans copier aveuglément le code de reconstruction historique.

Avant toute modification du prochain chantier : retrouver son worktree/HANDOFF dédié, vérifier branche, HEAD, `git status`, tests/CI et point d’arrêt réel.
