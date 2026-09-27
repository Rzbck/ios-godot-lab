[CmdletBinding()]
param(
    [int]$Port = 8765,
    [string]$HostAddress,
    [switch]$OpenFolder,
    [switch]$ClearRemoteSnapshots
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-ContainerRoot {
    $RepoTop = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($RepoTop -join ''))) {
        return (Get-Location).Path
    }
    $RepoTop = ($RepoTop -join '').Trim()
    $Parent = Split-Path -Parent $RepoTop
    if ((Split-Path -Leaf $Parent) -eq 'worktrees') {
        return (Split-Path -Parent $Parent)
    }
    return $RepoTop
}

function Get-SessionPath {
    $Root = Join-Path $env:LOCALAPPDATA 'CloudWeightLab'
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    return (Join-Path $Root 'diagnostics-session.json')
}

function Invoke-ApiJson {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Token,
        [ValidateSet('GET','POST','DELETE')][string]$Method = 'GET',
        [int]$TimeoutSec = 3
    )
    $Headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $Headers.Authorization = "Bearer $Token"
    }
    return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -TimeoutSec $TimeoutSec
}

function Test-CloudWeightHost {
    param([Parameter(Mandatory)][string]$Address)
    try {
        $Health = Invoke-RestMethod -Uri "http://${Address}:$Port/api/v1/health" -Method Get -TimeoutSec 1
        if ([string]$Health.app -eq 'Cloud Weight Lab') {
            return $Health
        }
    } catch {}
    return $null
}

function Find-CloudWeightHost {
    if (-not [string]::IsNullOrWhiteSpace($HostAddress)) {
        $Health = Test-CloudWeightHost -Address $HostAddress
        if ($null -eq $Health) { throw "Cloud Weight Lab API introuvable sur $HostAddress`:$Port." }
        return [pscustomobject]@{ Address = $HostAddress; Health = $Health }
    }

    $LocalAddresses = @(
        Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notmatch '^127\.' -and
                $_.IPAddress -notmatch '^169\.254\.' -and
                $_.IPAddress -notmatch '^0\.'
            } |
            Select-Object -ExpandProperty IPAddress -Unique
    )

    if ($LocalAddresses.Count -eq 0) {
        throw 'Aucune interface IPv4 locale trouvée.'
    }

    $Candidates = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Local in $LocalAddresses) {
        $Parts = $Local.Split('.')
        if ($Parts.Count -ne 4) { continue }
        $Prefix = "$($Parts[0]).$($Parts[1]).$($Parts[2])"
        foreach ($Last in 1..254) {
            [void]$Candidates.Add("$Prefix.$Last")
        }
    }

    Write-Host "Recherche de l'iPhone Cloud Weight sur le LAN…" -ForegroundColor DarkCyan

    $Hits = @(
        $Candidates |
            ForEach-Object -Parallel {
                $Address = $_
                try {
                    $Health = Invoke-RestMethod -Uri "http://${Address}:$using:Port/api/v1/health" -Method Get -TimeoutSec 1
                    if ([string]$Health.app -eq 'Cloud Weight Lab') {
                        [pscustomobject]@{
                            Address = $Address
                            Build = [string]$Health.build
                            Paired = [bool]$Health.paired
                            PairingArmed = [bool]$Health.pairing_armed
                        }
                    }
                } catch {}
            } -ThrottleLimit 64
    )

    if ($Hits.Count -eq 0) {
        throw "API Cloud Weight introuvable. Vérifie que l'iPhone et le PC sont sur le même Wi-Fi et que l'accès Réseau local est autorisé pour l'app."
    }
    if ($Hits.Count -gt 1) {
        Write-Host 'Plusieurs instances trouvées ; utilisation de la première :' -ForegroundColor Yellow
        $Hits | Format-Table | Out-Host
    }

    $Hit = $Hits[0]
    $Health = Test-CloudWeightHost -Address $Hit.Address
    return [pscustomobject]@{ Address = $Hit.Address; Health = $Health }
}

$SessionPath = Get-SessionPath
$Session = $null
if (Test-Path -LiteralPath $SessionPath) {
    try {
        $Session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
        $TestStatus = Invoke-ApiJson -Uri "$($Session.base_url)/api/v1/status" -Token ([string]$Session.token) -TimeoutSec 2
        Write-Host "Session API existante : $($Session.base_url)" -ForegroundColor Green
    } catch {
        $Session = $null
        Remove-Item -LiteralPath $SessionPath -Force -ErrorAction SilentlyContinue
    }
}

if ($null -eq $Session) {
    $Found = Find-CloudWeightHost
    $BaseUrl = "http://$($Found.Address):$Port"

    Write-Host "iPhone trouvé : $BaseUrl" -ForegroundColor Green
    Write-Host "Appuie une fois sur le petit bouton API dans Cloud Weight. Le script attend l'ouverture de la fenêtre d'appairage…" -ForegroundColor Yellow

    $Deadline = (Get-Date).AddSeconds(60)
    $PairResponse = $null
    while ((Get-Date) -lt $Deadline) {
        try {
            $Health = Invoke-RestMethod -Uri "$BaseUrl/api/v1/health" -Method Get -TimeoutSec 2
            if ([bool]$Health.pairing_armed) {
                $PairResponse = Invoke-RestMethod -Uri "$BaseUrl/api/v1/pair" -Method Post -TimeoutSec 3
                break
            }
        } catch {}
        Start-Sleep -Milliseconds 500
    }

    if ($null -eq $PairResponse -or [string]::IsNullOrWhiteSpace([string]$PairResponse.token)) {
        throw "Appairage non réalisé. Relance le script et touche API dans l'app quand il te le demande."
    }

    $Session = [pscustomobject]@{
        base_url = $BaseUrl
        token = [string]$PairResponse.token
        build = [string]$PairResponse.build
        paired_at = (Get-Date).ToString('o')
    }
    $Session | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    Write-Host 'Appairage local établi.' -ForegroundColor Green
}

$BaseUrl = [string]$Session.base_url
$Token = [string]$Session.token
$Status = Invoke-ApiJson -Uri "$BaseUrl/api/v1/status" -Token $Token
$Telemetry = Invoke-ApiJson -Uri "$BaseUrl/api/v1/telemetry?limit=180" -Token $Token
$Snapshots = @(Invoke-ApiJson -Uri "$BaseUrl/api/v1/snapshots" -Token $Token)

$Container = Get-ContainerRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Build = [string]$Status.build
$OutDir = Join-Path $Container ("artifacts\cloud-weight-lab\diagnostics\$Stamp-$Build")
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'status.json') -Encoding UTF8
$Telemetry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'telemetry.json') -Encoding UTF8
$Snapshots | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'snapshots.json') -Encoding UTF8

$Headers = @{ Authorization = "Bearer $Token" }
foreach ($Snapshot in $Snapshots) {
    $Id = [string]$Snapshot.id
    if ([string]::IsNullOrWhiteSpace($Id)) { continue }
    $Destination = Join-Path $OutDir ("snapshot-$Id.jpg")
    Invoke-WebRequest -Uri "$BaseUrl/api/v1/snapshots/$Id.jpg" -Headers $Headers -OutFile $Destination -TimeoutSec 5
}

if ($ClearRemoteSnapshots) {
    Invoke-ApiJson -Uri "$BaseUrl/api/v1/snapshots" -Token $Token -Method DELETE | Out-Null
}

Write-Host "`n=== CLOUD WEIGHT DIAGNOSTICS ===" -ForegroundColor Cyan
Write-Host "BUILD       = $Build"
Write-Host "API         = $BaseUrl"
Write-Host "SNAPSHOTS   = $($Snapshots.Count)"
Write-Host "OUTPUT      = $OutDir" -ForegroundColor Green

if ($null -ne $Status.telemetry) {
    Write-Host ("PIPELINE    = {0:N0} ms" -f [double]$Status.telemetry.analysisMilliseconds)
    Write-Host ("CADENCE     = {0:N2} Hz" -f [double]$Status.telemetry.effectiveHz)
    Write-Host ("SKY/CLOUD   = {0:N1}% / {1:N1}%" -f [double]$Status.telemetry.skyCoveragePercent, [double]$Status.telemetry.cloudCoveragePercent)
    Write-Host ("ORIENTATION = {0}" -f [string]$Status.telemetry.orientation)
}

if ($OpenFolder) {
    Start-Process explorer.exe $OutDir
}
