# Discipline GitHub / PowerShell — ios-godot-lab

## 1. Source de vérité

- `main` = dernière version publiée/testable.
- Le dépôt réel prime sur l'ancien chat.
- Toute reprise commence par `/HANDOFF.md`.
- Tout build/test doit être attribuable à un SHA exact.

## 2. Branches

Convention :

- `bootstrap/...` : fondations temporaires ;
- `feat/...` : fonctionnalité ;
- `fix/...` : correction ;
- `test/...` : instrumentation/validation ;
- `checkpoint/...` : point durable exceptionnel avant étape risquée.

Pas de développement direct sur `main`.

## 3. Worktrees Windows

Règle : **1 chantier = 1 branche = 1 worktree**.

Avant toute mutation locale :

```powershell
$ErrorActionPreference = 'Stop'

git rev-parse --show-toplevel
git worktree list --porcelain
git branch --show-current
git rev-parse HEAD
git status --porcelain
```

Interprétation obligatoire :

- CLEAN = sortie `git status --porcelain` vide ;
- DIRTY = ne pas changer/supprimer le worktree sans inventaire ;
- branche déjà liée à un worktree = réutiliser ce worktree après contrôle ;
- branche absente = la créer depuis le `origin/main` fraîchement fetché ;
- local en retard seulement = fast-forward `--ff-only` ;
- local en avance/divergent = STOP et analyser ;
- jamais reset/rebase/force automatique.

## 4. Commits

- scope minimal ;
- pathspecs explicites ;
- pas de `git add -A` aveugle ;
- secrets/pairing/certificats exclus ;
- inspecter `git diff --cached` avant commit.

## 5. CI iOS

Le workflow cible doit :

1. tourner sur runner macOS standard explicite ;
2. checkout le SHA exact déclencheur ;
3. installer une version Godot verrouillée ;
4. installer les export templates correspondants ;
5. exporter le projet Godot vers Xcode ;
6. lancer `xcodebuild` avec signature désactivée ;
7. empaqueter `Payload/*.app` en `.ipa` ;
8. produire `BUILD-METADATA.json` contenant repo/ref/SHA/Godot/Xcode/date ;
9. uploader l'IPA + manifeste comme artifact ;
10. échouer si une précondition manque au lieu de produire un artifact ambigu.

Au bootstrap, privilégier `workflow_dispatch` manuel. Le build automatique sur tags/releases pourra venir ensuite.

## 6. Publication `main`

Avant merge/promotion :

- branche re-fetchée ;
- `main` re-fetché ;
- diff final connu ;
- CI pertinente verte ;
- aucune donnée secrète ;
- handoff/state/log réconciliés ;
- accord humain.

## 7. Test iPhone exact-SHA

Lorsqu'une IPA est installée : consigner au minimum :

- SHA Git ;
- nom artifact ;
- version Godot ;
- modèle/iOS si pertinent ;
- résultat lancement ;
- capacités réellement testées.

Ne jamais reporter une validation d'une IPA vers un autre SHA.
