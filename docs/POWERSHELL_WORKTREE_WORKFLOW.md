# PowerShell — règles pratiques de travail local

Objectif : éviter les erreurs de branche/worktree, les `else` cassés en collage interactif et les diagnostics faux positifs.

## Règle critique — gros blocs collés directement dans PowerShell

Quand une commande est destinée à être **copiée-collée directement dans une console PowerShell interactive**, tout bloc multi-instructions contenant `if / elseif / else`, `try / catch / finally`, fonctions ou boucles doit être encapsulé dans un script block unique :

```powershell
& {
    $ErrorActionPreference = 'Stop'

    if ($conditionA) {
        Write-Host 'A'
    }
    elseif ($conditionB) {
        Write-Host 'B'
    }
    else {
        Write-Host 'C'
    }
}
```

Pourquoi : lors d'un gros collage interactif, PowerShell/Terminal peut exécuter un `if { ... }` dès qu'il considère cette instruction complète, puis recevoir `elseif` ou `else` au prompt suivant. Le résultat est alors :

```text
else: The term 'else' is not recognized...
elseif: The term 'elseif' is not recognized...
```

Cette erreur a été reproduite lors du bootstrap local `ios-godot-lab` le 2026-09-07. Le simple fait d'écrire un `else` correct syntaxiquement ne suffit donc pas pour nos gros blocs copiés-collés directement dans la console.

**Règle permanente du projet :**

- bloc court sans branchement : collage direct acceptable ;
- gros bloc interactif avec branchements : toujours `& { ... }` autour de l'ensemble ;
- si l'on fournit un fichier `.ps1`, l'encapsulation externe n'est pas nécessaire ;
- ne jamais envoyer `if { ... }`, puis `elseif { ... }`, puis `else { ... }` comme instructions interactives séparées ;
- après une erreur de parsing/exécution, ne pas supposer que la suite du collage s'est arrêtée : vérifier ce qui a réellement été créé/modifié avant toute reprise.

## Règles de robustesse observées pendant le bootstrap

### Comparaison de chemins

Git peut retourner :

```text
E:/_Project/IOS APP/...
```

alors que PowerShell manipule :

```text
E:\_Project\IOS APP\...
```

Ne pas comparer ces chaînes brutes. Normaliser les chemins avant comparaison, par exemple :

```powershell
$expected = [IO.Path]::GetFullPath($expectedPath).TrimEnd('\', '/')
$actual   = [IO.Path]::GetFullPath(($gitPath -replace '/', '\')).TrimEnd('\', '/')

if ($actual -ine $expected) {
    throw "Repository inattendu : $gitPath"
}
```

### `Set-StrictMode` et objets hétérogènes

Avec `Set-StrictMode -Version Latest`, ne pas supposer qu'une propriété comme `DisplayName` existe sur chaque entrée du registre.

Préférer :

```powershell
$prop = $entry.PSObject.Properties['DisplayName']

if ($null -eq $prop) {
    # ignorer
}
elseif ([string]::IsNullOrWhiteSpace([string]$prop.Value)) {
    # ignorer
}
else {
    $name = [string]$prop.Value
}
```

## Préflight obligatoire

Depuis le repo/worktree concerné :

```powershell
& {
    $ErrorActionPreference = 'Stop'

    $repoRoot = (git rev-parse --show-toplevel).Trim()
    if ([string]::IsNullOrWhiteSpace($repoRoot)) {
        throw 'Repository Git introuvable.'
    }

    $branch = (git branch --show-current).Trim()
    $head   = (git rev-parse HEAD).Trim()
    $status = @(git status --porcelain)

    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Detached HEAD: chantier long interdit dans cet etat.'
    }
    elseif ($status.Count -eq 0) {
        $cleanState = 'CLEAN'
    }
    else {
        $cleanState = 'DIRTY'
    }

    Write-Host "REPO   = $repoRoot"
    Write-Host "BRANCH = $branch"
    Write-Host "HEAD   = $head"
    Write-Host "STATE  = $cleanState"

    git worktree list --porcelain
}
```

## Synchronisation sûre

```powershell
& {
    $ErrorActionPreference = 'Stop'

    git fetch origin --prune

    $branch = (git branch --show-current).Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw 'Detached HEAD: synchro standard bloquee.'
    }

    $dirty = @(git status --porcelain)
    if ($dirty.Count -gt 0) {
        throw 'Worktree DIRTY: synchro automatique bloquee.'
    }

    $remoteRef = "origin/$branch"
    $remoteExists = $false
    git show-ref --verify --quiet "refs/remotes/$remoteRef"
    if ($LASTEXITCODE -eq 0) {
        $remoteExists = $true
    }
    elseif ($LASTEXITCODE -eq 1) {
        $remoteExists = $false
    }
    else {
        throw "Impossible de verifier $remoteRef."
    }

    if ($remoteExists) {
        git merge --ff-only $remoteRef
        if ($LASTEXITCODE -ne 0) {
            throw 'Fast-forward impossible: STOP, analyser la divergence.'
        }
    }
    else {
        Write-Host "Pas encore de branche distante $remoteRef : aucune fusion automatique."
    }
}
```

## Interdits par défaut

Ne pas utiliser pour « réparer vite » :

```text
git reset --hard
git clean -fd
git clean -fdx
git push --force
git rebase ...   # sur branche partagee sans decision explicite
```

La règle reste : état ambigu = STOP + diagnostic, jamais deviner.
