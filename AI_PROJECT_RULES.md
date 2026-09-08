# ios-godot-lab — règles permanentes IA / développement

> À lire avant toute modification.

## 1. Périmètre strict

- Ce chantier écrit uniquement dans `Rzbck/ios-godot-lab` sauf demande utilisateur explicite distincte.
- Les autres repositories, notamment SIGNAL, peuvent être consultés en **lecture seule** comme référence de méthode.
- Ne jamais pousser, commenter, merger, créer de branche ou modifier un fichier dans un autre repo depuis ce chantier.

## 2. Source de vérité

Avant toute écriture :

1. re-fetch repo/branche ;
2. identifier HEAD réel ;
3. latest activity check ;
4. lire `HANDOFF.md` puis `docs/AI_HANDOFF.md`, `docs/PROJECT_STATE.md`, `docs/GITHUB_WORKFLOW.md` ;
5. localement : repo, worktree, branche, HEAD, CLEAN/DIRTY obligatoires.

Un SHA écrit dans un document n'est jamais supposé courant sans vérification.

## 3. Catégories de validation

Toujours distinguer :

- **VALIDÉ UTILISATEUR** ;
- **VALIDÉ SUR IPHONE** ;
- **BUILD CI VALIDÉ** ;
- **IMPLÉMENTÉ NON VALIDÉ** ;
- **BUG / BLOCKER** ;
- **EXPÉRIMENTAL / HYPOTHÈSE**.

Un build vert ne prouve pas que l'app se lance sur l'iPhone. Une IPA installée ne prouve pas chaque capteur/API.

## 4. Git / branches / worktrees

Règle : **1 chantier actif = 1 branche = 1 worktree dédié**.

- `main` reste sur le worktree permanent `main` ;
- ne pas développer directement sur `main` ;
- deux IA/chantiers ne partagent jamais un worktree en écriture ;
- aucun `reset --hard`, `git clean -fd[x]`, force-push ou rebase destructif automatique ;
- pas de `git add -A` aveugle : pathspecs explicites ;
- promotion `main` uniquement après validation pertinente et accord humain ;
- rollback publié par nouveau commit/revert, pas par réécriture d'historique.

## 5. PowerShell

Les commandes/scripts fournis à l'utilisateur doivent :

- utiliser `$ErrorActionPreference = 'Stop'` ;
- vérifier chaque précondition importante ;
- traiter explicitement les branches `if / elseif / else` ;
- stopper sur état ambigu au lieu de deviner ;
- afficher repo / branche / HEAD / remote / CLEAN-DIRTY avant mutation ;
- ne jamais supprimer un worktree DIRTY ;
- préférer fast-forward strict (`--ff-only`) ;
- éviter toute commande destructive implicite.

## 6. Version moteur / CI

- version cible bootstrap : **Godot 4.7.2 stable** ;
- version CI et version Windows doivent rester alignées ;
- le runner GitHub macOS doit être épinglé à une image explicite lorsque possible, pas seulement `macos-latest` ;
- tout IPA doit être associé au SHA exact qui l'a produit ;
- les artifacts doivent inclure le SHA court dans leur nom ou un manifeste embarqué.

## 7. Distribution locale des IPA

Règle permanente : **ne plus donner à l'utilisateur des liens GitHub Actions à cliquer pour récupérer les IPA**.

- Les IPA restent des artifacts GitHub Actions, pas des binaires commités dans Git.
- Le poste Windows récupère les artifacts avec `UPDATE_IOS_LAB.ps1` via GitHub CLI (`gh`).
- Le script met à jour la branche courante uniquement par fast-forward strict, exige un worktree CLEAN, puis cherche un build iOS `success` pour le HEAD exact.
- Si aucun build exact n'existe encore, le script déclenche lui-même `build-ios-unsigned.yml` sur la branche courante, attend le résultat, puis continue uniquement si ce build exact termine en `success`.
- Il télécharge ensuite uniquement l'artifact `ios-unsigned-<SHA exact>`, vérifie `BUILD-METADATA.json` et le SHA-256 de l'IPA, puis range le résultat dans `artifacts/<sha-court>/`.
- Le dossier `artifacts/` est local et ignoré par Git.
- Ne jamais substituer « dernier artifact disponible » à « artifact du SHA exact » sans le dire explicitement.
- Si le build exact échoue, est annulé ou time out, STOP : ne pas installer silencieusement un build d'un autre SHA.

## 8. Apple / secrets

Ne jamais committer :

- mot de passe Apple ;
- app-specific password ;
- certificat privé / `.p12` ;
- provisioning profile contenant des données sensibles si une solution évite de le versionner ;
- pairing file SideStore ;
- tokens GitHub.

Le Team ID et le bundle identifier ne sont pas traités comme mots de passe, mais leur valeur doit être intentionnelle et documentée.

## 9. Sideload gratuit retenu

**SideStore** est la solution par défaut parce qu'après l'installation initiale elle peut rafraîchir périodiquement les apps en arrière-plan sans PC.

Contraintes à conserver dans toute UX/documentation :

- profil gratuit Apple : 7 jours ;
- 3 apps installées max par appareil, SideStore inclus ;
- 10 App IDs ;
- LocalDevVPN requis lors des opérations SideStore ;
- le rafraîchissement de fond dépend de la planification iOS : il faut prévoir un indicateur/contrôle et ne jamais promettre une garantie absolue à la seconde près ;
- préférer les serveurs anisette v3 officiels ou un v3 auto-hébergé ; éviter les anciens serveurs partagés signalés comme risqués par la documentation SideStore.

## 10. APIs iPhone

Principe : **Godot d'abord, plugin iOS natif seulement quand nécessaire**.

- capteurs de mouvement de base : API Godot lorsque disponible ;
- caméra : CameraServer/module caméra Godot ;
- fonctions Apple spécifiques : plugin iOS `.xcframework`/`.a` + `.gdip` exposé à GDScript ;
- respecter permissions, entitlements, sandbox et limitations de fond Apple ;
- ne jamais dire « accès total au téléphone » : seules les APIs publiques et capacités autorisées par iOS sont utilisables.

## 11. Fin de session

Mettre à jour si l'état change :

- `docs/AI_HANDOFF.md` ;
- `docs/PROJECT_STATE.md` si invariant/architecture ;
- `docs/AI_SESSION_LOG.md` pour le delta compact ;
- `HANDOFF.md` seulement si routage/règle permanente change.

Ne jamais copier une conversation complète dans Git.
