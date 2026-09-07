[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8787,

    [string]$BindAddress = '0.0.0.0',

    [switch]$Raw
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-ExactBytes {
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [int]$Count
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
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream
    )

    $bytes = [System.Collections.Generic.List[byte]]::new()
    $window = [System.Collections.Generic.Queue[byte]]::new()

    while ($bytes.Count -lt 65536) {
        $one = Read-ExactBytes -Stream $Stream -Count 1
        $value = $one[0]
        $bytes.Add($value)
        $window.Enqueue($value)
        while ($window.Count -gt 4) {
            [void]$window.Dequeue()
        }

        if ($window.Count -eq 4) {
            $tail = $window.ToArray()
            if ($tail[0] -eq 13 -and $tail[1] -eq 10 -and $tail[2] -eq 13 -and $tail[3] -eq 10) {
                return [System.Text.Encoding]::ASCII.GetString($bytes.ToArray())
            }
        }
    }

    throw 'HTTP header exceeded 64 KiB.'
}

function Parse-HttpHeader {
    param(
        [Parameter(Mandatory)]
        [string]$HeaderText
    )

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

        $name = $line.Substring(0, $separator).Trim()
        $value = $line.Substring($separator + 1).Trim()
        $headers[$name] = $value
    }

    return [pscustomobject]@{
        RequestLine = $lines[0]
        Headers     = $headers
    }
}

function Convert-BytesToUInt16BE {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ne 2) {
        throw 'Expected exactly 2 bytes.'
    }

    return ([uint16]$Bytes[0] -shl 8) -bor [uint16]$Bytes[1]
}

function Convert-BytesToUInt64BE {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ne 8) {
        throw 'Expected exactly 8 bytes.'
    }

    [uint64]$value = 0
    foreach ($byte in $Bytes) {
        $value = ($value -shl 8) -bor [uint64]$byte
    }
    return $value
}

function Read-WebSocketFrame {
    param(
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream
    )

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
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [ValidateRange(0, 15)]
        [int]$Opcode,

        [Parameter(Mandatory)]
        [byte[]]$Payload
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
        [Parameter(Mandatory)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory)]
        [string]$Text
    )

    $payload = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-WebSocketFrame -Stream $Stream -Opcode 1 -Payload $payload
}

function Get-MapValue {
    param(
        $Map,
        [string]$Key,
        $Default = $null
    )

    if ($Map -is [System.Collections.IDictionary] -and $Map.Contains($Key)) {
        return $Map[$Key]
    }

    return $Default
}

function Format-Vector3 {
    param($Value)

    if ($null -eq $Value -or $Value.Count -lt 3) {
        return '(—)'
    }

    return '({0:N2},{1:N2},{2:N2})' -f [double]$Value[0], [double]$Value[1], [double]$Value[2]
}

function Write-TelemetryRecord {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Record,

        [string]$RawText = ''
    )

    $stamp = Get-Date -Format 'HH:mm:ss.fff'

    if ($Raw) {
        Write-Host "[$stamp] $RawText"
        return
    }

    $type = [string](Get-MapValue -Map $Record -Key 'type' -Default 'unknown')
    $seq = Get-MapValue -Map $Record -Key 'seq' -Default '-'

    switch ($type) {
        'snapshot' {
            $app = Get-MapValue -Map $Record -Key 'app' -Default @{}
            $device = Get-MapValue -Map $Record -Key 'device' -Default @{}
            $sensors = Get-MapValue -Map $Record -Key 'sensors' -Default @{}
            $touch = Get-MapValue -Map $Record -Key 'touch' -Default @{}
            $location = Get-MapValue -Map $Record -Key 'location' -Default @{}

            $page = Get-MapValue -Map $app -Key 'page' -Default '?'
            $fps = Get-MapValue -Map $app -Key 'fps' -Default '?'
            $touchCount = Get-MapValue -Map $touch -Key 'count' -Default 0
            $battery = Get-MapValue -Map $device -Key 'battery_percent' -Default -1
            $accel = Format-Vector3 (Get-MapValue -Map $sensors -Key 'accelerometer')
            $gyro = Format-Vector3 (Get-MapValue -Map $sensors -Key 'gyroscope')

            $gps = 'GPS=—'
            $haveFix = [bool](Get-MapValue -Map $location -Key 'have_fix' -Default $false)
            if ($haveFix) {
                $lat = [double](Get-MapValue -Map $location -Key 'latitude' -Default 0)
                $lon = [double](Get-MapValue -Map $location -Key 'longitude' -Default 0)
                $acc = [double](Get-MapValue -Map $location -Key 'accuracy_m' -Default 0)
                $gps = 'GPS={0:F6},{1:F6} ±{2:N1}m' -f $lat, $lon, $acc
            }

            $batteryText = if ([int]$battery -ge 0) { "BAT=$battery%" } else { 'BAT=—' }
            Write-Host ("[{0}] SNAP #{1} page={2} fps={3} touch={4} ACC={5} GYRO={6} {7} {8}" -f $stamp, $seq, $page, $fps, $touchCount, $accel, $gyro, $gps, $batteryText)
        }

        'event' {
            $event = Get-MapValue -Map $Record -Key 'event' -Default @{}
            $kind = Get-MapValue -Map $event -Key 'kind' -Default 'event'
            $message = Get-MapValue -Map $event -Key 'message' -Default ''
            Write-Host ("[{0}] EVENT #{1} {2} :: {3}" -f $stamp, $seq, $kind, $message) -ForegroundColor Cyan
        }

        default {
            Write-Host ("[{0}] {1} #{2}" -f $stamp, $type.ToUpperInvariant(), $seq)
        }
    }
}

function Convert-RecordToAckJson {
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$Record
    )

    $seq = [int64](Get-MapValue -Map $Record -Key 'seq' -Default -1)
    $unixMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

    return (@{
        type           = 'ack'
        seq            = $seq
        server_unix_ms = $unixMs
    } | ConvertTo-Json -Compress)
}

function Process-TelemetryText {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    try {
        $record = $Text | ConvertFrom-Json -AsHashtable -Depth 32
    }
    catch {
        Write-Host "[INVALID JSON] $Text" -ForegroundColor Yellow
        return $null
    }

    if ($record -isnot [System.Collections.IDictionary]) {
        Write-Host '[INVALID PAYLOAD] JSON root is not an object.' -ForegroundColor Yellow
        return $null
    }

    Write-TelemetryRecord -Record $record -RawText $Text
    return Convert-RecordToAckJson -Record $record
}

function Get-TailscaleIPv4 {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        $candidate = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
        if (Test-Path -LiteralPath $candidate) {
            $command = Get-Item -LiteralPath $candidate
        }
    }

    if ($null -eq $command) {
        return $null
    }

    try {
        $value = (& $command.Source ip -4 2>$null | Select-Object -First 1)
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

    $tailscaleIp = Get-TailscaleIPv4
    if ($tailscaleIp) {
        Write-Host "TAILSCALE WS   = ws://${tailscaleIp}:$ListenPort/telemetry" -ForegroundColor Green
        Write-Host "TAILSCALE HTTP = http://${tailscaleIp}:$ListenPort/telemetry"
    }

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

    Write-Host ''
    Write-Host 'In the iPhone app: Telemetry > WebSocket > enter host:port > START STREAM.'
    Write-Host 'Ctrl+C stops the receiver.'
    Write-Host ''
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
        Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] CONNECT $remote" -ForegroundColor DarkCyan

        try {
            $client.NoDelay = $true
            $stream = $client.GetStream()
            $headerText = Read-HttpHeaderText -Stream $stream
            $request = Parse-HttpHeader -HeaderText $headerText
            $headers = $request.Headers

            $upgrade = ''
            if ($headers.ContainsKey('Upgrade')) {
                $upgrade = [string]$headers['Upgrade']
            }

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

                Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] WEBSOCKET OPEN $remote" -ForegroundColor Green

                while ($client.Connected) {
                    $frame = Read-WebSocketFrame -Stream $stream

                    if (-not $frame.Fin) {
                        Write-Host '[WARN] Fragmented WebSocket frames are not expected from IOSLab and are ignored.' -ForegroundColor Yellow
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
                            break
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
                $contentLength = 0
                if ($headers.ContainsKey('Content-Length')) {
                    $contentLength = [int]$headers['Content-Length']
                }

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
            Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] DISCONNECT $remote" -ForegroundColor DarkGray
        }
        catch {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss.fff')] ERROR $remote :: $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            $client.Close()
            $client.Dispose()
        }
    }
}
finally {
    $listener.Stop()
}
