[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('run', 'ping')]
    [string]$Command = 'run',

    [string]$ExpectedBuildSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DevicePort = 37992
$ProtocolName = 'wsl_selftest_v1'

function Resolve-Python {
    $Candidates = @(
        'E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv\Scripts\python.exe',
        'E:\_Project\IOS APP\_Tools\pymobiledevice3\.venv\Scripts\python.exe'
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    foreach ($Name in @('py', 'python')) {
        $Info = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $Info) {
            return $Info.Source
        }
    }

    throw 'Python/pymobiledevice3 introuvable.'
}

function Get-FreeTcpPort {
    $Listener = [System.Net.Sockets.TcpListener]::new(
        [System.Net.IPAddress]::Loopback,
        0
    )
    try {
        $Listener.Start()
        return ([System.Net.IPEndPoint]$Listener.LocalEndpoint).Port
    }
    finally {
        $Listener.Stop()
    }
}

function Connect-SelfTestPort {
    param(
        [int]$Port,
        [System.Diagnostics.Process]$ForwardProcess
    )

    for ($Attempt = 0; $Attempt -lt 50; $Attempt++) {
        if ($ForwardProcess.HasExited) {
            return $null
        }

        $Candidate = [System.Net.Sockets.TcpClient]::new()
        try {
            $Task = $Candidate.ConnectAsync('127.0.0.1', $Port)
            if ($Task.Wait(200) -and $Candidate.Connected) {
                return $Candidate
            }
        }
        catch {
            # usbmux may still be establishing the forward.
        }

        $Candidate.Dispose()
        Start-Sleep -Milliseconds 100
    }

    return $null
}

$Python = Resolve-Python
$HostPort = Get-FreeTcpPort
$TempBase = Join-Path $env:TEMP ("wsl-selftest-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$ForwardStdout = "$TempBase.out.log"
$ForwardStderr = "$TempBase.err.log"
$Forward = $null
$Client = $null
$Reader = $null
$Writer = $null

try {
    $Arguments = @(
        '-m', 'pymobiledevice3',
        'usbmux', 'forward',
        [string]$HostPort,
        [string]$DevicePort
    )

    $Forward = Start-Process `
        -FilePath $Python `
        -ArgumentList $Arguments `
        -PassThru `
        -WindowStyle Hidden `
        -RedirectStandardOutput $ForwardStdout `
        -RedirectStandardError $ForwardStderr

    $Client = Connect-SelfTestPort -Port $HostPort -ForwardProcess $Forward
    if ($null -eq $Client) {
        $Details = ''
        if (Test-Path -LiteralPath $ForwardStderr) {
            $Details = (Get-Content -LiteralPath $ForwardStderr -Raw -ErrorAction SilentlyContinue).Trim()
        }
        if ($Details) {
            throw "Impossible de joindre le self-test USB. $Details"
        }
        throw "Impossible de joindre le self-test USB. Garde l'iPhone branché, déverrouillé et Watch Tracker ouvert au premier plan."
    }

    $Stream = $Client.GetStream()
    $Stream.ReadTimeout = 20000
    $Stream.WriteTimeout = 5000
    $Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $Writer = [System.IO.StreamWriter]::new($Stream, $Utf8NoBom, 4096, $true)
    $Reader = [System.IO.StreamReader]::new($Stream, [System.Text.Encoding]::UTF8, $false, 4096, $true)
    $Writer.NewLine = "`n"
    $Writer.AutoFlush = $true

    $Request = [ordered]@{
        protocol = $ProtocolName
        command  = $Command
    }
    $Writer.WriteLine(($Request | ConvertTo-Json -Compress))

    $ResponseLine = $Reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($ResponseLine)) {
        throw 'Le self-test a fermé la connexion sans réponse.'
    }

    $Response = $ResponseLine | ConvertFrom-Json

    if (-not [string]::IsNullOrWhiteSpace($ExpectedBuildSha)) {
        $ExpectedShort = if ($ExpectedBuildSha.Length -gt 12) {
            $ExpectedBuildSha.Substring(0, 12)
        }
        else {
            $ExpectedBuildSha
        }
        if ([string]$Response.build_sha -ne $ExpectedShort) {
            throw "STOP: mauvais build sur l'iPhone. Attendu=$ExpectedShort / trouvé=$($Response.build_sha)"
        }
    }

    Write-Host ''
    Write-Host '=== WATCH SENSOR LAB - READ-ONLY SELF TEST ==='
    Write-Host ("BUILD SHA = {0}" -f $Response.build_sha)
    Write-Host ("TRANSPORT = USB / usbmux / device:{0}" -f $DevicePort)
    Write-Host ("READ ONLY = {0}" -f $Response.read_only)
    Write-Host ("HEALTHKIT MUTATION = {0}" -f $Response.healthkit_mutation)
    Write-Host ''

    if ($Command -eq 'ping') {
        if (-not [bool]$Response.ok) {
            throw ("Self-test API error: {0}" -f $Response.error)
        }
        Write-Host 'SELFTEST API: READY' -ForegroundColor Green
        return
    }

    $Rows = foreach ($Test in @($Response.tests)) {
        [pscustomobject]@{
            status = if ([bool]$Test.passed) { 'PASS' } else { 'FAIL' }
            test   = $Test.name
            detail = $Test.detail
        }
    }

    $Rows | Format-Table -AutoSize -Wrap
    Write-Host ''
    Write-Host ("PASSED = {0}" -f $Response.passed)
    Write-Host ("FAILED = {0}" -f $Response.failed)

    if (-not [bool]$Response.ok -or [int]$Response.failed -ne 0) {
        throw 'SELFTEST: FAIL'
    }

    Write-Host 'SELFTEST: PASS' -ForegroundColor Green
}
finally {
    if ($null -ne $Writer) {
        $Writer.Dispose()
    }
    if ($null -ne $Reader) {
        $Reader.Dispose()
    }
    if ($null -ne $Client) {
        $Client.Dispose()
    }
    if ($null -ne $Forward -and -not $Forward.HasExited) {
        Stop-Process -Id $Forward.Id -Force -ErrorAction SilentlyContinue
    }
    foreach ($Path in @($ForwardStdout, $ForwardStderr)) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}
