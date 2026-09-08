# HANDOFF — point d'entrée unique pour reprise IA

Ce fichier est le routeur de reprise de `ios-godot-lab`.

Si une nouvelle conversation concernant ce repository commence simplement par **`HANDOFF`**, repartir du repository GitHub courant et de ses HEAD réels, jamais d'un ancien chat.

## 1. Avant toute action

1. Vérifier `Rzbck/ios-godot-lab`, la branche concernée et leurs HEAD réels.
2. Faire un latest-activity check : branches, commits, PR/Issues et derniers artefacts CI pertinents.
3. Lire les sources ci-dessous dans l'ordre canonique.
4. Ne jamais considérer un SHA documentaire comme HEAD courant sans vérification.
5. Information absente ou contradictoire = **à vérifier**, jamais à inventer.
6. Avant toute commande locale de modification, identifier repo, worktree, branche, HEAD et CLEAN/DIRTY.
7. Ne jamais modifier un autre repository depuis un chantier `ios-godot-lab`, sauf demande utilisateur explicite distincte. Les autres repos peuvent être lus comme référence uniquement.

## 2. Ordre de lecture canonique

1. `AI_PROJECT_RULES.md` — règles permanentes.
2. `docs/AI_HANDOFF.md` — état courant / point exact de reprise.
3. `docs/PROJECT_STATE.md` — architecture et décisions consolidées.
4. `docs/AI_SESSION_LOG.md` — delta récent compact.
5. `docs/GITHUB_WORKFLOW.md` — discipline branches/worktrees/publication.
6. Documents du domaine concerné (`docs/IOS_*.md`, `docs/BUILD_*.md`, etc.).

Après lecture, toujours réconcilier les documents avec l'activité GitHub réellement la plus récente.

## 3. Sources de vérité

- Git HEAD + fichiers réellement présents indiquent ce qui existe.
- Code présent != fonction validée sur iPhone.
- Un build CI réussi valide uniquement le build réellement exécuté.
- Une installation réussie sur l'iPhone valide uniquement le SHA/IPA effectivement testé.
- `HANDOFF.md` route la reprise ; `docs/AI_HANDOFF.md` donne le point immédiat ; `docs/PROJECT_STATE.md` l'état consolidé ; `docs/AI_SESSION_LOG.md` le delta récent.

## 4. Catégories obligatoires

Toujours distinguer :

- **VALIDÉ UTILISATEUR** ;
- **VALIDÉ SUR IPHONE** ;
- **BUILD CI VALIDÉ** ;
- **IMPLÉMENTÉ MAIS NON VALIDÉ UTILISATEUR** ;
- **BUG / LIMITE / BLOCKER** ;
- **EXPÉRIMENTAL / HYPOTHÈSE** ;
- **PROCHAIN TEST / PROCHAIN CHANTIER**.

## 5. Travail local parallèle

Règle permanente : **1 chantier actif = 1 branche = 1 worktree dédié**.

- le worktree permanent `main` reste sur `main` ;
- deux chantiers/IA simultanés n'écrivent jamais dans le même worktree ;
- avant de proposer un chemin local : `git worktree list --porcelain`, branche, HEAD et CLEAN/DIRTY ;
- un detached HEAD sert aux validations exact-SHA, pas à un chantier long ;
- aucun `reset --hard`, `clean -fd[x]`, force-push ou autre nettoyage destructif automatique.

### Invariant PowerShell interactif

Quand l'utilisateur doit **copier-coller un gros bloc directement dans une console PowerShell interactive**, tout bloc contenant `if / elseif / else`, `try / catch / finally`, fonctions ou boucles doit être encapsulé dans un bloc unique :

```powershell
& {
    # tout le script ici
}
```

Ne jamais fournir `if { ... }`, puis `elseif { ... }`, puis `else { ... }` comme unités interactives séparées : lors d'un collage, PowerShell peut exécuter le `if` dès qu'il est syntaxiquement complet puis interpréter `else` comme une nouvelle commande. Cette panne a été reproduite le 2026-09-07 pendant le bootstrap Windows du projet.

Après toute erreur dans un gros collage, vérifier l'état réel avant de « relancer tout » : certaines instructions suivantes peuvent quand même avoir été exécutées. Voir `docs/POWERSHELL_WORKTREE_WORKFLOW.md` pour les règles détaillées.

### Invariant artifacts iOS

Ne plus transmettre les IPA à l'utilisateur sous forme de lien GitHub Actions à cliquer.

- GitHub Actions reste la source des artifacts de build ; les `.ipa` ne sont pas commités dans Git.
- Le poste Windows récupère l'IPA exact-SHA via `UPDATE_IOS_LAB.ps1` et GitHub CLI.
- Le script exige un worktree CLEAN, fait seulement un fast-forward strict de la branche courante et cherche un build iOS `success` pour le HEAD exact.
- Si aucun build exact n'existe encore, le script déclenche lui-même le workflow iOS sur cette branche et attend sa fin.
- Si le build exact réussit, le script télécharge uniquement l'artifact de ce SHA, vérifie `BUILD-METADATA.json` et le SHA-256, puis range le résultat dans le dossier local `artifacts/<sha-court>/`.
- Si le build exact échoue/est annulé/time out, STOP : ne jamais prendre silencieusement un artifact d'un autre SHA.

## 6. But permanent

Développer depuis Windows des applications iPhone avec Godot, compiler sur un runner macOS GitHub Actions standard d'un repository public, produire un IPA testable et l'installer sur un iPhone personnel avec une chaîne gratuite quand Apple le permet.

La solution de sideload retenue au bootstrap est **SideStore** pour son rafraîchissement périodique en arrière-plan des apps signées avec un compte Apple gratuit. Les limites Apple (profil 7 jours, 3 apps par appareil, 10 App IDs) restent des contraintes de plateforme et doivent être documentées, pas contournées silencieusement.

## 7. Raccourci mental

`HANDOFF -> HEADs -> latest activity -> règles -> état -> worktree exact -> changement minimal -> UPDATE_IOS_LAB.ps1 -> build CI exact-SHA si nécessaire -> IPA exact local -> test iPhone -> classification -> publication humaine`
