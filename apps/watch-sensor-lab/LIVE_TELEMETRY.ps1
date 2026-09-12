param(
    [switch]$Raw,
    [switch]$SnapshotsOnly
)

$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$OutputRoot = Join-Path $RepoRoot 'artifacts\watch-sensor-lab\_TELEMETRY'
$RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$RunRoot = Join-Path $OutputRoot $RunStamp
$EventsFile = Join-Path $RunRoot 'events.jsonl'
$LatestSnapshot = Join-Path $OutputRoot 'LATEST_SNAPSHOT.json'
$LatestEvent = Join-Path $OutputRoot 'LATEST_EVENT.json'

New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$PythonCandidates = @(
    'E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv\Scripts\python.exe',
    'E:\_Project\IOS APP\_Tools\pymobiledevice3\.venv\Scripts\python.exe'
)

$Python = $PythonCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Python) {
    $PythonCommand = Get-Command py -ErrorAction SilentlyContinue
    if ($PythonCommand) {
        $Python = $PythonCommand.Source
    }
}
if (-not $Python) {
    $PythonCommand = Get-Command python -ErrorAction SilentlyContinue
    if ($PythonCommand) {
        $Python = $PythonCommand.Source
    }
}
if (-not $Python) {
    throw 'Python/pymobiledevice3 introuvable. Le venv attendu est E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv.'
}

Write-Host ''
Write-Host '=== WATCH SENSOR LAB - LIVE TELEMETRY ===' -ForegroundColor Cyan
Write-Host "PYTHON          = $Python"
Write-Host "EVENTS JSONL    = $EventsFile"
Write-Host "LATEST SNAPSHOT = $LatestSnapshot"
Write-Host 'USB             = garde l’iPhone branché et l’app ouverte'
Write-Host 'STOP            = Ctrl+C'
Write-Host ''

$Marker = 'WSL_TELEMETRY|'
$Arguments = @('-m', 'pymobiledevice3', 'syslog', 'live', '-m', 'WSL_TELEMETRY')

& $Python @Arguments 2>&1 | ForEach-Object {
    $Line = [string]$_
    $MarkerIndex = $Line.IndexOf($Marker, [StringComparison]::Ordinal)
    if ($MarkerIndex -lt 0) {
        return
    }

    $Json = $Line.Substring($MarkerIndex + $Marker.Length).Trim()
    $LastBrace = $Json.LastIndexOf('}')
    if ($LastBrace -ge 0) {
        $Json = $Json.Substring(0, $LastBrace + 1)
    }

    try {
        $Record = $Json | ConvertFrom-Json -Depth 64
    }
    catch {
        Write-Host "TELEMETRY PARSE ERROR: $Line" -ForegroundColor Red
        return
    }

    $Canonical = $Record | ConvertTo-Json -Depth 64 -Compress
    Add-Content -LiteralPath $EventsFile -Value $Canonical -Encoding utf8
    Set-Content -LiteralPath $LatestEvent -Value ($Record | ConvertTo-Json -Depth 64) -Encoding utf8

    if ($Record.kind -eq 'snapshot') {
        Set-Content -LiteralPath $LatestSnapshot -Value ($Record | ConvertTo-Json -Depth 64) -Encoding utf8
    }

    if ($SnapshotsOnly -and $Record.kind -ne 'snapshot') {
        return
    }

    $Time = $Record.timestamp
    if ($Time -and $Time.Length -ge 19) {
        $Time = $Time.Substring(11, 8)
    }
    $Screen = if ($Record.screen) { [string]$Record.screen } else { '-' }
    $Prefix = "[$Time] [$($Record.platform)] [$($Record.kind)] [$Screen] $($Record.name)"

    if ($Record.kind -eq 'snapshot' -and $Record.fields) {
        $F = $Record.fields
        $Phase = if ($null -ne $F.phase) { $F.phase } else { '-' }
        $Activity = if ($null -ne $F.effective_activity) { $F.effective_activity } else { '-' }
        $Session = if ($null -ne $F.session_id -and $F.session_id) { $F.session_id } else { '-' }
        $Distance = if ($null -ne $F.distance_m) { [Math]::Round([double]$F.distance_m, 1) } else { '-' }
        $Status = if ($null -ne $F.status_message) { $F.status_message } else { '-' }
        Write-Host "$Prefix | phase=$Phase activity=$Activity session=$Session distance=${Distance}m | $Status" -ForegroundColor Green
    }
    elseif ($Record.kind -eq 'error') {
        Write-Host $Prefix -ForegroundColor Red
    }
    elseif ($Record.kind -eq 'action') {
        Write-Host $Prefix -ForegroundColor Yellow
    }
    else {
        Write-Host $Prefix
    }

    if ($Raw) {
        Write-Host ($Record | ConvertTo-Json -Depth 64)
    }
}
