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

$BuildRelevantPaths = @(
    'apps/watch-sensor-lab/iphone',
    'apps/watch-sensor-lab/watch',
    'apps/watch-sensor-lab/Shared',
    'apps/watch-sensor-lab/godot',
    'apps/watch-sensor-lab/GENERATE_APP_ICON.py',
    '.github/workflows/watch-sensor-lab-bootstrap.yml'
)

function Assert-NativeSuccess {
    param([Parameter(Mandatory)][string]$What)
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed with exit code $LASTEXITCODE"
    }
}

function Get-RepoContainer {
    param([Parameter(Mandatory)][string]$RepoTop)

    $parent = Split-Path -Parent $RepoTop
    if ((Split-Path -Leaf $parent) -eq 'worktrees') {
        return (Split-Path -Parent $parent)
    }

    if ((Split-Path -Leaf $RepoTop) -eq 'main') {
        return $parent
    }

    return $RepoTop
}

function Get-BranchRuns {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$BranchName
    )

    $json = & gh run list `
        --repo $RepositoryName `
        --workflow $WorkflowName `
        --branch $BranchName `
        --limit 100 `
        --json databaseId,headSha,conclusion,status,createdAt,event,displayTitle
    Assert-NativeSuccess 'gh run list'

    if ([string]::IsNullOrWhiteSpace(($json -join ''))) {
        return @()
    }

    return @($json | ConvertFrom-Json)
}

function Test-RunHasExpectedArtifact {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][Int64]$RunId,
        [Parameter(Mandatory)][string]$BuildSha
    )

    $artifactName = "watch-sensor-lab-companion-$BuildSha"
    $json = & gh api "repos/$RepositoryName/actions/runs/$RunId/artifacts?per_page=100"
    Assert-NativeSuccess "gh api artifacts for run $RunId"

    if ([string]::IsNullOrWhiteSpace(($json -join ''))) {
        return $false
    }

    $payload = $json | ConvertFrom-Json
    $matches = @($payload.artifacts | Where-Object {
        [string]$_.name -eq $artifactName -and $_.expired -ne $true
    })
    return ($matches.Count -gt 0)
}

function Test-CommitAvailable {
    param([Parameter(Mandatory)][string]$CommitSha)

    & git cat-file -e "$CommitSha^{commit}" 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Test-CommitIsAncestor {
    param(
        [Parameter(Mandatory)][string]$CandidateSha,
        [Parameter(Mandatory)][string]$HeadSha
    )

    if (-not (Test-CommitAvailable -CommitSha $CandidateSha)) {
        return $false
    }

    & git merge-base --is-ancestor $CandidateSha $HeadSha
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw "git merge-base failed while checking candidate build SHA $CandidateSha."
}

function Test-BuildInputsEquivalent {
    param(
        [Parameter(Mandatory)][string]$CandidateSha,
        [Parameter(Mandatory)][string]$HeadSha,
        [Parameter(Mandatory)][string[]]$RelevantPaths
    )

    if ($CandidateSha -eq $HeadSha) {
        return $true
    }

    if (-not (Test-CommitIsAncestor -CandidateSha $CandidateSha -HeadSha $HeadSha)) {
        return $false
    }

    $args = @('diff', '--quiet', "$CandidateSha..$HeadSha", '--') + $RelevantPaths
    & git @args
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw "git diff failed while checking build inputs between $CandidateSha and $HeadSha."
}

function Wait-ForCompatibleBuild {
    param(
        [Parameter(Mandatory)][string]$RepositoryName,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$BranchName,
        [Parameter(Mandatory)][string]$HeadSha,
        [Parameter(Mandatory)][string[]]$RelevantPaths,
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [switch]$MayTrigger
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $triggeredHere = $false

    while ((Get-Date) -lt $deadline) {
        $runs = @(Get-BranchRuns `
            -RepositoryName $RepositoryName `
            -WorkflowName $WorkflowName `
            -BranchName $BranchName)

        $compatible = @()
        foreach ($candidate in ($runs | Sort-Object createdAt -Descending)) {
            if ([string]::IsNullOrWhiteSpace([string]$candidate.headSha)) { continue }
            if (Test-BuildInputsEquivalent `
                -CandidateSha ([string]$candidate.headSha) `
                -HeadSha $HeadSha `
                -RelevantPaths $RelevantPaths) {
                $compatible += $candidate
            }
        }

        $success = $null
        $successfulRuns = @($compatible |
            Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' } |
            Select-Object -First 12)

        foreach ($candidate in $successfulRuns) {
            if (Test-RunHasExpectedArtifact `
                -RepositoryName $RepositoryName `
                -RunId ([Int64]$candidate.databaseId) `
                -BuildSha ([string]$candidate.headSha)) {
                $success = $candidate
                break
            }
        }

        if ($null -ne $success) {
            return [pscustomobject]@{
                Run = $success
                BuildSha = [string]$success.headSha
            }
        }

        $failed = $compatible |
            Where-Object {
                $_.status -eq 'completed' -and
                $_.conclusion -in @('failure', 'timed_out', 'action_required', 'startup_failure')
            } |
            Select-Object -First 1

        if ($null -ne $failed) {
            throw "Compatible Watch Sensor Lab build $($failed.databaseId) finished with conclusion '$($failed.conclusion)' for SHA $($failed.headSha)."
        }

        $active = $compatible |
            Where-Object { $_.status -in @('queued', 'in_progress', 'pending', 'requested', 'waiting') } |
            Select-Object -First 1

        if ($null -ne $active) {
            Write-Host ("BUILD       = {0} - {1} - {2}" -f $active.databaseId, $active.status, $active.headSha) -ForegroundColor DarkCyan
            Start-Sleep -Seconds 5
            continue
        }

        if (-not $MayTrigger) {
            throw "No retained device artifact exists whose build inputs exactly match branch HEAD $HeadSha."
        }

        if (-not $triggeredHere) {
            Write-Host 'No retained compatible device artifact exists. Triggering exact current-HEAD device build...' -ForegroundColor Yellow
            & gh workflow run $WorkflowName `
                --repo $RepositoryName `
                --ref $BranchName
            Assert-NativeSuccess 'gh workflow run'
            $triggeredHere = $true
            Start-Sleep -Seconds 3
            continue
        }

        Write-Host 'Waiting for GitHub Actions to register the dispatched device-artifact run...' -ForegroundColor DarkCyan
        Start-Sleep -Seconds 5
    }

    throw "Timed out after $TimeoutMinutes minute(s) waiting for a retained Watch Sensor Lab artifact compatible with HEAD $HeadSha."
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
        if ($metadata.watch_companion_integrated_in_ipa -ne $true) {
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

$repoTop = (& git rev-parse --show-toplevel).Trim()
Assert-NativeSuccess 'git rev-parse --show-toplevel'

$branch = (& git branch --show-current).Trim()
Assert-NativeSuccess 'git branch --show-current'
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Detached HEAD detected. Run this script from the Watch Sensor Lab worktree.'
}
if ($branch -ne $ExpectedBranch) {
    throw "STOP: expected branch '$ExpectedBranch', current branch is '$branch'."
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

    Write-Host 'Fast-forwarding current Watch Sensor Lab branch only...' -ForegroundColor DarkCyan
    & git merge --ff-only "origin/$branch"
    Assert-NativeSuccess 'git merge --ff-only'
}

$head = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'
Write-Host "HEAD AFTER  = $head" -ForegroundColor Green

Write-Host "`nResolving retained companion artifact with identical build inputs..." -ForegroundColor DarkCyan
$resolverOutput = @(
    Wait-ForCompatibleBuild `
        -RepositoryName $Repository `
        -WorkflowName $Workflow `
        -BranchName $branch `
        -HeadSha $head `
        -RelevantPaths $BuildRelevantPaths `
        -TimeoutMinutes $BuildTimeoutMinutes `
        -MayTrigger:(-not $NoAutoBuild)
)

$resolved = @(
    $resolverOutput | Where-Object {
        $null -ne $_ -and
        $null -ne $_.PSObject.Properties['Run'] -and
        $null -ne $_.PSObject.Properties['BuildSha']
    }
) | Select-Object -Last 1

if ($null -ne $resolved) {
    $run = $resolved.Run
    $buildSha = [string]$resolved.BuildSha
}
else {
    $run = @(
        $resolverOutput | Where-Object {
            $null -ne $_ -and
            $null -ne $_.PSObject.Properties['databaseId'] -and
            $null -ne $_.PSObject.Properties['headSha']
        }
    ) | Select-Object -Last 1

    if ($null -eq $run) {
        $types = @(
            $resolverOutput | ForEach-Object {
                if ($null -eq $_) { '<null>' }
                else { $_.GetType().FullName }
            }
        ) -join ', '

        throw "Compatible build resolver returned no usable run object. Output types: $types"
    }

    $buildSha = [string]$run.headSha
}

$runId = [int64]$run.databaseId

if ($buildSha -ne $head) {
    Write-Host "BRANCH HEAD = $head" -ForegroundColor DarkGray
    Write-Host "BUILD SHA   = $buildSha" -ForegroundColor Green
    Write-Host 'BUILD INPUTS= identical; intervening commits do not affect the packaged app' -ForegroundColor Green
}
else {
    Write-Host "BUILD SHA   = $buildSha" -ForegroundColor Green
}

$artifactName = "watch-sensor-lab-companion-$buildSha"
$shortSha = $buildSha.Substring(0, 12)
$repoContainer = Get-RepoContainer -RepoTop $repoTop
$artifactRoot = Join-Path (Join-Path $repoContainer 'artifacts') 'watch-sensor-lab'
$finalDir = Join-Path $artifactRoot $shortSha

New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

if (Test-ArtifactDirectory -Directory $finalDir -ExpectedSha $buildSha) {
    Write-Host "`nCompatible exact companion artifact already present and hash-verified." -ForegroundColor Green
}
else {
    if (Test-Path -LiteralPath $finalDir) {
        throw "Artifact directory exists but is incomplete or invalid: $finalDir`nInspect it manually; this updater will not overwrite it."
    }

    $tempDir = Join-Path $artifactRoot ('.tmp-' + $shortSha + '-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Write-Host "`nDownloading exact retained companion artifact..." -ForegroundColor DarkCyan
        Write-Host "RUN         = $runId"
        Write-Host "ARTIFACT    = $artifactName"

        & gh run download $runId `
            --repo $Repository `
            --name $artifactName `
            --dir $tempDir
        Assert-NativeSuccess 'gh run download'

        if (-not (Test-ArtifactDirectory -Directory $tempDir -ExpectedSha $buildSha)) {
            throw 'Downloaded artifact failed exact build-SHA, metadata, companion or SHA-256 validation.'
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
    branch_head_sha = $head
    git_sha = $buildSha
    build_sha = $buildSha
    build_inputs_match_branch_head = $true
    workflow_run = $runId
    workflow_event = [string]$run.event
    artifact = $artifactName
    ipa = $ipa[0].FullName
    ipa_sha256 = $ipaHash
    synced_at = (Get-Date).ToString('o')
}

$latestJson = Join-Path $artifactRoot 'LATEST.json'
$latestTxt = Join-Path $artifactRoot 'LATEST_IPA.txt'
$latest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $latestJson -Encoding UTF8
$ipa[0].FullName | Set-Content -LiteralPath $latestTxt -Encoding UTF8

Write-Host "`n=== READY FOR ILOADER TEST ===" -ForegroundColor Green
Write-Host "HEAD        = $head"
Write-Host "BUILD SHA   = $buildSha"
Write-Host "RUN         = $runId"
Write-Host "IPA         = $($ipa[0].FullName)"
Write-Host "SHA-256     = $ipaHash"
Write-Host "LATEST JSON = $latestJson"
Write-Host 'WATCH       = embedded in IPA; hardware installation is NOT validated yet' -ForegroundColor Yellow

if ($OpenFolder) {
    Start-Process explorer.exe -ArgumentList "/select,`"$($ipa[0].FullName)`""
}
