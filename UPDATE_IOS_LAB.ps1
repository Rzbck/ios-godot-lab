[CmdletBinding()]
param(
    [string]$Repository = 'Rzbck/ios-godot-lab',
    [string]$Workflow = 'build-ios-unsigned.yml',
    [switch]$SkipGitUpdate,
    [switch]$NoAutoBuild,
    [int]$BuildTimeoutMinutes = 30,
    [ValidateRange(0, 50)]
    [int]$KeepLocalArtifacts = 2,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

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

function Get-ExactIosRuns {
    param(
        [string]$RepositoryName,
        [string]$WorkflowName,
        [string]$BranchName,
        [string]$CommitSha
    )

    $json = & gh run list `
        --repo $RepositoryName `
        --workflow $WorkflowName `
        --branch $BranchName `
        --commit $CommitSha `
        --limit 20 `
        --json databaseId,headSha,conclusion,status,createdAt,event,displayTitle
    Assert-NativeSuccess 'gh run list'

    if ([string]::IsNullOrWhiteSpace(($json -join ''))) {
        return @()
    }

    return @($json | ConvertFrom-Json)
}

function Wait-ForExactIosBuild {
    param(
        [string]$RepositoryName,
        [string]$WorkflowName,
        [string]$BranchName,
        [string]$CommitSha,
        [int]$TimeoutMinutes,
        [switch]$MayTrigger
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $triggeredHere = $false

    while ((Get-Date) -lt $deadline) {
        $runs = @(Get-ExactIosRuns `
            -RepositoryName $RepositoryName `
            -WorkflowName $WorkflowName `
            -BranchName $BranchName `
            -CommitSha $CommitSha)

        $exactRuns = @($runs |
            Where-Object { $_.headSha -eq $CommitSha } |
            Sort-Object createdAt -Descending)

        $success = $exactRuns |
            Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' } |
            Select-Object -First 1

        if ($null -ne $success) {
            return $success
        }

        $failed = $exactRuns |
            Where-Object {
                $_.status -eq 'completed' -and
                $_.conclusion -in @('failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure')
            } |
            Select-Object -First 1

        if ($null -ne $failed) {
            throw "Exact iOS build $($failed.databaseId) finished with conclusion '$($failed.conclusion)' for SHA $CommitSha."
        }

        $active = $exactRuns |
            Where-Object { $_.status -in @('queued', 'in_progress', 'pending', 'requested', 'waiting') } |
            Select-Object -First 1

        if ($null -ne $active) {
            Write-Host ("BUILD       = {0} · {1}" -f $active.databaseId, $active.status) -ForegroundColor DarkCyan
            Start-Sleep -Seconds 5
            continue
        }

        if (-not $MayTrigger) {
            throw "No successful iOS build exists for exact SHA $CommitSha. Re-run without -NoAutoBuild to trigger it automatically."
        }

        if (-not $triggeredHere) {
            Write-Host "No exact-SHA build exists yet. Triggering GitHub Actions..." -ForegroundColor Yellow
            & gh workflow run $WorkflowName `
                --repo $RepositoryName `
                --ref $BranchName
            Assert-NativeSuccess 'gh workflow run'
            $triggeredHere = $true
            Start-Sleep -Seconds 3
            continue
        }

        Write-Host 'Waiting for GitHub Actions to register the dispatched run...' -ForegroundColor DarkCyan
        Start-Sleep -Seconds 5
    }

    throw "Timed out after $TimeoutMinutes minute(s) waiting for an iOS build for exact SHA $CommitSha."
}

function Test-ArtifactDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ExpectedSha
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }

    $ipaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa' -File -ErrorAction SilentlyContinue)
    $hashFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa.sha256' -File -ErrorAction SilentlyContinue)
    $metaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'BUILD-METADATA.json' -File -ErrorAction SilentlyContinue)

    if ($ipaFiles.Count -ne 1 -or $hashFiles.Count -ne 1 -or $metaFiles.Count -ne 1) {
        return $false
    }

    try {
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
        if ([string]$metadata.sha -ne $ExpectedSha) {
            return $false
        }
    }
    catch {
        return $false
    }

    return $true
}

function Get-VerifiedBranchArtifactRecords {
    param(
        [Parameter(Mandatory)][string]$ArtifactRoot,
        [Parameter(Mandatory)][string]$BranchName
    )

    if (-not (Test-Path -LiteralPath $ArtifactRoot -PathType Container)) {
        return @()
    }

    $branchRef = "refs/heads/$BranchName"
    $records = @()

    foreach ($directory in @(Get-ChildItem -LiteralPath $ArtifactRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($directory.Name -notmatch '^[0-9a-fA-F]{12}$') {
            continue
        }

        $metaFile = Join-Path $directory.FullName 'BUILD-METADATA.json'
        if (-not (Test-Path -LiteralPath $metaFile -PathType Leaf)) {
            continue
        }

        try {
            $metadata = Get-Content -LiteralPath $metaFile -Raw | ConvertFrom-Json
            $sha = [string]$metadata.sha
            $ref = [string]$metadata.ref

            if ($ref -ne $branchRef) {
                continue
            }
            if ($sha -notmatch '^[0-9a-fA-F]{40}$') {
                continue
            }
            if ($sha.Substring(0, 12) -ine $directory.Name) {
                continue
            }
            if (-not (Test-ArtifactDirectory -Directory $directory.FullName -ExpectedSha $sha)) {
                continue
            }

            $records += [pscustomobject]@{
                Directory = $directory.FullName
                Sha = $sha
                LastWriteTimeUtc = $directory.LastWriteTimeUtc
            }
        }
        catch {
            continue
        }
    }

    return @($records)
}

function Prune-OldBranchArtifacts {
    param(
        [Parameter(Mandatory)][string]$ArtifactRoot,
        [Parameter(Mandatory)][string]$BranchName,
        [Parameter(Mandatory)][string]$CurrentDirectory,
        [Parameter(Mandatory)][int]$KeepCount
    )

    if ($KeepCount -le 0) {
        Write-Host 'LOCAL CACHE = pruning disabled' -ForegroundColor DarkGray
        return
    }

    $records = @(Get-VerifiedBranchArtifactRecords -ArtifactRoot $ArtifactRoot -BranchName $BranchName)
    if ($records.Count -le $KeepCount) {
        Write-Host ("LOCAL CACHE = {0}/{1} verified artifact(s) for branch" -f $records.Count, $KeepCount) -ForegroundColor DarkGray
        return
    }

    $currentFull = [System.IO.Path]::GetFullPath($CurrentDirectory).TrimEnd('\', '/')
    $keep = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    [void]$keep.Add($currentFull)

    $otherRecords = @($records |
        Where-Object { [System.IO.Path]::GetFullPath($_.Directory).TrimEnd('\', '/') -ne $currentFull } |
        Sort-Object LastWriteTimeUtc -Descending)

    $slots = [Math]::Max($KeepCount - 1, 0)
    foreach ($record in @($otherRecords | Select-Object -First $slots)) {
        [void]$keep.Add([System.IO.Path]::GetFullPath($record.Directory).TrimEnd('\', '/'))
    }

    foreach ($record in $records) {
        $full = [System.IO.Path]::GetFullPath($record.Directory).TrimEnd('\', '/')
        if ($keep.Contains($full)) {
            continue
        }

        Write-Host "PRUNE       = $($record.Directory)" -ForegroundColor DarkYellow
        Remove-Item -LiteralPath $record.Directory -Recurse -Force
    }

    $remaining = @(Get-VerifiedBranchArtifactRecords -ArtifactRoot $ArtifactRoot -BranchName $BranchName)
    Write-Host ("LOCAL CACHE = {0}/{1} verified artifact(s) kept for branch" -f $remaining.Count, $KeepCount) -ForegroundColor Green
}

Write-Host "`n=== IOS LAB UPDATE + EXACT IPA SYNC ===" -ForegroundColor Cyan

if ($BuildTimeoutMinutes -lt 1 -or $BuildTimeoutMinutes -gt 120) {
    throw 'BuildTimeoutMinutes must be between 1 and 120.'
}

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

Write-Host "`nResolving iOS build for this exact SHA..." -ForegroundColor DarkCyan
$run = Wait-ForExactIosBuild `
    -RepositoryName $Repository `
    -WorkflowName $Workflow `
    -BranchName $branch `
    -CommitSha $head `
    -TimeoutMinutes $BuildTimeoutMinutes `
    -MayTrigger:(-not $NoAutoBuild)

$runId = [int64]$run.databaseId
$artifactName = "ios-unsigned-$head"
$shortSha = $head.Substring(0, 12)
$repoContainer = Get-RepoContainer -RepoTop $repoTop
$artifactRoot = Join-Path $repoContainer 'artifacts'
$finalDir = Join-Path $artifactRoot $shortSha

New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

if (Test-ArtifactDirectory -Directory $finalDir -ExpectedSha $head) {
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
    keep_local_artifacts = $KeepLocalArtifacts
}

$latestJson = Join-Path $artifactRoot 'LATEST.json'
$latestTxt = Join-Path $artifactRoot 'LATEST_IPA.txt'
$latest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $latestJson -Encoding UTF8
$ipa[0].FullName | Set-Content -LiteralPath $latestTxt -Encoding UTF8

Prune-OldBranchArtifacts `
    -ArtifactRoot $artifactRoot `
    -BranchName $branch `
    -CurrentDirectory $finalDir `
    -KeepCount $KeepLocalArtifacts

Write-Host "`n=== READY FOR ILOADER ===" -ForegroundColor Green
Write-Host "SHA         = $head"
Write-Host "RUN         = $runId"
Write-Host "IPA         = $($ipa[0].FullName)"
Write-Host "SHA-256     = $ipaHash"
Write-Host "LOCAL KEEP  = $KeepLocalArtifacts verified artifact(s) for this branch"
Write-Host "LATEST JSON = $latestJson"

if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList "/select,`"$($ipa[0].FullName)`""
}
