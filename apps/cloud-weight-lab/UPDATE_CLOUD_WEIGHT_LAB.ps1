[CmdletBinding()]
param(
    [string]$Repository = 'Rzbck/ios-godot-lab',
    [string]$Workflow = 'cloud-weight-lab-build.yml',
    [string]$ExpectedBranch = 'fix/cloud-weight-tracking-live-diag-v8-20260927',
    [int]$BuildTimeoutMinutes = 50,
    [switch]$NoAutoBuild,
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

function Get-ExactRuns {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Sha
    )

    $Json = & gh run list --repo $Repo --workflow $WorkflowName --branch $Branch --limit 100 --json databaseId,headSha,status,conclusion,createdAt
    Assert-NativeSuccess 'gh run list'
    if ([string]::IsNullOrWhiteSpace(($Json -join ''))) { return @() }
    return @($Json | ConvertFrom-Json | Where-Object { [string]$_.headSha -eq $Sha } | Sort-Object createdAt -Descending)
}

function Test-ExactArtifact {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][Int64]$RunId,
        [Parameter(Mandatory)][string]$Sha
    )

    $ExpectedName = "cloud-weight-lab-$Sha"
    $Json = & gh api "repos/$Repo/actions/runs/$RunId/artifacts?per_page=100"
    Assert-NativeSuccess 'gh api artifacts'
    $Payload = $Json | ConvertFrom-Json
    return @($Payload.artifacts | Where-Object { $_.name -eq $ExpectedName -and $_.expired -ne $true }).Count -gt 0
}

function Wait-ExactBuild {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$WorkflowName,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Sha,
        [Parameter(Mandatory)][int]$TimeoutMinutes,
        [switch]$MayTrigger
    )

    $Deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $Triggered = $false

    while ((Get-Date) -lt $Deadline) {
        $Runs = @(Get-ExactRuns -Repo $Repo -WorkflowName $WorkflowName -Branch $Branch -Sha $Sha)

        foreach ($Run in @($Runs | Where-Object { $_.status -eq 'completed' -and $_.conclusion -eq 'success' })) {
            if (Test-ExactArtifact -Repo $Repo -RunId ([Int64]$Run.databaseId) -Sha $Sha) {
                return $Run
            }
        }

        $Active = $Runs | Where-Object { $_.status -in @('queued','in_progress','pending','requested','waiting') } | Select-Object -First 1
        if ($null -ne $Active) {
            Write-Host ("BUILD       = {0} - {1}" -f $Active.databaseId, $Active.status) -ForegroundColor DarkCyan
            Start-Sleep -Seconds 5
            continue
        }

        $Failed = $Runs | Where-Object { $_.status -eq 'completed' -and $_.conclusion -notin @('success','cancelled','skipped') } | Select-Object -First 1
        if ($null -ne $Failed -and $Triggered) {
            throw "Exact build $($Failed.databaseId) failed with '$($Failed.conclusion)' for $Sha."
        }

        if (-not $MayTrigger) {
            throw "No retained exact-SHA artifact exists for $Sha."
        }

        if (-not $Triggered) {
            Write-Host 'No exact-SHA artifact found. Triggering GitHub Actions…' -ForegroundColor Yellow
            & gh workflow run $WorkflowName --repo $Repo --ref $Branch | Out-Host
            Assert-NativeSuccess 'gh workflow run'
            $Triggered = $true
            Start-Sleep -Seconds 4
            continue
        }

        Start-Sleep -Seconds 5
    }

    throw "Timed out after $TimeoutMinutes minute(s) waiting for $Sha."
}

Write-Host "`n=== CLOUD WEIGHT LAB - EXACT IPA SYNC ===" -ForegroundColor Cyan

if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) { throw 'git not found in PATH.' }
if ($null -eq (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) not found in PATH.' }
if ($BuildTimeoutMinutes -lt 1 -or $BuildTimeoutMinutes -gt 120) { throw 'BuildTimeoutMinutes must be between 1 and 120.' }

$RepoTop = (& git rev-parse --show-toplevel).Trim()
Assert-NativeSuccess 'git rev-parse --show-toplevel'
$Branch = (& git branch --show-current).Trim()
Assert-NativeSuccess 'git branch --show-current'
$HeadSha = (& git rev-parse HEAD).Trim()
Assert-NativeSuccess 'git rev-parse HEAD'
$Dirty = @(& git status --porcelain)
Assert-NativeSuccess 'git status --porcelain'

if ($Branch -ne $ExpectedBranch) {
    throw "Current branch '$Branch' does not match expected '$ExpectedBranch'."
}
if ($Dirty.Count -gt 0) {
    Write-Host 'WORKTREE    = DIRTY (artifact sync remains read-only for Git)' -ForegroundColor Yellow
} else {
    Write-Host 'WORKTREE    = CLEAN' -ForegroundColor Green
}

Write-Host "BRANCH      = $Branch"
Write-Host "HEAD        = $HeadSha"

$Run = Wait-ExactBuild -Repo $Repository -WorkflowName $Workflow -Branch $Branch -Sha $HeadSha -TimeoutMinutes $BuildTimeoutMinutes -MayTrigger:(-not $NoAutoBuild)
$ArtifactName = "cloud-weight-lab-$HeadSha"
$Container = if ((Split-Path -Leaf (Split-Path -Parent $RepoTop)) -eq 'worktrees') { Split-Path -Parent (Split-Path -Parent $RepoTop) } else { $RepoTop }
$Destination = Join-Path $Container ("artifacts\cloud-weight-lab\" + $HeadSha)
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("cloud-weight-lab-" + [Guid]::NewGuid().ToString('N'))

New-Item -ItemType Directory -Path $Temp -Force | Out-Null
try {
    & gh run download ([string]$Run.databaseId) --repo $Repository --name $ArtifactName --dir $Temp
    Assert-NativeSuccess 'gh run download'

    $MetadataPath = Join-Path $Temp 'BUILD-METADATA.json'
    if (-not (Test-Path -LiteralPath $MetadataPath)) { throw 'BUILD-METADATA.json missing.' }
    $Metadata = Get-Content -LiteralPath $MetadataPath -Raw | ConvertFrom-Json
    if ([string]$Metadata.sha -ne $HeadSha) { throw "Metadata SHA '$($Metadata.sha)' does not match HEAD '$HeadSha'." }

    $Ipa = @(Get-ChildItem -LiteralPath $Temp -Filter '*.ipa' -File)
    $HashFile = @(Get-ChildItem -LiteralPath $Temp -Filter '*.ipa.sha256' -File)
    if ($Ipa.Count -ne 1 -or $HashFile.Count -ne 1) { throw 'Expected exactly one IPA and one SHA-256 file.' }

    $ExpectedLine = (Get-Content -LiteralPath $HashFile[0].FullName -TotalCount 1).Trim()
    if ($ExpectedLine -notmatch '^([0-9a-fA-F]{64})\b') { throw 'Invalid SHA-256 file.' }
    $ActualHash = (Get-FileHash -LiteralPath $Ipa[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($Matches[1].ToLowerInvariant() -ne $ActualHash) { throw 'IPA SHA-256 mismatch.' }

    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Copy-Item -Path (Join-Path $Temp '*') -Destination $Destination -Recurse -Force

    Write-Host "RUN         = $($Run.databaseId)" -ForegroundColor Green
    Write-Host "ARTIFACT    = $ArtifactName" -ForegroundColor Green
    Write-Host "IPA         = $($Ipa[0].Name)" -ForegroundColor Green
    Write-Host "SHA256      = $ActualHash" -ForegroundColor Green
    Write-Host "DESTINATION = $Destination" -ForegroundColor Cyan
    Write-Host 'Next: install this exact IPA with iLoader, then validate on the iPhone.' -ForegroundColor Yellow

    if ($OpenFolder) { Start-Process explorer.exe $Destination }
}
finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force }
}
