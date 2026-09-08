[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8787,

    [string]$BindAddress = '0.0.0.0',

    [string]$OutputRoot = '',

    [ValidateRange(2, 300)]
    [int]$ConsoleHeartbeatSeconds = 10,

    [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Invariant = [System.Globalization.CultureInfo]::InvariantCulture

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $OutputRoot = Join-Path $repoRoot 'telemetry-sessions'
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$sessionStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$sessionDirectory = Join-Path $OutputRoot $sessionStamp
if (Test-Path -LiteralPath $sessionDirectory) {
    $sessionDirectory = Join-Path $OutputRoot ($sessionStamp + '-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
}
New-Item -ItemType Directory -Path $sessionDirectory | Out-Null

$rawFile = Join-Path $sessionDirectory 'session.raw.jsonl'
$changesFile = Join-Path $sessionDirectory 'session.changes.log'
$summaryJsonFile = Join-Path $sessionDirectory 'session.summary.json'
$summaryTextFile = Join-Path $sessionDirectory 'session-summary.txt'
$latestSessionFile = Join-Path $OutputRoot 'LATEST_SESSION.txt'
$sessionDirectory | Set-Content -LiteralPath $latestSessionFile -Encoding utf8

$script:Stats = [ordered]@{
    StartedAt              = Get-Date
    EndedAt                = $null
    Packets                = 0
    Snapshots              = 0
    Events                 = 0
    InvalidPayloads        = 0
    Connections            = 0
    Disconnects            = 0
    ReceiverErrors         = 0
    MinFps                 = $null
    MaxFps                 = $null
    LowFpsSamples          = 0
    CriticalFpsSamples     = 0
    FirstGpsFix            = $null
    BestGpsAccuracyM       = $null
    WorstGpsAccuracyM      = $null
    LastGps                = $null
    TouchStart             = $null
    TouchEnd               = $null
    MaxAccelDeviation      = 0.0
    MaxGyroMagnitude       = 0.0
    LastBatteryPercent     = $null
    Build                  = $null
    Device                 = $null
    EventCounts            = @{}
    CameraEvents           = @()
    LastPage               = $null
    LastFps                = $null
}

$script:ConsoleState = [ordered]@{
    FirstSnapshot          = $true
    Page                   = ''
    FpsBand                = ''
    Battery                = $null
    GpsSeen                = $false
    GpsAccuracy            = $null
    LastHeartbeat          = Get-Date
    LastMotionNotice       = [DateTime]::MinValue
}

function Write-ChangeLine {
    param(
        [Parameter(Mandatory)][string]$Line,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Add-Content -LiteralPath $changesFile -Value $Line -Encoding utf8
    Write-Host $Line -ForegroundColor $Color
}

function Format-InvariantNumber {
    param([double]$Value, [string]$Format = '0.00')
    return [string]::Format($script:Invariant, "{0:$Format}", $Value)
}

function Read-ExactBytes {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][int]$Count
    )

    if ($Count -le 0) {
        return ,([byte[]]@())
    }

    $buffer = New-Object byte[] $Count
    $offset = 0
    while ($offset -lt $Count) {
        $read = $Stream.Read($buffer, $offset, $Count - $offset)
        if ($read -le 0) {
            throw [System.IO.EndOfStreamException]::new('Remote peer closed the stream.')
        }
        $offset += $read
    }
    return ,$buffer
}

function Read-HttpHeaderText {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $tail = [System.Collections.Generic.Queue[byte]]::new()

    while ($bytes.Count -lt 65536) {
        $one = Read-ExactBytes -Stream $Stream -Count 1
        $value = $one[0]
        $bytes.Add($value)
        $tail.Enqueue($value)
        while ($tail.Count -gt 4) {
            [void]$tail.Dequeue()
        }

        if ($tail.Count -eq 4) {
            $last = $tail.ToArray()
            if ($last[0] -eq 13 -and $last[1] -eq 10 -and $last[2] -eq 13 -and $last[3] -eq 10) {
                return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
            }
        }
    }

    throw 'HTTP header exceeded 64 KiB.'
}

function Parse-HttpHeader {
    param([Parameter(Mandatory)][string]$HeaderText)

    $lines = $HeaderText -split "`r`n"
    if ($lines.Count -lt 1) {
        throw 'Invalid HTTP request.'
    }

    $headers = @{}
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $separator = $line.IndexOf(':')
        if ($separator -le 0) {
            continue
        }
        $headers[$line.Substring(0, $separator).Trim()] = $line.Substring($separator + 1).Trim()
    }

    return [pscustomobject]@{
        RequestLine = $lines[0]
        Headers     = $headers
    }
}

function Convert-BytesToUInt16BE {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ne 2) { throw 'Expected 2 bytes.' }
    return ([uint16]$Bytes[0] -shl 8) -bor [uint16]$Bytes[1]
}

function Convert-BytesToUInt64BE {
    param([byte[]]$Bytes)
    if ($Bytes.Length -ne 8) { throw 'Expected 8 bytes.' }
    [uint64]$value = 0
    foreach ($byte in $Bytes) {
        $value = ($value -shl 8) -bor [uint64]$byte
    }
    return $value
}

function Read-WebSocketFrame {
    param([Parameter(Mandatory)][System.IO.Stream]$Stream)

    $head = Read-ExactBytes -Stream $Stream -Count 2
    $first = [int]$head[0]
    $second = [int]$head[1]
    $fin = (($first -band 0x80) -ne 0)
    $opcode = $first -band 0x0F
    $masked = (($second -band 0x80) -ne 0)
    [uint64]$length = $second -band 0x7F

    if ($length -eq 126) {
        $length = Convert-BytesToUInt16BE -Bytes (Read-ExactBytes -Stream $Stream -Count 2)
    }
    elseif ($length -eq 127) {
        $length = Convert-BytesToUInt64BE -Bytes (Read-ExactBytes -Stream $Stream -Count 8)
    }

    if ($length -gt 8MB) {
        throw "WebSocket payload too large: $length bytes"
    }

    $mask = $null
    if ($masked) {
        $mask = Read-ExactBytes -Stream $Stream -Count 4
    }

    $payload = Read-ExactBytes -Stream $Stream -Count ([int]$length)
    if ($masked) {
        for ($i = 0; $i -lt $payload.Length; $i++) {
            $payload[$i] = $payload[$i] -bxor $mask[$i % 4]
        }
    }

    return [pscustomobject]@{
        Fin     = $fin
        Opcode  = $opcode
        Payload = $payload
    }
}

function Send-WebSocketFrame {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][ValidateRange(0, 15)][int]$Opcode,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Payload
    )

    $header = [System.Collections.Generic.List[byte]]::new()
    $header.Add([byte](0x80 -bor $Opcode))
    [uint64]$length = $Payload.Length

    if ($length -lt 126) {
        $header.Add([byte]$length)
    }
    elseif ($length -le 65535) {
        $header.Add([byte]126)
        $header.Add([byte](($length -shr 8) -band 0xFF))
        $header.Add([byte]($length -band 0xFF))
    }
    else {
        $header.Add([byte]127)
        for ($shift = 56; $shift -ge 0; $shift -= 8) {
            $header.Add([byte](($length -shr $shift) -band 0xFF))
        }
    }

    $headerBytes = $header.ToArray()
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Payload.Length -gt 0) {
        $Stream.Write($Payload, 0, $Payload.Length)
    }
    $Stream.Flush()
}

function Send-WebSocketText {
    param(
        [Parameter(Mandatory)][System.IO.Stream]$Stream,
        [Parameter(Mandatory)][string]$Text
    )
    Send-WebSocketFrame -Stream $Stream -Opcode 1 -Payload ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-MapValue {
    param($Map, [string]$Key, $Default = $null)
    if ($Map -is [System.Collections.IDictionary] -and $Map.Contains($Key)) {
        return $Map[$Key]
    }
    return $Default
}

function Get-VectorMagnitude {
    param($Value)
    if ($null -eq $Value -or $Value.Count -lt 3) {
        return 0.0
    }
    $x = [double]$Value[0]
    $y = [double]$Value[1]
    $z = [double]$Value[2]
    return [Math]::Sqrt(($x * $x) + ($y * $y) + ($z * $z))
}

function Format-Vector3 {
    param($Value)
    if ($null -eq $Value -or $Value.Count -lt 3) {
        return '(—)'
    }
    return [string]::Format(
        $script:Invariant,
        '({0:0.00},{1:0.00},{2:0.00})',
        [double]$Value[0], [double]$Value[1], [double]$Value[2]
    )
}

function Get-FpsBand {
    param([double]$Fps)
    if ($Fps -lt 25) { return 'CRITICAL' }
    if ($Fps -lt 45) { return 'LOW' }
    if ($Fps -lt 55) { return 'MID' }
    return 'OK'
}

function Save-RawRecord {
    param([Parameter(Mandatory)][string]$Text)
    Add-Content -LiteralPath $rawFile -Value $Text -Encoding utf8
}

function Update-StatsFromSnapshot {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Record)

    $app = Get-MapValue -Map $Record -Key 'app' -Default @{}
    $device = Get-MapValue -Map $Record -Key 'device' -Default @{}
    $sensors = Get-MapValue -Map $Record -Key 'sensors' -Default @{}
    $touch = Get-MapValue -Map $Record -Key 'touch' -Default @{}
    $location = Get-MapValue -Map $Record -Key 'location' -Default @{}

    $fpsRaw = Get-MapValue -Map $app -Key 'fps' -Default $null
    if ($null -ne $fpsRaw) {
        $fps = [double]$fpsRaw
        $script:Stats.LastFps = $fps
        if ($null -eq $script:Stats.MinFps -or $fps -lt [double]$script:Stats.MinFps) {
            $script:Stats.MinFps = $fps
        }
        if ($null -eq $script:Stats.MaxFps -or $fps -gt [double]$script:Stats.MaxFps) {
            $script:Stats.MaxFps = $fps
        }
        if ($fps -lt 45) { $script:Stats.LowFpsSamples++ }
        if ($fps -lt 25) { $script:Stats.CriticalFpsSamples++ }
    }

    $page = [string](Get-MapValue -Map $app -Key 'page' -Default '')
    if (-not [string]::IsNullOrWhiteSpace($page)) {
        $script:Stats.LastPage = $page
    }

    $touchCount = Get-MapValue -Map $touch -Key 'count' -Default $null
    if ($null -ne $touchCount) {
        if ($null -eq $script:Stats.TouchStart) { $script:Stats.TouchStart = [int64]$touchCount }
        $script:Stats.TouchEnd = [int64]$touchCount
    }

    $battery = Get-MapValue -Map $device -Key 'battery_percent' -Default $null
    if ($null -ne $battery -and [int]$battery -ge 0) {
        $script:Stats.LastBatteryPercent = [int]$battery
    }

    $accel = Get-MapValue -Map $sensors -Key 'accelerometer' -Default $null
    $gyro = Get-MapValue -Map $sensors -Key 'gyroscope' -Default $null
    $accelDeviation = [Math]::Abs((Get-VectorMagnitude $accel) - 9.81)
    $gyroMagnitude = Get-VectorMagnitude $gyro
    if ($accelDeviation -gt [double]$script:Stats.MaxAccelDeviation) {
        $script:Stats.MaxAccelDeviation = $accelDeviation
    }
    if ($gyroMagnitude -gt [double]$script:Stats.MaxGyroMagnitude) {
        $script:Stats.MaxGyroMagnitude = $gyroMagnitude
    }

    if ([bool](Get-MapValue -Map $location -Key 'have_fix' -Default $false)) {
        $lat = [double](Get-MapValue -Map $location -Key 'latitude' -Default 0)
        $lon = [double](Get-MapValue -Map $location -Key 'longitude' -Default 0)
        $accuracy = [double](Get-MapValue -Map $location -Key 'accuracy_m' -Default 0)
        $gps = [ordered]@{
            Latitude = $lat
            Longitude = $lon
            AccuracyM = $accuracy
        }
        if ($null -eq $script:Stats.FirstGpsFix) {
            $script:Stats.FirstGpsFix = $gps
        }
        $script:Stats.LastGps = $gps
        if ($accuracy -ge 0) {
            if ($null -eq $script:Stats.BestGpsAccuracyM -or $accuracy -lt [double]$script:Stats.BestGpsAccuracyM) {
                $script:Stats.BestGpsAccuracyM = $accuracy
            }
            if ($null -eq $script:Stats.WorstGpsAccuracyM -or $accuracy -gt [double]$script:Stats.WorstGpsAccuracyM) {
                $script:Stats.WorstGpsAccuracyM = $accuracy
            }
        }
    }

    if ($null -eq $script:Stats.Build) {
        $build = Get-MapValue -Map $Record -Key 'build' -Default @{}
        if ($build -is [System.Collections.IDictionary]) {
            $script:Stats.Build = $build
        }
    }
    if ($null -eq $script:Stats.Device) {
        $script:Stats.Device = $device
    }
}

function Write-FilteredSnapshot {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Record)

    $app = Get-MapValue -Map $Record -Key 'app' -Default @{}
    $device = Get-MapValue -Map $Record -Key 'device' -Default @{}
    $sensors = Get-MapValue -Map $Record -Key 'sensors' -Default @{}
    $touch = Get-MapValue -Map $Record -Key 'touch' -Default @{}
    $location = Get-MapValue -Map $Record -Key 'location' -Default @{}
    $seq = Get-MapValue -Map $Record -Key 'seq' -Default '-'
    $stamp = Get-Date -Format 'HH:mm:ss.fff'

    $page = [string](Get-MapValue -Map $app -Key 'page' -Default '?')
    $fps = [double](Get-MapValue -Map $app -Key 'fps' -Default 0)
    $touchCount = [int64](Get-MapValue -Map $touch -Key 'count' -Default 0)
    $battery = [int](Get-MapValue -Map $device -Key 'battery_percent' -Default -1)
    $band = Get-FpsBand $fps

    $gpsText = 'GPS=—'
    $haveFix = [bool](Get-MapValue -Map $location -Key 'have_fix' -Default $false)
    $gpsAccuracy = $null
    if ($haveFix) {
        $lat = [double](Get-MapValue -Map $location -Key 'latitude' -Default 0)
        $lon = [double](Get-MapValue -Map $location -Key 'longitude' -Default 0)
        $gpsAccuracy = [double](Get-MapValue -Map $location -Key 'accuracy_m' -Default 0)
        $gpsText = [string]::Format($script:Invariant, 'GPS={0:F6},{1:F6} ±{2:F1}m', $lat, $lon, $gpsAccuracy)
    }

    if ($script:ConsoleState.FirstSnapshot) {
        $screen = Get-MapValue -Map $device -Key 'screen_px' -Default @()
        $screenText = if ($screen.Count -ge 2) { "$($screen[0])x$($screen[1])px" } else { '?' }
        $line = "[$stamp] START SNAP #$seq page=$page fps=$([int]$fps) touch=$touchCount $gpsText BAT=$battery% screen=$screenText"
        Write-ChangeLine -Line $line -Color Green
        $script:ConsoleState.FirstSnapshot = $false
        $script:ConsoleState.Page = $page
        $script:ConsoleState.FpsBand = $band
        $script:ConsoleState.Battery = $battery
        if ($haveFix) {
            $script:ConsoleState.GpsSeen = $true
            $script:ConsoleState.GpsAccuracy = $gpsAccuracy
        }
        return
    }

    if ($page -ne $script:ConsoleState.Page) {
        Write-ChangeLine -Line "[$stamp] PAGE $($script:ConsoleState.Page) -> $page" -Color Cyan
        $script:ConsoleState.Page = $page
    }

    if ($band -ne $script:ConsoleState.FpsBand) {
        $color = if ($band -eq 'CRITICAL') { [ConsoleColor]::Red } elseif ($band -eq 'LOW') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Green }
        Write-ChangeLine -Line "[$stamp] FPS $($script:ConsoleState.FpsBand) -> $band · fps=$([int]$fps)" -Color $color
        $script:ConsoleState.FpsBand = $band
    }

    if ($battery -ge 0 -and $battery -ne $script:ConsoleState.Battery) {
        Write-ChangeLine -Line "[$stamp] BATTERY $($script:ConsoleState.Battery)% -> $battery%" -Color DarkCyan
        $script:ConsoleState.Battery = $battery
    }

    if ($haveFix -and -not $script:ConsoleState.GpsSeen) {
        Write-ChangeLine -Line "[$stamp] GPS FIRST FIX · $gpsText" -Color Green
        $script:ConsoleState.GpsSeen = $true
        $script:ConsoleState.GpsAccuracy = $gpsAccuracy
    }
    elseif ($haveFix -and $null -ne $script:ConsoleState.GpsAccuracy) {
        $previousAccuracy = [double]$script:ConsoleState.GpsAccuracy
        if ([Math]::Abs($gpsAccuracy - $previousAccuracy) -ge 5.0) {
            Write-ChangeLine -Line "[$stamp] GPS ACCURACY $(Format-InvariantNumber $previousAccuracy '0.0')m -> $(Format-InvariantNumber $gpsAccuracy '0.0')m" -Color DarkCyan
            $script:ConsoleState.GpsAccuracy = $gpsAccuracy
        }
    }

    $accel = Get-MapValue -Map $sensors -Key 'accelerometer' -Default $null
    $gyro = Get-MapValue -Map $sensors -Key 'gyroscope' -Default $null
    $accelDeviation = [Math]::Abs((Get-VectorMagnitude $accel) - 9.81)
    $gyroMagnitude = Get-VectorMagnitude $gyro
    $now = Get-Date
    if (($accelDeviation -ge 4.0 -or $gyroMagnitude -ge 2.0) -and (($now - $script:ConsoleState.LastMotionNotice).TotalSeconds -ge 1.5)) {
        Write-ChangeLine -Line ("[$stamp] MOTION peak accelΔ={0}m/s² gyro={1}rad/s ACC={2} GYRO={3}" -f (Format-InvariantNumber $accelDeviation), (Format-InvariantNumber $gyroMagnitude), (Format-Vector3 $accel), (Format-Vector3 $gyro)) -Color Magenta
        $script:ConsoleState.LastMotionNotice = $now
    }

    if (($now - $script:ConsoleState.LastHeartbeat).TotalSeconds -ge $ConsoleHeartbeatSeconds) {
        $heartbeatGps = if ($haveFix) { $gpsText } else { 'GPS=—' }
        Write-ChangeLine -Line "[$stamp] HEARTBEAT packets=$($script:Stats.Packets) fps=$([int]$fps) page=$page touch=$touchCount $heartbeatGps" -Color DarkGray
        $script:ConsoleState.LastHeartbeat = $now
    }
}

function Write-EventRecord {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Record)

    $event = Get-MapValue -Map $Record -Key 'event' -Default @{}
    $kind = [string](Get-MapValue -Map $event -Key 'kind' -Default 'event')
    $message = [string](Get-MapValue -Map $event -Key 'message' -Default '')
    $data = Get-MapValue -Map $event -Key 'data' -Default @{}
    $seq = Get-MapValue -Map $Record -Key 'seq' -Default '-'
    $stamp = Get-Date -Format 'HH:mm:ss.fff'

    if (-not $script:Stats.EventCounts.ContainsKey($kind)) {
        $script:Stats.EventCounts[$kind] = 0
    }
    $script:Stats.EventCounts[$kind] = [int]$script:Stats.EventCounts[$kind] + 1

    if ($kind.StartsWith('camera_')) {
        $script:Stats.CameraEvents += [ordered]@{
            Time = $stamp
            Kind = $kind
            Message = $message
            Data = $data
        }
    }

    $dataText = ''
    if ($data -is [System.Collections.IDictionary] -and $data.Count -gt 0) {
        $dataText = ' · ' + ($data | ConvertTo-Json -Compress -Depth 20)
    }
    Write-ChangeLine -Line "[$stamp] EVENT #$seq $kind :: $message$dataText" -Color Cyan
}

function Convert-RecordToAckJson {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Record)

    return (@{
        type           = 'ack'
        seq            = [int64](Get-MapValue -Map $Record -Key 'seq' -Default -1)
        server_unix_ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    } | ConvertTo-Json -Compress)
}

function Process-TelemetryText {
    param([Parameter(Mandatory)][string]$Text)

    Save-RawRecord -Text $Text

    try {
        $record = $Text | ConvertFrom-Json -AsHashtable -Depth 32
    }
    catch {
        $script:Stats.InvalidPayloads++
        Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] INVALID JSON" -Color Yellow
        return $null
    }

    if ($record -isnot [System.Collections.IDictionary]) {
        $script:Stats.InvalidPayloads++
        Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] INVALID PAYLOAD · JSON root is not an object" -Color Yellow
        return $null
    }

    $script:Stats.Packets++
    $type = [string](Get-MapValue -Map $record -Key 'type' -Default 'unknown')

    if ($Raw) {
        Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] $Text"
    }

    switch ($type) {
        'snapshot' {
            $script:Stats.Snapshots++
            Update-StatsFromSnapshot -Record $record
            if (-not $Raw) {
                Write-FilteredSnapshot -Record $record
            }
        }
        'event' {
            $script:Stats.Events++
            Write-EventRecord -Record $record
        }
        default {
            Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] PACKET type=$type" -Color DarkGray
        }
    }

    return Convert-RecordToAckJson -Record $record
}

function Get-TailscaleIPv4 {
    $commandPath = $null
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) {
        $commandPath = $command.Source
    }
    elseif ($env:ProgramFiles) {
        $candidate = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        if (Test-Path -LiteralPath $candidate) {
            $commandPath = $candidate
        }
    }

    if (-not $commandPath) {
        return $null
    }

    try {
        $value = (& $commandPath ip -4 2>$null | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
    catch {
    }

    return $null
}

function Show-ListeningEndpoints {
    param([int]$ListenPort)

    Write-Host ''
    Write-Host '=== IOSLAB LIVE TELEMETRY RECEIVER ===' -ForegroundColor Cyan
    Write-Host "LISTENING TCP = $BindAddress`:$ListenPort"
    Write-Host "SESSION DIR   = $sessionDirectory" -ForegroundColor Green
    Write-Host "SUMMARY       = $summaryTextFile"
    Write-Host "CHANGES       = $changesFile"
    Write-Host "RAW JSONL     = $rawFile"

    $tailscaleIp = Get-TailscaleIPv4
    if ($tailscaleIp) {
        Write-Host "TAILSCALE WS   = ws://${tailscaleIp}:$ListenPort/telemetry" -ForegroundColor Green
        Write-Host "TAILSCALE HTTP = http://${tailscaleIp}:$ListenPort/telemetry"
    }

    if ($IsWindows) {
        try {
            $localIps = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
                Where-Object {
                    $_.IPAddress -ne '127.0.0.1' -and
                    -not $_.IPAddress.StartsWith('169.254.')
                } |
                Select-Object -ExpandProperty IPAddress -Unique

            foreach ($ip in $localIps) {
                if ($ip -eq $tailscaleIp) {
                    continue
                }
                Write-Host "LAN WS         = ws://${ip}:$ListenPort/telemetry"
            }
        }
        catch {
        }
    }

    Write-Host ''
    Write-Host 'Console mode: meaningful changes/events only + heartbeat.' -ForegroundColor DarkGray
    Write-Host 'Full snapshots are still preserved in session.raw.jsonl.' -ForegroundColor DarkGray
    Write-Host 'Ctrl+C stops the receiver and finalizes session-summary.txt.'
    Write-Host ''
}

function Complete-Session {
    $script:Stats.EndedAt = Get-Date
    $duration = [Math]::Round(($script:Stats.EndedAt - $script:Stats.StartedAt).TotalSeconds, 2)
    $touchDelta = if ($null -ne $script:Stats.TouchStart -and $null -ne $script:Stats.TouchEnd) {
        [int64]$script:Stats.TouchEnd - [int64]$script:Stats.TouchStart
    }
    else {
        0
    }

    $summary = [ordered]@{
        schema                 = 'ioslab.receiver.summary.v1'
        started_at             = $script:Stats.StartedAt.ToString('o')
        ended_at               = $script:Stats.EndedAt.ToString('o')
        duration_seconds       = $duration
        packets                = $script:Stats.Packets
        snapshots              = $script:Stats.Snapshots
        events                 = $script:Stats.Events
        invalid_payloads       = $script:Stats.InvalidPayloads
        receiver_errors        = $script:Stats.ReceiverErrors
        connections            = $script:Stats.Connections
        disconnects            = $script:Stats.Disconnects
        fps                    = [ordered]@{
            min = $script:Stats.MinFps
            max = $script:Stats.MaxFps
            last = $script:Stats.LastFps
            low_samples_below_45 = $script:Stats.LowFpsSamples
            critical_samples_below_25 = $script:Stats.CriticalFpsSamples
        }
        gps                    = [ordered]@{
            first_fix = $script:Stats.FirstGpsFix
            last_fix = $script:Stats.LastGps
            best_accuracy_m = $script:Stats.BestGpsAccuracyM
            worst_accuracy_m = $script:Stats.WorstGpsAccuracyM
        }
        touch                  = [ordered]@{
            first_count = $script:Stats.TouchStart
            last_count = $script:Stats.TouchEnd
            delta = $touchDelta
        }
        motion                 = [ordered]@{
            max_accel_deviation_from_gravity = [Math]::Round([double]$script:Stats.MaxAccelDeviation, 3)
            max_gyro_magnitude = [Math]::Round([double]$script:Stats.MaxGyroMagnitude, 3)
        }
        battery_percent_last   = $script:Stats.LastBatteryPercent
        last_page              = $script:Stats.LastPage
        event_counts           = $script:Stats.EventCounts
        camera_events          = $script:Stats.CameraEvents
        build                  = $script:Stats.Build
        device                 = $script:Stats.Device
        files                  = [ordered]@{
            summary_text = $summaryTextFile
            summary_json = $summaryJsonFile
            changes_log = $changesFile
            raw_jsonl = $rawFile
        }
    }

    $summary | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $summaryJsonFile -Encoding utf8

    $minFpsText = if ($null -eq $script:Stats.MinFps) { '—' } else { Format-InvariantNumber ([double]$script:Stats.MinFps) '0' }
    $maxFpsText = if ($null -eq $script:Stats.MaxFps) { '—' } else { Format-InvariantNumber ([double]$script:Stats.MaxFps) '0' }
    $bestGpsText = if ($null -eq $script:Stats.BestGpsAccuracyM) { '—' } else { (Format-InvariantNumber ([double]$script:Stats.BestGpsAccuracyM) '0.0') + ' m' }
    $buildSha = '—'
    if ($script:Stats.Build -is [System.Collections.IDictionary]) {
        $buildSha = [string](Get-MapValue -Map $script:Stats.Build -Key 'git_sha' -Default '—')
    }

    $lines = @(
        'IOSLAB TELEMETRY SESSION SUMMARY'
        '================================'
        "Build SHA          : $buildSha"
        "Started            : $($script:Stats.StartedAt.ToString('o'))"
        "Duration           : $duration s"
        "Packets            : $($script:Stats.Packets) ($($script:Stats.Snapshots) snapshots / $($script:Stats.Events) events)"
        "Connections        : $($script:Stats.Connections)"
        "Receiver errors    : $($script:Stats.ReceiverErrors)"
        "FPS min / max      : $minFpsText / $maxFpsText"
        "FPS < 45 samples   : $($script:Stats.LowFpsSamples)"
        "FPS < 25 samples   : $($script:Stats.CriticalFpsSamples)"
        "GPS best accuracy  : $bestGpsText"
        "Touch delta        : $touchDelta"
        "Max accel delta    : $(Format-InvariantNumber ([double]$script:Stats.MaxAccelDeviation) '0.00') m/s²"
        "Max gyro magnitude : $(Format-InvariantNumber ([double]$script:Stats.MaxGyroMagnitude) '0.00') rad/s"
        "Last page          : $($script:Stats.LastPage)"
        "Camera events      : $($script:Stats.CameraEvents.Count)"
        ''
        'FILES TO SHARE WITH CHATGPT'
        '----------------------------'
        "1. $summaryTextFile"
        "2. $changesFile"
        "3. $summaryJsonFile"
        "4. $rawFile  (only if deep raw analysis is needed)"
    )
    $lines | Set-Content -LiteralPath $summaryTextFile -Encoding utf8

    try {
        Write-Host ''
        Write-Host '=== IOSLAB SESSION FINALIZED ===' -ForegroundColor Green
        Write-Host "SUMMARY = $summaryTextFile" -ForegroundColor Green
        Write-Host "CHANGES = $changesFile"
        Write-Host "RAW     = $rawFile" -ForegroundColor DarkGray
        Write-Host 'Send session-summary.txt first; add session.changes.log if needed.' -ForegroundColor Cyan
    }
    catch {
    }
}

$ipAddress = if ($BindAddress -eq '0.0.0.0' -or $BindAddress -eq '*') {
    [System.Net.IPAddress]::Any
}
else {
    [System.Net.IPAddress]::Parse($BindAddress)
}

$listener = [System.Net.Sockets.TcpListener]::new($ipAddress, $Port)

try {
    $listener.Start()
    Show-ListeningEndpoints -ListenPort $Port

    while ($true) {
        $client = $listener.AcceptTcpClient()
        $remote = $client.Client.RemoteEndPoint
        $script:Stats.Connections++
        Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] CONNECT $remote" -Color DarkCyan

        try {
            $client.NoDelay = $true
            $stream = $client.GetStream()
            $request = Parse-HttpHeader -HeaderText (Read-HttpHeaderText -Stream $stream)
            $headers = $request.Headers

            $upgrade = if ($headers.ContainsKey('Upgrade')) { [string]$headers['Upgrade'] } else { '' }

            if ($upgrade -ieq 'websocket') {
                if (-not $headers.ContainsKey('Sec-WebSocket-Key')) {
                    throw 'WebSocket handshake is missing Sec-WebSocket-Key.'
                }

                $key = [string]$headers['Sec-WebSocket-Key']
                $source = [System.Text.Encoding]::ASCII.GetBytes($key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')
                $sha1 = [System.Security.Cryptography.SHA1]::Create()
                try {
                    $accept = [Convert]::ToBase64String($sha1.ComputeHash($source))
                }
                finally {
                    $sha1.Dispose()
                }

                $response = "HTTP/1.1 101 Switching Protocols`r`nUpgrade: websocket`r`nConnection: Upgrade`r`nSec-WebSocket-Accept: $accept`r`n`r`n"
                $responseBytes = [System.Text.Encoding]::ASCII.GetBytes($response)
                $stream.Write($responseBytes, 0, $responseBytes.Length)
                $stream.Flush()
                Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] WEBSOCKET OPEN $remote" -Color Green

                while ($client.Connected) {
                    $frame = Read-WebSocketFrame -Stream $stream
                    if (-not $frame.Fin) {
                        Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] WARN fragmented WebSocket frame ignored" -Color Yellow
                        continue
                    }

                    switch ($frame.Opcode) {
                        1 {
                            $text = [System.Text.Encoding]::UTF8.GetString($frame.Payload)
                            $ack = Process-TelemetryText -Text $text
                            if ($ack) {
                                Send-WebSocketText -Stream $stream -Text $ack
                            }
                        }
                        8 {
                            Send-WebSocketFrame -Stream $stream -Opcode 8 -Payload ([byte[]]@())
                        }
                        9 {
                            Send-WebSocketFrame -Stream $stream -Opcode 10 -Payload $frame.Payload
                        }
                    }

                    if ($frame.Opcode -eq 8) {
                        break
                    }
                }
            }
            else {
                $contentLength = if ($headers.ContainsKey('Content-Length')) { [int]$headers['Content-Length'] } else { 0 }
                $bodyBytes = Read-ExactBytes -Stream $stream -Count $contentLength
                $text = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
                $ack = Process-TelemetryText -Text $text
                if (-not $ack) {
                    $ack = '{"type":"error","message":"invalid telemetry payload"}'
                }

                $ackBytes = [System.Text.Encoding]::UTF8.GetBytes($ack)
                $httpResponse = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($ackBytes.Length)`r`nConnection: close`r`n`r`n"
                $httpHeaderBytes = [System.Text.Encoding]::ASCII.GetBytes($httpResponse)
                $stream.Write($httpHeaderBytes, 0, $httpHeaderBytes.Length)
                $stream.Write($ackBytes, 0, $ackBytes.Length)
                $stream.Flush()
            }
        }
        catch [System.IO.EndOfStreamException] {
            $script:Stats.Disconnects++
            Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] DISCONNECT $remote" -Color DarkGray
        }
        catch {
            $script:Stats.ReceiverErrors++
            Write-ChangeLine -Line "[$(Get-Date -Format 'HH:mm:ss.fff')] RECEIVER ERROR $remote :: $($_.Exception.Message)" -Color Red
        }
        finally {
            $client.Close()
            $client.Dispose()
        }
    }
}
finally {
    try { $listener.Stop() } catch {}
    Complete-Session
}
