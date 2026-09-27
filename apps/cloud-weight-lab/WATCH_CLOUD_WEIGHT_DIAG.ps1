[CmdletBinding()]
param(
    [int]$Port = 8765,
    [string]$HostAddress,
    [ValidateRange(250, 5000)][int]$IntervalMilliseconds = 500,
    [ValidateRange(0, 86400)][int]$DurationSeconds = 0,
    [switch]$OpenFolder,
    [switch]$ClearRemoteSnapshotsOnStart,
    [switch]$MakeVideo,
    [switch]$KeepFrames
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
        throw "API Cloud Weight introuvable. Vérifie le même Wi-Fi et l'autorisation Réseau local de l'app."
    }
    if ($Hits.Count -gt 1) {
        Write-Host 'Plusieurs instances trouvées ; utilisation de la première :' -ForegroundColor Yellow
        $Hits | Format-Table | Out-Host
    }

    $Hit = $Hits[0]
    $Health = Test-CloudWeightHost -Address $Hit.Address
    return [pscustomobject]@{ Address = $Hit.Address; Health = $Health }
}

function Get-OrCreateSession {
    $SessionPath = Get-SessionPath
    $Session = $null

    if (Test-Path -LiteralPath $SessionPath) {
        try {
            $Session = Get-Content -LiteralPath $SessionPath -Raw | ConvertFrom-Json
            $null = Invoke-ApiJson -Uri "$($Session.base_url)/api/v1/status" -Token ([string]$Session.token) -TimeoutSec 2
            Write-Host "Session API existante : $($Session.base_url)" -ForegroundColor Green
        } catch {
            $Session = $null
            Remove-Item -LiteralPath $SessionPath -Force -ErrorAction SilentlyContinue
        }
    }

    if ($null -ne $Session) {
        return $Session
    }

    $Found = Find-CloudWeightHost
    $BaseUrl = "http://$($Found.Address):$Port"
    Write-Host "iPhone trouvé : $BaseUrl" -ForegroundColor Green
    Write-Host "Appuie une fois sur le petit bouton API dans Cloud Weight. J'attends 60 s…" -ForegroundColor Yellow

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
        throw "Appairage non réalisé. Relance puis touche API quand le script le demande."
    }

    $Session = [pscustomobject]@{
        base_url = $BaseUrl
        token = [string]$PairResponse.token
        build = [string]$PairResponse.build
        paired_at = (Get-Date).ToString('o')
    }
    $Session | ConvertTo-Json | Set-Content -LiteralPath $SessionPath -Encoding UTF8
    Write-Host 'Appairage local établi.' -ForegroundColor Green
    return $Session
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $Property = $Object.PSObject.Properties[$Name]
    if ($null -eq $Property) { return $Default }
    return $Property.Value
}

function Write-TelemetryCsvRow {
    param(
        [Parameter(Mandatory)]$Record,
        [Parameter(Mandatory)][string]$Path
    )
    $T = $Record.telemetry
    $Row = [pscustomobject]@{
        timestamp = [double]$Record.timestamp
        pipeline_ms = [double](Get-PropertyValue $T 'analysisMilliseconds' 0)
        hz = [double](Get-PropertyValue $T 'effectiveHz' 0)
        prep_ms = [double](Get-PropertyValue $T 'preprocessingMilliseconds' 0)
        sky_ms = [double](Get-PropertyValue $T 'skyInferenceMilliseconds' 0)
        cloud_ms = [double](Get-PropertyValue $T 'cloudInferenceMilliseconds' 0)
        post_ms = [double](Get-PropertyValue $T 'postprocessingMilliseconds' 0)
        mask_delta_pct = [double](Get-PropertyValue $T 'maskChangePercent' 0)
        cloud_pct = [double](Get-PropertyValue $T 'cloudCoveragePercent' 0)
        sky_pct = [double](Get-PropertyValue $T 'skyCoveragePercent' 0)
        raw = [int](Get-PropertyValue $T 'rawDetections' 0)
        visible = [int](Get-PropertyValue $T 'trackingVisibleTracks' (Get-PropertyValue $T 'stabilizedDetections' 0))
        active_tracks = [int](Get-PropertyValue $T 'trackingActiveTracks' 0)
        hidden_tracks = [int](Get-PropertyValue $T 'trackingHiddenMissedTracks' 0)
        matched_tracks = [int](Get-PropertyValue $T 'trackingMatchedTracks' 0)
        new_tracks = [int](Get-PropertyValue $T 'trackingCreatedTracks' 0)
        dropped = [int](Get-PropertyValue $T 'droppedFrames' 0)
        throttled = [int](Get-PropertyValue $T 'throttledFrames' 0)
        thermal = [string](Get-PropertyValue $T 'thermalState' '')
        orientation = [string](Get-PropertyValue $T 'orientation' '')
        rotation_deg = [double](Get-PropertyValue $T 'captureRotationDegrees' 0)
        luminance_pct = [double](Get-PropertyValue $T 'sceneLuminancePercent' 0)
        rejected = [bool](Get-PropertyValue $T 'sceneRejected' $false)
    }

    if (Test-Path -LiteralPath $Path) {
        $Row | Export-Csv -LiteralPath $Path -NoTypeInformation -Append -Encoding UTF8
    } else {
        $Row | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
}

$Session = Get-OrCreateSession
$BaseUrl = [string]$Session.base_url
$Token = [string]$Session.token

if ($ClearRemoteSnapshotsOnStart) {
    Invoke-ApiJson -Uri "$BaseUrl/api/v1/snapshots" -Token $Token -Method DELETE | Out-Null
}

$InitialStatus = Invoke-ApiJson -Uri "$BaseUrl/api/v1/status" -Token $Token
$Build = [string]$InitialStatus.build
$Container = Get-ContainerRoot
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutDir = Join-Path $Container ("artifacts\cloud-weight-lab\diagnostics-live\$Stamp-$Build")
$FramesDir = Join-Path $OutDir 'frames'
New-Item -ItemType Directory -Path $FramesDir -Force | Out-Null

$StatusPath = Join-Path $OutDir 'status-latest.json'
$SnapshotsPath = Join-Path $OutDir 'snapshots-latest.json'
$TelemetryNDJSON = Join-Path $OutDir 'telemetry.ndjson'
$TelemetryCSV = Join-Path $OutDir 'telemetry.csv'
$DownloadedFrames = [System.Collections.Generic.HashSet[string]]::new()
$LastTelemetryTimestamp = 0.0
$Started = Get-Date
$LastConsoleUpdate = [datetime]::MinValue

$InitialStatus | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $StatusPath -Encoding UTF8

Write-Host "`n=== CLOUD WEIGHT LIVE DIAGNOSTICS ===" -ForegroundColor Cyan
Write-Host "BUILD       = $Build"
Write-Host "API         = $BaseUrl"
Write-Host "OUTPUT      = $OutDir" -ForegroundColor Green
Write-Host "INTERVAL    = $IntervalMilliseconds ms"
Write-Host "MODE        = continu ; Ctrl+C pour arrêter"
Write-Host "FRAMES      = séquence JPEG locale, récupérée au fil de l'eau"
Write-Host ''

if ($OpenFolder) {
    Start-Process explorer.exe $OutDir
}

try {
    while ($true) {
        if ($DurationSeconds -gt 0 -and ((Get-Date) - $Started).TotalSeconds -ge $DurationSeconds) {
            break
        }

        try {
            $Status = Invoke-ApiJson -Uri "$BaseUrl/api/v1/status" -Token $Token -TimeoutSec 3
            $Status | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $StatusPath -Encoding UTF8

            $AfterText = $LastTelemetryTimestamp.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
            $TelemetryResponse = Invoke-ApiJson -Uri "$BaseUrl/api/v1/telemetry?limit=300&after=$AfterText" -Token $Token -TimeoutSec 4
            $NewTelemetry = if ($null -eq $TelemetryResponse) { @() } else { @($TelemetryResponse) }

            foreach ($Record in $NewTelemetry) {
                if ($null -eq $Record) { continue }
                $Timestamp = [double](Get-PropertyValue $Record 'timestamp' 0)
                if ($Timestamp -le $LastTelemetryTimestamp) { continue }

                ($Record | ConvertTo-Json -Depth 12 -Compress) | Add-Content -LiteralPath $TelemetryNDJSON -Encoding UTF8
                Write-TelemetryCsvRow -Record $Record -Path $TelemetryCSV
                $LastTelemetryTimestamp = [Math]::Max($LastTelemetryTimestamp, $Timestamp)
            }

            $SnapshotResponse = Invoke-ApiJson -Uri "$BaseUrl/api/v1/snapshots" -Token $Token -TimeoutSec 4
            $Snapshots = if ($null -eq $SnapshotResponse) { @() } else { @($SnapshotResponse) }
            ConvertTo-Json -InputObject $Snapshots -Depth 10 | Set-Content -LiteralPath $SnapshotsPath -Encoding UTF8

            $Headers = @{ Authorization = "Bearer $Token" }
            foreach ($Snapshot in $Snapshots) {
                if ($null -eq $Snapshot) { continue }
                $Id = [string](Get-PropertyValue $Snapshot 'id' '')
                if ([string]::IsNullOrWhiteSpace($Id) -or $DownloadedFrames.Contains($Id)) { continue }

                $Destination = Join-Path $FramesDir ("frame-$Id.jpg")
                try {
                    Invoke-WebRequest -Uri "$BaseUrl/api/v1/snapshots/$Id.jpg" -Headers $Headers -OutFile $Destination -TimeoutSec 5
                    [void]$DownloadedFrames.Add($Id)
                } catch {
                    # The iPhone uses a bounded ring. If a frame expired between list and download,
                    # continue without killing the live session.
                }
            }

            if (((Get-Date) - $LastConsoleUpdate).TotalMilliseconds -ge 750) {
                $LastConsoleUpdate = Get-Date
                $T = $Status.telemetry
                if ($null -ne $T) {
                    $Pipeline = [double](Get-PropertyValue $T 'analysisMilliseconds' 0)
                    $Hz = [double](Get-PropertyValue $T 'effectiveHz' 0)
                    $Mask = [double](Get-PropertyValue $T 'maskChangePercent' 0)
                    $Cloud = [double](Get-PropertyValue $T 'cloudCoveragePercent' 0)
                    $Sky = [double](Get-PropertyValue $T 'skyCoveragePercent' 0)
                    $Visible = [int](Get-PropertyValue $T 'trackingVisibleTracks' (Get-PropertyValue $T 'stabilizedDetections' 0))
                    $Active = [int](Get-PropertyValue $T 'trackingActiveTracks' 0)
                    $Hidden = [int](Get-PropertyValue $T 'trackingHiddenMissedTracks' 0)
                    $Thermal = [string](Get-PropertyValue $T 'thermalState' '')
                    $Line = "{0:HH:mm:ss}  {1,5:N1} ms  {2,5:N1} Hz  mask {3,5:N1}%  ciel {4,5:N1}%  nuage {5,5:N1}%  tracks {6}/{7} hidden {8}  frames {9}  {10}" -f (Get-Date), $Pipeline, $Hz, $Mask, $Sky, $Cloud, $Visible, $Active, $Hidden, $DownloadedFrames.Count, $Thermal
                    Write-Host $Line
                }
            }
        } catch {
            Write-Host ("{0:HH:mm:ss}  API temporairement indisponible : {1}" -f (Get-Date), $_.Exception.Message) -ForegroundColor Yellow
        }

        Start-Sleep -Milliseconds $IntervalMilliseconds
    }
}
finally {
    Write-Host "`nSession diagnostic arrêtée." -ForegroundColor Cyan
    Write-Host "FRAMES      = $($DownloadedFrames.Count)"
    Write-Host "OUTPUT      = $OutDir" -ForegroundColor Green

    if ($MakeVideo -and $DownloadedFrames.Count -gt 1) {
        $Ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
        if ($null -ne $Ffmpeg) {
            $Concat = Join-Path $OutDir 'frames.ffconcat'
            $Video = Join-Path $OutDir 'diagnostic-preview.mp4'
            $Lines = @('ffconcat version 1.0')
            $FrameFiles = @(Get-ChildItem -LiteralPath $FramesDir -Filter 'frame-*.jpg' | Sort-Object Name)
            foreach ($Frame in $FrameFiles) {
                $Escaped = $Frame.FullName.Replace("'", "''")
                $Lines += "file '$Escaped'"
                $Lines += 'duration 0.25'
            }
            if ($FrameFiles.Count -gt 0) {
                $EscapedLast = $FrameFiles[-1].FullName.Replace("'", "''")
                $Lines += "file '$EscapedLast'"
            }
            $Lines | Set-Content -LiteralPath $Concat -Encoding UTF8
            & $Ffmpeg.Source -hide_banner -loglevel error -y -f concat -safe 0 -i $Concat -vf 'fps=4,format=yuv420p' -c:v libx264 -crf 28 $Video
            if ($LASTEXITCODE -eq 0) {
                Write-Host "VIDEO       = $Video" -ForegroundColor Green
                if (-not $KeepFrames) {
                    Remove-Item -LiteralPath $FramesDir -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath $Concat -Force -ErrorAction SilentlyContinue
                    Write-Host 'FRAMES      = supprimées après création MP4 réussie (utilise -KeepFrames pour les conserver)' -ForegroundColor DarkGray
                }
                Write-Host 'PARTAGE     = diagnostic-preview.mp4 + telemetry.ndjson/csv + status-latest.json + snapshots-latest.json' -ForegroundColor Cyan
            } else {
                Write-Host 'ffmpeg présent mais création MP4 échouée ; la séquence JPEG reste complète.' -ForegroundColor Yellow
            }
        } else {
            Write-Host 'ffmpeg non installé : pas de MP4, séquence JPEG conservée.' -ForegroundColor DarkYellow
        }
    }
}
