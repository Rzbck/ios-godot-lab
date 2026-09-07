# PowerShell — règles pratiques de travail local

Objectif : éviter les erreurs de branche/worktree et les `else` implicites.

## Préflight obligatoire

Depuis le repo/worktree concerné :

```powershell
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
```

## Synchronisation sûre

```powershell
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
