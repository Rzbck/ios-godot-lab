# Discipline GitHub / PowerShell — ios-godot-lab

## 1. Source de vérité

- `main` = dernière version publiée/testable.
- Le dépôt réel prime sur l'ancien chat.
- Toute reprise commence par `/HANDOFF.md`.
- Tout build/test doit être attribuable à un SHA exact.
- Le handoff ne s'auto-déclare jamais HEAD : le HEAD réel est toujours re-fetché.

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

## 5. CI Godot rapide

`verify-godot.yml` :

1. checkout SHA exact ;
2. Godot 4.7.2 verrouillé ;
3. import/parse ;
4. `tests/smoke_project.gd` ;
5. aucune conclusion hardware/iPhone à partir de ce PASS.

## 6. CI iOS

`build-ios-unsigned.yml` est **manuel (`workflow_dispatch`)** après le bootstrap.

Le workflow :

1. tourne sur `macos-26` ;
2. checkout le SHA exact déclencheur ;
3. installe Godot 4.7.2 verrouillé ;
4. installe les export templates correspondants ;
5. stamp le SHA dans `config/build_info.json` ;
6. exporte le projet Godot vers Xcode ;
7. construit le scheme `IOSGodotLab` Release / `generic/platform=iOS` avec signature désactivée ;
8. exige que `codesign --verify` échoue ;
9. empaquette `Payload/*.app` en `.ipa` ;
10. produit `BUILD-METADATA.json` contenant repo/ref/SHA/Godot/Xcode/SDK ;
11. produit le SHA-256 de l'IPA ;
12. upload l'IPA + manifeste + hash comme artifact ;
13. échoue si une précondition manque au lieu de produire un artifact ambigu.

Premier BUILD IOS VALIDÉ :

- SHA `8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- run `34160430197` ;
- `BUILD SUCCEEDED` ;
- IPA `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d`.

## 7. Publication `main`

Avant merge/promotion :

- branche re-fetchée ;
- `main` re-fetché ;
- diff final connu ;
- CI pertinente verte ;
- aucune donnée secrète ;
- handoff/state/log réconciliés ;
- accord humain.

Aucun merge automatique de la branche bootstrap n'est autorisé simplement parce que le build iOS passe.

## 8. Test iPhone exact-SHA

Lorsqu'une IPA est installée : consigner au minimum :

- SHA Git ;
- nom artifact ;
- SHA-256 IPA ;
- version Godot/Xcode ;
- modèle/iOS si pertinent ;
- résultat lancement ;
- capacités réellement testées.

Ne jamais reporter une validation d'une IPA vers un autre SHA.

## 9. SideStore

SideStore signe/installera l'IPA unsigned avec le compte Apple gratuit de l'utilisateur. Le refresh 7 jours est un mécanisme de distribution/test, pas une preuve que les fonctions iPhone marchent.

## 10. Nettoyage / rollback

- jamais `reset --hard`, `clean -fd[x]`, force-push ou rebase destructif automatique ;
- worktree DIRTY = HOLD jusqu'à inventaire ;
- rollback publié = nouveau commit/revert propre ;
- branche/worktree supprimable uniquement après identité, CLEAN, publication/préservation et absence d'usage actif.
