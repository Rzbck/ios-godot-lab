[CmdletBinding()]
param(
    [string]$Repository = 'Rzbck/ios-godot-lab',
    [string]$Workflow = 'watch-sensor-lab-bootstrap.yml',
    [string]$ExpectedBranch = 'feat/watch-sensor-lab-bootstrap-20260909',
    [switch]$SkipGitUpdate,
    [switch]$NoAutoBuild,
    [int]$BuildTimeoutMinutes = 30,
    [switch]$OpenFolder
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Assert-NativeSuccess {
    param([Parameter(Mandatory)][string]$What)
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE"
    }
}

function Get-RepoContainer {
    param([Parameter(Mandatory)][string]$RepoTop)

    $Parent = Split-Path -Parent $RepoTop
    if ((Split-Path -Leaf $Parent) -eq 'worktrees') {
        return (Split-Path -Parent $Parent)
    }
    if ((Split-Path -Leaf $RepoTop) -eq 'main') {
        return $Parent
    }
    return $RepoTop
}

function Get-BranchRuns {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$BranchName
    )

    $Json = & gh run list `
        --repo $RepositoryName `
        --workflow $WorkflowName `
        --branch $BranchName `
        --limit 100 `
        --json databaseId,headSha,conclusion,status,createdAt,event,displayTitle
    Assert-NativeSuccess 'gh run list'

    if ([string]::IsNullOrWhiteSpace(($Json -join ''))) {
        return @()
    }
    return @($Json | ConvertFrom-Json)
}

function Test-RunHasExpectedArtifact {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][Int64]$RunId,
        [Parameter(Mandatory)][string]$BuildSha
    )

    $ArtifactName = "watch-sensor-lab-companion-$BuildSha"
    $Json = & gh api "repos/$RepositoryName/actions/runs/$RunId/artifacts?per_page=100"
    Assert-NativeSuccess "gh api artifacts for run $RunId"

    if ([string]::IsNullOrWhiteSpace(($Json -join ''))) {
        return $false
    }

    $Payload = $Json | ConvertFrom-Json
    $Matches = @($Payload.artifacts | Where-Object {
        [string]$_.name -eq $ArtifactName -and $_.expired -ne $true
    })
    return ($Matches.Count -gt 0)
}

function Wait-ForExactBuild {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$BranchName,
        [Parameter(Mandatory)][string]$HeadSha,
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [switch]$MayTrigger
    )

    $Deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $TriggeredHere = $false

    while ((Get-Date) -lt $Deadline) {
        $Runs = @(Get-BranchRuns `
            -RepositoryName $RepositoryName `
            -WorkflowName $WorkflowName `
            -BranchName $BranchName)

        $ExactRuns = @($Runs |
            Where-Object { [string]$_.headSha -eq $HeadSha } |
            Sort-Object createdAt -Descending)

        $SuccessfulRuns = @($ExactRuns |
            Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' })

        foreach ($Candidate in $SuccessfulRuns) {
            if (Test-RunHasExpectedArtifact `
                -RepositoryName $RepositoryName `
                -RunId ([Int64]$Candidate.databaseId) `
                -BuildSha $HeadSha) {
                return $Candidate
            }
        }

        $Active = $ExactRuns |
            Where-Object { $_.status -in @('queued', 'in_progress', 'pending', 'requested', 'waiting') } |
            Select-Object -First 1

        if ($null -ne $Active) {
            Write-Host ("BUILD       = {0} - {1} - {2}" -f $Active.databaseId, $Active.status, $Active.headSha) -ForegroundColor DarkCyan
            Start-Sleep -Seconds 5
            continue
        }

        $Failed = $ExactRuns |
            Where-Object {
                $_.status -eq 'completed' -and
                $_.conclusion -in @('failure', 'timed_out', 'action_required', 'startup_failure')
            } |
            Select-Object -First 1

        if ($null -ne $Failed -and $TriggeredHere) {
            throw "Exact Watch Sensor Lab build $($Failed.databaseId) finished with conclusion '$($Failed.conclusion)' for SHA $HeadSha."
        }

        if (-not $MayTrigger) {
            throw "No retained device artifact exists for exact branch HEAD $HeadSha."
        }

        if (-not $TriggeredHere) {
            Write-Host 'No retained exact-HEAD device artifact exists. Triggering exact current-HEAD device build...' -ForegroundColor Yellow
            # Capture gh stdout locally. PowerShell functions emit uncaptured stdout as
            # pipeline output; letting the dispatch URL escape here polluted $Run and
            # later caused a missing databaseId property after a successful build.
            $DispatchOutput = & gh workflow run $WorkflowName `
                --repo $RepositoryName `
                --ref $BranchName
            Assert-NativeSuccess 'gh workflow run'
            if ($DispatchOutput) {
                Write-Host ("DISPATCH    = " + (($DispatchOutput | ForEach-Object { [string]$_ }) -join ' ')) -ForegroundColor DarkGray
            }
            $TriggeredHere = $true
            Start-Sleep -Seconds 3
            continue
        }

        Write-Host 'Waiting for GitHub Actions to register the exact-HEAD device-artifact run...' -ForegroundColor DarkCyan
        Start-Sleep -Seconds 5
    }

    throw "Timed out after $TimeoutMinutes minute(s) waiting for exact Watch Sensor Lab artifact at HEAD $HeadSha."
}

function Test-ArtifactDirectory {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$ExpectedSha
    )

    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }

    $IpaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa' -File -ErrorAction SilentlyContinue)
    $HashFiles = @(Get-ChildItem -LiteralPath $Directory -Filter '*.ipa.sha256' -File -ErrorAction SilentlyContinue)
    $MetaFiles = @(Get-ChildItem -LiteralPath $Directory -Filter 'BUILD-METADATA.json' -File -ErrorAction SilentlyContinue)

    if ($IpaFiles.Count -ne 1 -or $HashFiles.Count -ne 1 -or $MetaFiles.Count -ne 1) {
        return $false
    }

    try {
        $ExpectedLine = (Get-Content -LiteralPath $HashFiles[0].FullName -TotalCount 1).Trim()
        if ($ExpectedLine -notmatch '^([0-9a-fA-F]{64})\b') {
            return $false
        }

        $ExpectedHash = $Matches[1].ToLowerInvariant()
        $ActualHash = (Get-FileHash -LiteralPath $IpaFiles[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ExpectedHash -ne $ActualHash) {
            return $false
        }

        $Metadata = Get-Content -LiteralPath $MetaFiles[0].FullName -Raw | ConvertFrom-Json
        if ([string]$Metadata.sha -ne $ExpectedSha) {
            return $false
        }
        if ($Metadata.watch_companion_integrated_in_ipa -ne $true) {
            return $false
        }
    }
    catch {
        return $false
    }

    return $true
}

Write-Host "`n=== WATCH SENSOR LAB - EXACT COMPANION IPA SYNC ===" -ForegroundColor Cyan

if ($BuildTimeoutMinutes -lt 1 -or $BuildTimeoutMinutes -gt 120) {
    throw 'BuildTimeoutMinutes must be between 1 and 120.'
}
if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git not found in PATH.'
}
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw 'GitHub CLI (gh) not found in PATH.'
}

$RepoTop = (& git rev-parse --show-toplevel).Trim()
Assert-NativeSuccess 'git rev-parse --show-toplevel'

$Branch = (& git branch --show-current).Trim()
Assert-NativeSuccess 'git branch --show-current'
if ([string]::IsNullOrWhiteSpace($Branch)) {
    throw 'Detached HEAD detected. Run this script from the Watch Sensor Lab worktree.'
}
if ($Branch -ne $ExpectedBranch) {
    throw "STOP: expected branch '$ExpectedBranch', current branch is '$Branch'."
}

$HeadBefore = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'
$Remote = (& git remote get-url origin).Trim()
Assert-NativeSuccess 'git remote get-url origin'
if ($Remote -notmatch 'Rzbck/ios-godot-lab(?:\.git)?$') {
    throw "Unexpected origin remote: $Remote"
}

$Status = @(git status --porcelain)
Assert-NativeSuccess 'git status --porcelain'

Write-Host "REPO        = $RepoTop"
Write-Host "BRANCH      = $Branch"
Write-Host "HEAD BEFORE = $HeadBefore"
Write-Host "ORIGIN      = $Remote"
Write-Host ("STATE       = " + ($(if ($Status.Count -eq 0) { 'CLEAN' } else { 'DIRTY' })))

if ($Status.Count -ne 0) {
    $Status | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    throw 'STOP: worktree is DIRTY. Nothing was updated or downloaded.'
}

& gh auth status --hostname github.com *> $null
Assert-NativeSuccess 'gh auth status'

if (-not $SkipGitUpdate) {
    Write-Host "`nFetching origin..." -ForegroundColor DarkCyan
    & git fetch origin --prune
    Assert-NativeSuccess 'git fetch origin --prune'

    & git show-ref --verify --quiet "refs/remotes/origin/$Branch"
    if ($LASTEXITCODE -ne 0) {
        throw "No matching remote branch origin/$Branch."
    }

    Write-Host 'Fast-forwarding current Watch Sensor Lab branch only...' -ForegroundColor DarkCyan
    & git merge --ff-only "origin/$Branch"
    Assert-NativeSuccess 'git merge --ff-only'
}

$Head = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'
Write-Host "HEAD AFTER  = $Head" -ForegroundColor Green

Write-Host "`nResolving retained companion artifact for exact HEAD only..." -ForegroundColor DarkCyan
$Run = Wait-ForExactBuild `
    -RepositoryName $Repository `
    -WorkflowName $Workflow `
    -BranchName $Branch `
    -HeadSha $Head `
    -TimeoutMinutes $BuildTimeoutMinutes `
    -MayTrigger:(-not $NoAutoBuild)

$RunId = [Int64]$Run.databaseId
$BuildSha = [string]$Run.headSha
if ($BuildSha -ne $Head) {
    throw "STOP: exact-SHA invariant violated. HEAD=$Head BUILD=$BuildSha"
}

Write-Host "BUILD SHA   = $BuildSha" -ForegroundColor Green

$ArtifactName = "watch-sensor-lab-companion-$BuildSha"
$ShortSha = $BuildSha.Substring(0, 12)
$RepoContainer = Get-RepoContainer -RepoTop $RepoTop
$ArtifactRoot = Join-Path (Join-Path $RepoContainer 'artifacts') 'watch-sensor-lab'
$FinalDir = Join-Path $ArtifactRoot $ShortSha
New-Item -ItemType Directory -Force -Path $ArtifactRoot | Out-Null

if (Test-ArtifactDirectory -Directory $FinalDir -ExpectedSha $BuildSha) {
    Write-Host "`nExact-HEAD companion artifact already present and hash-verified." -ForegroundColor Green
}
else {
    if (Test-Path -LiteralPath $FinalDir) {
        throw "Artifact directory exists but is incomplete or invalid: $FinalDir`nInspect it manually; this updater will not overwrite it."
    }

    $TempDir = Join-Path $ArtifactRoot ('.tmp-' + $ShortSha + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $TempDir | Out-Null

    try {
        Write-Host "`nDownloading exact-HEAD retained companion artifact..." -ForegroundColor DarkCyan
        Write-Host "RUN         = $RunId"
        Write-Host "ARTIFACT    = $ArtifactName"

        & gh run download $RunId `
            --repo $Repository `
            --name $ArtifactName `
            --dir $TempDir
        Assert-NativeSuccess 'gh run download'

        if (-not (Test-ArtifactDirectory -Directory $TempDir -ExpectedSha $BuildSha)) {
            throw 'Downloaded artifact failed exact build-SHA, metadata, companion or SHA-256 validation.'
        }

        Move-Item -LiteralPath $TempDir -Destination $FinalDir
    }
    catch {
        if (Test-Path -LiteralPath $TempDir) {
            Remove-Item -LiteralPath $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

$Ipa = @(Get-ChildItem -LiteralPath $FinalDir -Filter '*.ipa' -File)
if ($Ipa.Count -ne 1) {
    throw "Final artifact folder does not contain exactly one IPA: $FinalDir"
}

$IpaHash = (Get-FileHash -LiteralPath $Ipa[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$Latest = [ordered]@{
    repository = $Repository
    branch = $Branch
    branch_head_sha = $Head
    git_sha = $BuildSha
    build_sha = $BuildSha
    exact_head = $true
    workflow_run = $RunId
    workflow_event = [string]$Run.event
    artifact = $ArtifactName
    ipa = $Ipa[0].FullName
    ipa_sha256 = $IpaHash
    synced_at = (Get-Date).ToString('o')
}

$LatestJson = Join-Path $ArtifactRoot 'LATEST.json'
$LatestTxt = Join-Path $ArtifactRoot 'LATEST_IPA.txt'
$Latest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $LatestJson -Encoding UTF8
$Ipa[0].FullName | Set-Content -LiteralPath $LatestTxt -Encoding UTF8

Write-Host "`n=== READY FOR ILOADER TEST ===" -ForegroundColor Green
Write-Host "HEAD        = $Head"
Write-Host "BUILD SHA   = $BuildSha"
Write-Host "RUN         = $RunId"
Write-Host "IPA         = $($Ipa[0].FullName)"
Write-Host "SHA-256     = $IpaHash"
Write-Host "LATEST JSON = $LatestJson"
Write-Host 'WATCH       = embedded in IPA; hardware installation is NOT validated yet' -ForegroundColor Yellow

if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList "/select,`"$($Ipa[0].FullName)`""
}
