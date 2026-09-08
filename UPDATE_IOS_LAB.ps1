[CmdletBinding()]
param(
    [string]$Repository = 'Rzbck/ios-godot-lab',
    [string]$Workflow = 'build-ios-unsigned.yml',
    [switch]$SkipGitUpdate,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NativeSuccess {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE"
    }
}

function Get-RepoContainer {
    param([string]$RepoTop)

    $parent = Split-Path -Parent $RepoTop
    $leaf = Split-Path -Leaf $RepoTop
    $parentLeaf = Split-Path -Leaf $parent

    if ($parentLeaf -eq 'worktrees') {
        return (Split-Path -Parent $parent)
    }

    if ($leaf -eq 'main') {
        return $parent
    }

    return $RepoTop
}

Write-Host "`n=== IOS LAB UPDATE + EXACT IPA SYNC ===" -ForegroundColor Cyan

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    throw 'git not found in PATH.'
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($null -eq $gh) {
    throw 'GitHub CLI (gh) not found in PATH.'
}

$repoTop = (& git rev-parse --show-toplevel).Trim()
Assert-NativeSuccess 'git rev-parse --show-toplevel'

$branch = (& git branch --show-current).Trim()
Assert-NativeSuccess 'git branch --show-current'
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Detached HEAD detected. Run this updater from a named worktree branch.'
}

$headBefore = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'

$remote = (& git remote get-url origin).Trim()
Assert-NativeSuccess 'git remote get-url origin'
if ($remote -notmatch 'Rzbck/ios-godot-lab(?:\.git)?$') {
    throw "Unexpected origin remote: $remote"
}

$status = @(git status --porcelain)
Assert-NativeSuccess 'git status --porcelain'

Write-Host "REPO        = $repoTop"
Write-Host "BRANCH      = $branch"
Write-Host "HEAD BEFORE = $headBefore"
Write-Host "ORIGIN      = $remote"
Write-Host ("STATE       = " + ($(if ($status.Count -eq 0) { 'CLEAN' } else { 'DIRTY' })))

if ($status.Count -ne 0) {
    $status | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    throw 'STOP: worktree is DIRTY. Nothing was updated or downloaded.'
}

& gh auth status --hostname github.com *> $null
Assert-NativeSuccess 'gh auth status'

if (-not $SkipGitUpdate) {
    Write-Host "`nFetching origin..." -ForegroundColor DarkCyan
    & git fetch origin --prune
    Assert-NativeSuccess 'git fetch origin --prune'

    & git show-ref --verify --quiet "refs/remotes/origin/$branch"
    if ($LASTEXITCODE -ne 0) {
        throw "No matching remote branch origin/$branch."
    }

    Write-Host "Fast-forwarding current branch only..." -ForegroundColor DarkCyan
    & git merge --ff-only "origin/$branch"
    Assert-NativeSuccess 'git merge --ff-only'
}

$head = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'

Write-Host "HEAD AFTER  = $head" -ForegroundColor Green

Write-Host "`nLocating a successful iOS workflow for this exact SHA..." -ForegroundColor DarkCyan
$runJson = & gh run list `
    --repo $Repository `
    --workflow $Workflow `
    --branch $branch `
    --commit $head `
    --status success `
    --limit 20 `
    --json databaseId,headSha,conclusion,status,createdAt
Assert-NativeSuccess 'gh run list'

$runs = @($runJson | ConvertFrom-Json)
$run = $runs |
    Where-Object { $_.headSha -eq $head -and $_.conclusion -eq 'success' } |
    Sort-Object createdAt -Descending |
    Select-Object -First 1

if ($null -eq $run) {
    throw "No successful iOS build exists for exact SHA $head on branch $branch."
}

$runId = [int64]$run.databaseId
$artifactName = "ios-unsigned-$head"
$shortSha = $head.Substring(0, 12)
$repoContainer = Get-RepoContainer -RepoTop $repoTop
$artifactRoot = Join-Path $repoContainer 'artifacts'
$finalDir = Join-Path $artifactRoot $shortSha

New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

function Test-ExistingArtifact {
    param([string]$Directory)

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }

    $ipaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa' -File -ErrorAction SilentlyContinue)
    $hashFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa.sha256' -File -ErrorAction SilentlyContinue)
    $metaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'BUILD-METADATA.json' -File -ErrorAction SilentlyContinue)

    if ($ipaFiles.Count -ne 1 -or $hashFiles.Count -ne 1 -or $metaFiles.Count -ne 1) {
        return $false
    }

    $expectedLine = (Get-Content -LiteralPath $hashFiles[0].FullName -TotalCount 1).Trim()
    if ($expectedLine -notmatch '^([0-9a-fA-F]{64})\b') {
        return $false
    }

    $expectedHash = $Matches[1].ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $ipaFiles[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expectedHash -ne $actualHash) {
        return $false
    }

    $metadata = Get-Content -LiteralPath $metaFiles[0].FullName -Raw | ConvertFrom-Json
    if ([string]$metadata.sha -ne $head) {
        return $false
    }

    return $true
}

if (Test-ExistingArtifact -Directory $finalDir) {
    Write-Host "`nExact artifact already present and hash-verified." -ForegroundColor Green
}
else {
    if (Test-Path -LiteralPath $finalDir) {
        throw "Artifact directory already exists but is incomplete or invalid: $finalDir`nInspect it manually; updater will not overwrite it."
    }

    $tempDir = Join-Path $artifactRoot ('.tmp-' + $shortSha + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Write-Host "`nDownloading exact artifact from GitHub Actions..." -ForegroundColor DarkCyan
        Write-Host "RUN         = $runId"
        Write-Host "ARTIFACT    = $artifactName"

        & gh run download $runId `
            --repo $Repository `
            --name $artifactName `
            --dir $tempDir
        Assert-NativeSuccess 'gh run download'

        $ipaFiles = @(Get-ChildItem -LiteralPath $tempDir -Filter '*.ipa' -File)
        $hashFiles = @(Get-ChildItem -LiteralPath $tempDir -Filter '*.ipa.sha256' -File)
        $metaFiles = @(Get-ChildItem -LiteralPath $tempDir -Filter 'BUILD-METADATA.json' -File)

        if ($ipaFiles.Count -ne 1) {
            throw "Expected exactly one IPA in artifact, found $($ipaFiles.Count)."
        }
        if ($hashFiles.Count -ne 1) {
            throw "Expected exactly one IPA SHA-256 file, found $($hashFiles.Count)."
        }
        if ($metaFiles.Count -ne 1) {
            throw "Expected BUILD-METADATA.json, found $($metaFiles.Count)."
        }

        $expectedLine = (Get-Content -LiteralPath $hashFiles[0].FullName -TotalCount 1).Trim()
        if ($expectedLine -notmatch '^([0-9a-fA-F]{64})\b') {
            throw "Could not parse expected SHA-256 from $($hashFiles[0].Name)."
        }
        $expectedHash = $Matches[1].ToLowerInvariant()
        $actualHash = (Get-FileHash -LiteralPath $ipaFiles[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($actualHash -ne $expectedHash) {
            throw "IPA SHA-256 mismatch. Expected $expectedHash, got $actualHash."
        }

        $metadata = Get-Content -LiteralPath $metaFiles[0].FullName -Raw | ConvertFrom-Json
        if ([string]$metadata.sha -ne $head) {
            throw "BUILD-METADATA SHA mismatch. Expected $head, got $($metadata.sha)."
        }

        Move-Item -LiteralPath $tempDir -Destination $finalDir
    }
    catch {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

$ipa = @(Get-ChildItem -LiteralPath $finalDir -Filter '*.ipa' -File)
if ($ipa.Count -ne 1) {
    throw "Final artifact folder does not contain exactly one IPA: $finalDir"
}

$ipaHash = (Get-FileHash -LiteralPath $ipa[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$latest = [ordered]@{
    repository = $Repository
    branch = $branch
    git_sha = $head
    short_sha = $shortSha
    workflow_run = $runId
    artifact = $artifactName
    ipa = $ipa[0].FullName
    ipa_sha256 = $ipaHash
    synced_at = (Get-Date).ToString('o')
}

$latestJson = Join-Path $artifactRoot 'LATEST.json'
$latestTxt = Join-Path $artifactRoot 'LATEST_IPA.txt'
$latest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $latestJson -Encoding UTF8
$ipa[0].FullName | Set-Content -LiteralPath $latestTxt -Encoding UTF8

Write-Host "`n=== READY FOR ILOADER ===" -ForegroundColor Green
Write-Host "SHA         = $head"
Write-Host "RUN         = $runId"
Write-Host "IPA         = $($ipa[0].FullName)"
Write-Host "SHA-256     = $ipaHash"
Write-Host "LATEST JSON = $latestJson"

if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList "/select,`"$($ipa[0].FullName)`""
}
