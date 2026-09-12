param(
    [switch]$Raw,
    [switch]$SnapshotsOnly
)

$ErrorActionPreference = 'Stop'

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

$RepoTop = (& git -C $PSScriptRoot rev-parse --show-toplevel).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($RepoTop)) {
    throw 'Impossible de résoudre le dépôt Watch Sensor Lab.'
}
$RepoContainer = Get-RepoContainer -RepoTop $RepoTop
$OutputRoot = Join-Path (Join-Path $RepoContainer 'artifacts\watch-sensor-lab') '_TELEMETRY'
$RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunRoot = Join-Path $OutputRoot $RunStamp
$EventsFile = Join-Path $RunRoot 'events.jsonl'
$LatestSnapshot = Join-Path $OutputRoot 'LATEST_SNAPSHOT.json'
$LatestEvent = Join-Path $OutputRoot 'LATEST_EVENT.json'
$LatestState = Join-Path $OutputRoot 'LATEST_STATE.json'

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$PythonCandidates = @(
    'E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv\Scripts\python.exe',
    'E:\_Project\IOS APP\_Tools\pymobiledevice3\.venv\Scripts\python.exe'
)

$Python = $PythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Python) {
    $PythonCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($PythonCommand) { $Python = $PythonCommand.Source }
}
if (-not $Python) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($PythonCommand) { $Python = $PythonCommand.Source }
}
if (-not $Python) {
    throw 'Python/pymobiledevice3 introuvable. Le venv attendu est E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv.'
}

$State = @{
    schema = 'watch_sensor_lab_host_state_v1'
    capture_started = (Get-Date).ToString('o')
    snapshots = @{}
}

$Marker = 'WSL_TELEMETRY|'
$ChunkMarker = 'WSL_TELEMETRY_CHUNK|'
$ChunkBuffers = @{}

function Process-TelemetryJson {
    param([Parameter(Mandatory)][string]$Json)

    try {
        $Record = $Json | ConvertFrom-Json
    }
    catch {
        Write-Host 'TELEMETRY PARSE ERROR: JSON réassemblé invalide' -ForegroundColor Red
        if ($Raw) { Write-Host $Json }
        return
    }

    $Canonical = $Record | ConvertTo-Json -Depth 64 -Compress
    Add-Content -LiteralPath $EventsFile -Value $Canonical -Encoding utf8
    Set-Content -LiteralPath $LatestEvent -Value ($Record | ConvertTo-Json -Depth 64) -Encoding utf8

    if ($Record.kind -eq 'snapshot') {
        Set-Content -LiteralPath $LatestSnapshot -Value ($Record | ConvertTo-Json -Depth 64) -Encoding utf8

        $Platform = if ($Record.platform) { [string]$Record.platform } else { 'unknown' }
        $Name = if ($Record.name) { [string]$Record.name } else { 'snapshot' }
        $SnapshotKey = "$Platform.$Name"
        $State.snapshots[$SnapshotKey] = $Record
        $State.updated_at = (Get-Date).ToString('o')
        $State.latest_snapshot_key = $SnapshotKey
        Set-Content -LiteralPath $LatestState -Value ($State | ConvertTo-Json -Depth 64) -Encoding utf8
    }

    if ($SnapshotsOnly -and $Record.kind -ne 'snapshot') { return }

    $Time = [string]$Record.timestamp
    if ($Time -and $Time.Length -ge 19) { $Time = $Time.Substring(11, 8) }
    $Screen = if ($Record.screen) { [string]$Record.screen } else { '-' }
    $Prefix = "[$Time] [$($Record.platform)] [$($Record.kind)] [$Screen] $($Record.name)"

    if ($Record.kind -eq 'snapshot' -and $Record.fields) {
        $F = $Record.fields
        $Phase = if ($null -ne $F.phase) { $F.phase } else { '-' }
        $Activity = if ($null -ne $F.effective_activity) { $F.effective_activity } else { '-' }
        $Session = if ($null -ne $F.session_id -and $F.session_id) { $F.session_id } else { '-' }
        $Distance = if ($null -ne $F.distance_m) { [Math]::Round([double]$F.distance_m, 1) } else { '-' }
        $Status = if ($null -ne $F.status_message) { $F.status_message } else { '-' }
        Write-Host "$Prefix | sha=$($Record.build_sha) phase=$Phase activity=$Activity session=$Session distance=${Distance}m | $Status" -ForegroundColor Green
    }
    elseif ($Record.kind -eq 'error') {
        Write-Host "$Prefix | sha=$($Record.build_sha)" -ForegroundColor Red
    }
    elseif ($Record.kind -eq 'action') {
        Write-Host "$Prefix | sha=$($Record.build_sha)" -ForegroundColor Yellow
    }
    else {
        Write-Host "$Prefix | sha=$($Record.build_sha)"
    }

    if ($Raw) { Write-Host ($Record | ConvertTo-Json -Depth 64) }
}

function Expire-StaleChunks {
    $Now = Get-Date
    foreach ($Key in @($ChunkBuffers.Keys)) {
        $Buffer = $ChunkBuffers[$Key]
        if (($Now - $Buffer.FirstSeen).TotalSeconds -gt 15) {
            $ChunkBuffers.Remove($Key)
            Write-Host "TELEMETRY CHUNK TIMEOUT: $Key" -ForegroundColor DarkYellow
        }
    }
}

Write-Host ''
Write-Host '=== WATCH SENSOR LAB - LIVE TELEMETRY ===' -ForegroundColor Cyan
Write-Host "PYTHON          = $Python"
Write-Host "EVENTS JSONL    = $EventsFile"
Write-Host "LATEST SNAPSHOT = $LatestSnapshot"
Write-Host "LATEST STATE    = $LatestState"
Write-Host 'USB             = garde l iPhone branché et l app ouverte'
Write-Host 'STOP            = Ctrl+C'
Write-Host ''

$Arguments = @('-m', 'pymobiledevice3', 'syslog', 'live', '-m', 'WSL_TELEMETRY')

& $Python @Arguments 2>&1 | ForEach-Object {
    $Line = [string]$_
    Expire-StaleChunks

    $ChunkIndex = $Line.IndexOf($ChunkMarker, [StringComparison]::Ordinal)
    if ($ChunkIndex -ge 0) {
        $Payload = $Line.Substring($ChunkIndex + $ChunkMarker.Length).Trim()
        $Parts = $Payload -split '\|', 4
        if ($Parts.Count -ne 4) {
            Write-Host "TELEMETRY CHUNK HEADER ERROR: $Line" -ForegroundColor Red
            return
        }

        $Index = 0
        $Total = 0
        if (-not [int]::TryParse($Parts[1], [ref]$Index) -or
            -not [int]::TryParse($Parts[2], [ref]$Total) -or
            $Index -lt 1 -or $Total -lt 1 -or $Index -gt $Total -or $Total -gt 512) {
            Write-Host "TELEMETRY CHUNK RANGE ERROR: $Line" -ForegroundColor Red
            return
        }

        $RecordID = $Parts[0]
        if (-not $ChunkBuffers.ContainsKey($RecordID)) {
            $ChunkBuffers[$RecordID] = [pscustomobject]@{
                Total = $Total
                FirstSeen = Get-Date
                Chunks = @{}
            }
        }

        $Buffer = $ChunkBuffers[$RecordID]
        if ($Buffer.Total -ne $Total) {
            $ChunkBuffers.Remove($RecordID)
            Write-Host "TELEMETRY CHUNK COUNT MISMATCH: $RecordID" -ForegroundColor Red
            return
        }

        $Buffer.Chunks[$Index] = $Parts[3]
        if ($Buffer.Chunks.Count -lt $Buffer.Total) { return }

        try {
            $Bytes = [System.Collections.Generic.List[byte]]::new()
            foreach ($PartNumber in 1..$Buffer.Total) {
                if (-not $Buffer.Chunks.ContainsKey($PartNumber)) {
                    throw "missing chunk $PartNumber"
                }
                $Decoded = [Convert]::FromBase64String([string]$Buffer.Chunks[$PartNumber])
                $Bytes.AddRange([byte[]]$Decoded)
            }
            $Json = [Text.Encoding]::UTF8.GetString($Bytes.ToArray())
            $ChunkBuffers.Remove($RecordID)
            Process-TelemetryJson -Json $Json
        }
        catch {
            $ChunkBuffers.Remove($RecordID)
            Write-Host "TELEMETRY CHUNK REASSEMBLY ERROR: $RecordID - $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }

    $MarkerIndex = $Line.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($MarkerIndex -lt 0) { return }

    $Json = $Line.Substring($MarkerIndex + $Marker.Length).Trim()
    $LastBrace = $Json.LastIndexOf('}')
    if ($LastBrace -ge 0) { $Json = $Json.Substring(0, $LastBrace + 1) }
    Process-TelemetryJson -Json $Json
}
