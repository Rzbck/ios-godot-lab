[CmdletBinding()]
param(
    [int]$Port = 8765,
    [string]$HostAddress,
    [string]$SessionId,
    [switch]$AllSessions,
    [switch]$AnyBuild,
    [ValidateRange(1, 12)][int]$ParallelDownloads = 3,
    [ValidateRange(1, 8)][int]$RetryCount = 4,
    [switch]$KeepFrames,
    [switch]$KeepRaw,
    [switch]$NoVideo,
    [switch]$OpenFolder
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

function Get-ApiSessionPath {
    $Root = Join-Path $env:LOCALAPPDATA 'CloudWeightLab'
    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    return (Join-Path $Root 'diagnostics-session.json')
}

function Invoke-ApiJson {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Token,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [int]$TimeoutSec = 5,
        [int]$Attempts = 2
    )

    $Headers = @{}
    if (-not [string]::IsNullOrWhiteSpace($Token)) {
        $Headers.Authorization = "Bearer $Token"
    }

    $LastError = $null
    foreach ($Attempt in 1..[Math]::Max(1, $Attempts)) {
        try {
            return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -TimeoutSec $TimeoutSec
        } catch {
            $LastError = $_
            if ($Attempt -lt $Attempts) { Start-Sleep -Milliseconds (250 * $Attempt) }
        }
    }
    throw $LastError
}

function Test-CloudWeightHost {
    param([Parameter(Mandatory)][string]$Address)
    try {
        $Health = Invoke-RestMethod -Uri "http://${Address}:$Port/api/v1/health" -Method Get -TimeoutSec 1
        if ([string]$Health.app -eq 'Cloud Weight Lab') { return $Health }
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
    if ($LocalAddresses.Count -eq 0) { throw 'Aucune interface IPv4 locale trouvée.' }

    $Candidates = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Local in $LocalAddresses) {
        $Parts = $Local.Split('.')
        if ($Parts.Count -ne 4) { continue }
        $Prefix = "$($Parts[0]).$($Parts[1]).$($Parts[2])"
        foreach ($Last in 1..254) { [void]$Candidates.Add("$Prefix.$Last") }
    }

    Write-Host "Recherche de l'iPhone Cloud Weight sur le LAN…" -ForegroundColor DarkCyan
    $Hits = @(
        $Candidates | ForEach-Object -Parallel {
            $Address = $_
            try {
                $Health = Invoke-RestMethod -Uri "http://${Address}:$using:Port/api/v1/health" -Method Get -TimeoutSec 1
                if ([string]$Health.app -eq 'Cloud Weight Lab') {
                    [pscustomobject]@{
                        Address = $Address
                        Build = [string]$Health.build
                        Version = [string]$Health.version
                    }
                }
            } catch {}
        } -ThrottleLimit 64
    )
    if ($Hits.Count -eq 0) {
        throw "API Cloud Weight introuvable. Ouvre l'app sur l'iPhone, utilise le même Wi-Fi et vérifie l'autorisation Réseau local."
    }
    return $Hits[0]
}

function Save-ApiSession {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Token,
        [string]$Build
    )
    $Saved = [pscustomobject]@{
        base_url = $BaseUrl
        token = $Token
        build = $Build
        paired_at = (Get-Date).ToString('o')
    }
    $Saved | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
    return $Saved
}

function Get-OrCreateApiSession {
    $SessionPath = Get-ApiSessionPath
    $Saved = $null

    if (Test-Path -LiteralPath $SessionPath) {
        try { $Saved = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json } catch {}
    }

    if ($null -ne $Saved -and -not [string]::IsNullOrWhiteSpace([string]$Saved.base_url)) {
        try {
            $Health = Invoke-RestMethod -Uri "$($Saved.base_url)/api/v1/health" -Method Get -TimeoutSec 2
            $null = Invoke-ApiJson -Uri "$($Saved.base_url)/api/v1/sessions" -Token ([string]$Saved.token) -TimeoutSec 3 -Attempts 1
            if ([string]$Health.app -eq 'Cloud Weight Lab') {
                Write-Host "Connexion directe : $($Saved.base_url)" -ForegroundColor Green
                return [pscustomobject]@{ Session = $Saved; Health = $Health }
            }
        } catch {}
    }

    $Found = Find-CloudWeightHost
    $BaseUrl = "http://$($Found.Address):$Port"
    $Health = Invoke-RestMethod -Uri "$BaseUrl/api/v1/health" -Method Get -TimeoutSec 3
    Write-Host "iPhone trouvé : $BaseUrl · build $($Health.build)" -ForegroundColor Green

    if ($null -ne $Saved -and -not [string]::IsNullOrWhiteSpace([string]$Saved.token)) {
        try {
            $null = Invoke-ApiJson -Uri "$BaseUrl/api/v1/sessions" -Token ([string]$Saved.token) -TimeoutSec 3 -Attempts 1
            $Refreshed = Save-ApiSession -Path $SessionPath -BaseUrl $BaseUrl -Token ([string]$Saved.token) -Build ([string]$Health.build)
            Write-Host 'Jeton persistant réutilisé automatiquement.' -ForegroundColor Green
            return [pscustomobject]@{ Session = $Refreshed; Health = $Health }
        } catch {}
    }

    try {
        $PairResponse = Invoke-ApiJson -Uri "$BaseUrl/api/v1/pair" -Method POST -TimeoutSec 4 -Attempts 2
    } catch {
        throw "Connexion automatique impossible. L'iPhone possède peut-être déjà un autre jeton persistant. Détail : $($_.Exception.Message)"
    }

    if ($null -eq $PairResponse -or [string]::IsNullOrWhiteSpace([string]$PairResponse.token)) {
        throw "La connexion automatique n'a retourné aucun jeton."
    }

    $Created = Save-ApiSession -Path $SessionPath -BaseUrl $BaseUrl -Token ([string]$PairResponse.token) -Build ([string]$PairResponse.build)
    Write-Host 'Première connexion automatique enregistrée. Plus aucun bouton API à presser.' -ForegroundColor Green
    return [pscustomobject]@{ Session = $Created; Health = $Health }
}

function Merge-TelemetryChunks {
    param([Parameter(Mandatory)][string]$OutDir)
    $TelemetryDir = Join-Path $OutDir 'telemetry'
    if (-not (Test-Path -LiteralPath $TelemetryDir)) { return $null }
    $Chunks = @(Get-ChildItem -LiteralPath $TelemetryDir -Filter 'telemetry-*.ndjson' -File | Sort-Object Name)
    if ($Chunks.Count -eq 0) { return $null }
    $Merged = Join-Path $OutDir 'telemetry.ndjson'
    if (Test-Path -LiteralPath $Merged) { Remove-Item -LiteralPath $Merged -Force }
    foreach ($Chunk in $Chunks) {
        Get-Content -LiteralPath $Chunk.FullName | Add-Content -LiteralPath $Merged -Encoding UTF8
    }
    return $Merged
}

function Get-NdjsonLineCount {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
}

function Make-DiagnosticVideo {
    param([Parameter(Mandatory)][string]$OutDir)
    $VisualIndex = Join-Path $OutDir 'visual\visual.ndjson'
    if (-not (Test-Path -LiteralPath $VisualIndex)) { return $null }
    $Ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($null -eq $Ffmpeg) {
        Write-Host 'ffmpeg non installé : images conservées, MP4 non créé.' -ForegroundColor DarkYellow
        return $null
    }

    $Frames = @(
        Get-Content -LiteralPath $VisualIndex |
            ForEach-Object {
                if (-not [string]::IsNullOrWhiteSpace($_)) { $_ | ConvertFrom-Json }
            } |
            Sort-Object {[double]$_.timestamp}
    )
    if ($Frames.Count -lt 2) { return $null }

    $MissingFrames = @($Frames | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $OutDir ([string]$_.relativePath)))
    })
    if ($MissingFrames.Count -gt 0) {
        throw "Le téléchargement visuel est incomplet : $($MissingFrames.Count) frame(s) référencée(s) manquent."
    }

    $Concat = Join-Path $OutDir 'session.ffconcat'
    $Video = Join-Path $OutDir 'diagnostic-preview.mp4'
    $Lines = @('ffconcat version 1.0')
    for ($i = 0; $i -lt $Frames.Count; $i++) {
        $LocalPath = Join-Path $OutDir ([string]$Frames[$i].relativePath)
        $Escaped = $LocalPath.Replace("'", "''")
        $Lines += "file '$Escaped'"
        if ($i -lt $Frames.Count - 1) {
            $Delta = [double]$Frames[$i + 1].timestamp - [double]$Frames[$i].timestamp
            $Delta = [Math]::Min(2.0, [Math]::Max(0.04, $Delta))
            $Lines += ('duration ' + $Delta.ToString('0.000000', [System.Globalization.CultureInfo]::InvariantCulture))
        }
    }
    $Lines | Set-Content -LiteralPath $Concat -Encoding UTF8

    & $Ffmpeg.Source -hide_banner -loglevel error -y -f concat -safe 0 -i $Concat -vf 'format=yuv420p' -c:v libx264 -crf 28 $Video
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Video)) {
        Write-Host 'Création MP4 échouée ; images conservées.' -ForegroundColor Yellow
        return $null
    }
    Remove-Item -LiteralPath $Concat -Force -ErrorAction SilentlyContinue
    return $Video
}

function Sync-OneSession {
    param(
        [Parameter(Mandatory)]$SessionSummary,
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Root
    )

    $Id = [string]$SessionSummary.sessionID
    $OutDir = Join-Path $Root "artifacts\cloud-weight-lab\sessions\$Id"
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

    $Manifest = Invoke-ApiJson -Uri "$BaseUrl/api/v1/sessions/$Id/manifest" -Token $Token -TimeoutSec 8 -Attempts 3

    if ([string]$Manifest.state -eq 'recording') {
        Write-Host 'SESSION ACTIVE = scellement automatique avant synchronisation...' -ForegroundColor DarkCyan

        $Seal = Invoke-ApiJson `
            -Uri "$BaseUrl/api/v1/sessions/$Id/seal" `
            -Token $Token `
            -Method POST `
            -TimeoutSec 8 `
            -Attempts 3

        if ($null -eq $Seal -or $Seal.ok -ne $true) {
            throw "Impossible de figer automatiquement la session $Id."
        }

        $Manifest = Invoke-ApiJson -Uri "$BaseUrl/api/v1/sessions/$Id/manifest" -Token $Token -TimeoutSec 8 -Attempts 3

        if ([string]$Manifest.state -eq 'recording') {
            throw "La session $Id est encore active après scellement."
        }

        Write-Host "SESSION FIGEE = $Id" -ForegroundColor Green
    }

    $Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'manifest.json') -Encoding UTF8
    $FilesPayload = Invoke-ApiJson -Uri "$BaseUrl/api/v1/sessions/$Id/files" -Token $Token -TimeoutSec 15 -Attempts 3
    $Files = @($FilesPayload | ForEach-Object { $_ })

    Write-Host "`n=== SYNC CLOUD WEIGHT SESSION ===" -ForegroundColor Cyan
    Write-Host "SESSION     = $Id"
    Write-Host "STATE       = $($Manifest.state)"
    Write-Host "BUILD       = $($Manifest.buildSHA)"
    Write-Host "TELEMETRY   = $($Manifest.telemetryRecords) records"
    Write-Host "EVENTS      = $($Manifest.eventRecords)"
    Write-Host "VISUAL      = $($Manifest.visualFrames) frames"
    Write-Host "FILES       = $($Files.Count)"
    Write-Host "OUTPUT      = $OutDir" -ForegroundColor Green

    $Headers = @{ Authorization = "Bearer $Token" }
    $DownloadItems = @($Files | Where-Object { [string]$_.path -ne 'manifest.json' })
    $DownloadItems | ForEach-Object -Parallel {
        $Item = $_
        $Relative = [string]$Item.path
        $ExpectedBytes = [int64]$Item.byteCount
        $Destination = Join-Path $using:OutDir $Relative
        $Parent = Split-Path -Parent $Destination
        if (-not (Test-Path -LiteralPath $Parent)) {
            New-Item -ItemType Directory -Path $Parent -Force | Out-Null
        }

        if (Test-Path -LiteralPath $Destination) {
            $Existing = (Get-Item -LiteralPath $Destination).Length
            if ($Existing -eq $ExpectedBytes) { return }
        }

        $Escaped = [Uri]::EscapeDataString($Relative)
        $Uri = "$using:BaseUrl/api/v1/sessions/$using:Id/file?path=$Escaped"
        $Part = "$Destination.part"
        $Success = $false
        $LastMessage = ''

        foreach ($Attempt in 1..$using:RetryCount) {
            Remove-Item -LiteralPath $Part -Force -ErrorAction SilentlyContinue
            try {
                Invoke-WebRequest -Uri $Uri -Headers $using:Headers -OutFile $Part -TimeoutSec 60
                $Actual = (Get-Item -LiteralPath $Part).Length
                if ($Actual -ne $ExpectedBytes) {
                    throw "taille $Actual != $ExpectedBytes"
                }
                Move-Item -LiteralPath $Part -Destination $Destination -Force
                $Success = $true
                break
            } catch {
                $LastMessage = $_.Exception.Message
                Remove-Item -LiteralPath $Part -Force -ErrorAction SilentlyContinue
                if ($Attempt -lt $using:RetryCount) {
                    Start-Sleep -Milliseconds (400 * $Attempt)
                }
            }
        }

        if (-not $Success) {
            throw "Téléchargement impossible après $using:RetryCount tentative(s) : $Relative · $LastMessage"
        }
    } -ThrottleLimit $ParallelDownloads

    $MergedTelemetry = Merge-TelemetryChunks -OutDir $OutDir
    if ($null -eq $MergedTelemetry) { throw 'Aucune télémétrie fusionnable dans la session.' }

    $TelemetryCount = Get-NdjsonLineCount -Path $MergedTelemetry
    $EventsPath = Join-Path $OutDir 'events.ndjson'
    $VisualPath = Join-Path $OutDir 'visual\visual.ndjson'
    $EventCount = Get-NdjsonLineCount -Path $EventsPath
    $VisualCount = Get-NdjsonLineCount -Path $VisualPath

    $IsFinished = [string]$Manifest.state -ne 'recording'
    if ($IsFinished) {
        if ($TelemetryCount -ne [int]$Manifest.telemetryRecords) {
            throw "Validation télémétrie échouée : $TelemetryCount != $($Manifest.telemetryRecords)."
        }
        if ($EventCount -ne [int]$Manifest.eventRecords) {
            throw "Validation événements échouée : $EventCount != $($Manifest.eventRecords)."
        }
        if ($VisualCount -ne [int]$Manifest.visualFrames) {
            throw "Validation visuelle échouée : $VisualCount != $($Manifest.visualFrames)."
        }
    }

    $Video = $null
    if (-not $NoVideo) { $Video = Make-DiagnosticVideo -OutDir $OutDir }

    $Report = [ordered]@{
        sessionID = $Id
        buildSHA = [string]$Manifest.buildSHA
        appVersion = [string]$Manifest.appVersion
        state = [string]$Manifest.state
        syncedAt = (Get-Date).ToString('o')
        expectedTelemetryRecords = [int]$Manifest.telemetryRecords
        actualTelemetryRecords = $TelemetryCount
        expectedEventRecords = [int]$Manifest.eventRecords
        actualEventRecords = $EventCount
        expectedVisualFrames = [int]$Manifest.visualFrames
        actualVisualFrames = $VisualCount
        remoteFileCount = $Files.Count
        videoCreated = ($null -ne $Video)
        complete = (-not $IsFinished) -or (
            $TelemetryCount -eq [int]$Manifest.telemetryRecords -and
            $EventCount -eq [int]$Manifest.eventRecords -and
            $VisualCount -eq [int]$Manifest.visualFrames
        )
    }
    $Report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'SYNC-REPORT.json') -Encoding UTF8

    if ($null -ne $Video -and -not $KeepFrames) {
        Remove-Item -LiteralPath (Join-Path $OutDir 'visual\keyframes') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $OutDir 'visual\bursts') -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $MergedTelemetry -and -not $KeepRaw) {
        Remove-Item -LiteralPath (Join-Path $OutDir 'telemetry') -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "SYNC        = OK + VALIDÉ" -ForegroundColor Green
    Write-Host "TELEMETRY   = $TelemetryCount" -ForegroundColor Green
    Write-Host "EVENTS      = $EventCount" -ForegroundColor Green
    Write-Host "VISUAL      = $VisualCount" -ForegroundColor Green
    if ($null -ne $Video) { Write-Host "VIDEO       = $Video" -ForegroundColor Green }
    Write-Host "REPORT      = $(Join-Path $OutDir 'SYNC-REPORT.json')" -ForegroundColor Green

    return $OutDir
}

$Connection = Get-OrCreateApiSession
$ApiSession = $Connection.Session
$Health = $Connection.Health
$BaseUrl = [string]$ApiSession.base_url
$Token = [string]$ApiSession.token
$CurrentBuild = [string]$Health.build
$Root = Get-ContainerRoot

$SessionsPayload = Invoke-ApiJson -Uri "$BaseUrl/api/v1/sessions" -Token $Token -TimeoutSec 8 -Attempts 3
$Sessions = @($SessionsPayload | ForEach-Object { $_ }) | Sort-Object {[double]$_.startedAt} -Descending
if ($Sessions.Count -eq 0) { throw 'Aucune session Cloud Weight enregistrée sur cet iPhone.' }

$Selected = @()
if ($AllSessions) {
    $Selected = if ($AnyBuild) { $Sessions } else { @($Sessions | Where-Object { [string]$_.buildSHA -eq $CurrentBuild }) }
    if ($Selected.Count -eq 0) { throw "Aucune session du build installé $CurrentBuild." }
} elseif (-not [string]::IsNullOrWhiteSpace($SessionId)) {
    $Selected = @($Sessions | Where-Object { [string]$_.sessionID -eq $SessionId })
    if ($Selected.Count -eq 0) { throw "Session '$SessionId' introuvable." }
} else {
    $Candidates = if ($AnyBuild) { $Sessions } else { @($Sessions | Where-Object { [string]$_.buildSHA -eq $CurrentBuild }) }
    if ($Candidates.Count -eq 0) {
        $AvailableBuilds = @($Sessions | Select-Object -ExpandProperty buildSHA -Unique) -join ', '
        throw "Aucune session correspondant au build actuellement installé $CurrentBuild. Builds présents : $AvailableBuilds"
    }

    $Newest = $Candidates[0]
    $Selected = @($Newest)

    if ([string]$Newest.state -eq 'recording') {
        Write-Host "Session active la plus récente sélectionnée : $($Newest.sessionID)" -ForegroundColor DarkCyan
    } else {
        Write-Host "Session la plus récente du build courant sélectionnée : $($Newest.sessionID)" -ForegroundColor DarkCyan
    }
}

$LastOutput = $null
foreach ($Session in $Selected) {
    $LastOutput = Sync-OneSession -SessionSummary $Session -BaseUrl $BaseUrl -Token $Token -Root $Root
}

if ($OpenFolder -and $null -ne $LastOutput) {
    Start-Process explorer.exe $LastOutput
}
