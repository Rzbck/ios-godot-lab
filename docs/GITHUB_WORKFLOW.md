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

Le workflow `build-ios-unsigned.yml` doit toujours produire un artifact exact-SHA et ne jamais mélanger les sorties de deux commits.

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

## 7. Synchronisation locale des artifacts

Les liens de téléchargement GitHub Actions ne font **pas** partie du workflow utilisateur normal.

Commande canonique depuis le worktree de la branche à tester :

```powershell
.\UPDATE_IOS_LAB.ps1 -OpenFolder
```

Le script :

1. exige `git` et GitHub CLI `gh` ;
2. vérifie repository, origin, branche, HEAD et CLEAN/DIRTY ;
3. refuse un detached HEAD et refuse tout worktree DIRTY ;
4. fait `git fetch origin --prune` ;
5. met uniquement la branche courante à jour via `git merge --ff-only origin/<branche>` ;
6. demande à GitHub Actions un run iOS `success` pour **ce HEAD exact** ;
7. télécharge uniquement l'artifact `ios-unsigned-<SHA exact>` ;
8. vérifie que `BUILD-METADATA.json.sha == HEAD` ;
9. recalcule le SHA-256 de l'IPA et le compare au fichier `.ipa.sha256` ;
10. range l'artifact dans le dossier local central `artifacts/<sha-court>/` ;
11. écrit `artifacts/LATEST.json` et `artifacts/LATEST_IPA.txt` ;
12. n'écrase jamais silencieusement un dossier artifact existant invalide.

Avec l'arborescence Windows canonique du projet, le dossier central est :

```text
E:\_Project\IOS APP\ios-godot-lab\artifacts\
```

Les `.ipa` ne doivent pas être commités dans Git. `artifacts/` et `*.ipa` sont ignorés.

## 8. Publication `main`

Avant merge/promotion :

- branche re-fetchée ;
- `main` re-fetché ;
- diff final connu ;
- CI pertinente verte ;
- aucune donnée secrète ;
- handoff/state/log réconciliés ;
- accord humain.

Aucun merge automatique d'une branche de travail n'est autorisé simplement parce que le build iOS passe.

## 9. Test iPhone exact-SHA

Lorsqu'une IPA est installée : consigner au minimum :

- SHA Git ;
- nom artifact ;
- SHA-256 IPA ;
- version Godot/Xcode ;
- modèle/iOS si pertinent ;
- résultat lancement ;
- capacités réellement testées.

Ne jamais reporter une validation d'une IPA vers un autre SHA.

## 10. SideStore / iLoader

SideStore ou iLoader signent/installent l'IPA unsigned avec le compte Apple de l'utilisateur. Le mécanisme de sideload n'est pas une preuve que les fonctions iPhone marchent.

## 11. Nettoyage / rollback

- jamais `reset --hard`, `clean -fd[x]`, force-push ou rebase destructif automatique ;
- worktree DIRTY = HOLD jusqu'à inventaire ;
- rollback publié = nouveau commit/revert propre ;
- branche/worktree supprimable uniquement après identité, CLEAN, publication/préservation et absence d'usage actif.
