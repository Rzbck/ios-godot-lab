[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('ping', 'status', 'recovery', 'errors', 'logs')]
    [string]$Command = 'status',

    [Parameter(Position = 1)]
    [string]$SessionId,

    [ValidateRange(1, 200)]
    [int]$Limit = 50,

    [string]$Kind,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$DevicePort = 37991
$ProtocolName = 'wsl_diag_v1'

function Resolve-Python {
    $Candidates = @(
        'E:\_Project\IOS APP\_Tools\pymobiledevice3-watch\.venv\Scripts\python.exe',
        'E:\_Project\IOS APP\_Tools\pymobiledevice3\.venv\Scripts\python.exe'
    )

    foreach ($Candidate in $Candidates) {
        if (Test-Path $Candidate) {
            return $Candidate
        }
    }

    foreach ($Name in @('py', 'python')) {
        $CommandInfo = Get-Command $Name -ErrorAction SilentlyContinue
        if ($null -ne $CommandInfo) {
            return $CommandInfo.Source
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

function Connect-DiagnosticPort {
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
            # Forwarder may still be starting; retry briefly.
        }

        $Candidate.Dispose()
        Start-Sleep -Milliseconds 100
    }

    return $null
}

function Format-DiagnosticTimestamp {
    param([object]$Value)

    if ($null -eq $Value) {
        return '?'
    }

    try {
        $Parsed = [System.DateTimeOffset]::Parse(
            [string]$Value,
            [System.Globalization.CultureInfo]::InvariantCulture
        )
        return $Parsed.ToUniversalTime().ToString("HH:mm:ss'Z'")
    }
    catch {
        return [string]$Value
    }
}

function Show-RouteDiagnosticWindows {
    param(
        [string]$Title,
        [object[]]$Windows
    )

    Write-Host ''
    Write-Host $Title
    if ($null -eq $Windows -or @($Windows).Count -eq 0) {
        Write-Host 'Aucune fenêtre GPS/compteur significative.'
        return
    }

    $Index = 0
    foreach ($Window in @($Windows)) {
        $Index++
        $Start = Format-DiagnosticTimestamp $Window.start_iso
        $End = Format-DiagnosticTimestamp $Window.end_iso
        $Duration = [math]::Round([double]$Window.duration_s, 1)
        $Gps = [math]::Round([double]$Window.path_geometry_m, 1)
        $Counter = [math]::Round([double]$Window.watch_counter_advance_m, 1)
        $Excess = [math]::Round([double]$Window.path_excess_m, 1)
        $Detour = [math]::Round([double]$Window.detour_m, 1)
        $Direct = [math]::Round([double]$Window.direct_geometry_m, 1)
        $Allowed = [math]::Round([double]$Window.allowed_path_geometry_m, 1)
        $BridgeAllowed = [math]::Round([double]$Window.bridge_allowed_geometry_m, 1)
        $MaxGap = [math]::Round([double]$Window.max_source_gap_s, 1)
        $CounterGap = [math]::Round([double]$Window.max_counter_interpolation_gap_s, 1)
        $BridgeOk = [bool]$Window.bridge_within_counter_budget
        $Filterable = [bool]$Window.counter_proven_detour

        Write-Host ("[{0}] {1}  {2} -> {3}  {4:N1}s  {5} pts" -f `
            $Index, $Window.source, $Start, $End, $Duration, $Window.point_count)
        Write-Host ("    GPS={0:N1} m | counter={1:N1} m | excess={2:N1} m | detour={3:N1} m | direct={4:N1} m" -f `
            $Gps, $Counter, $Excess, $Detour, $Direct)
        Write-Host ("    budgets: path<={0:N1} m | bridge<={1:N1} m | source_gap={2:N1}s | counter_gap={3:N1}s" -f `
            $Allowed, $BridgeAllowed, $MaxGap, $CounterGap)
        Write-Host ("    decision: bridge_ok={0} | filterable={1} | diagnosis={2}" -f `
            $BridgeOk, $Filterable, $Window.diagnosis)
    }
}

function Show-SavedHealthKitDiagnostic {
    param([object]$Saved)

    Write-Host ''
    Write-Host 'HEALTHKIT SAVED OBJECTS (READ-ONLY)'

    if ($null -eq $Saved) {
        Write-Host 'Aucune donnée HealthKit persistée retournée.'
        return
    }

    $App = $Saved.app_identity
    if ($null -ne $App) {
        Write-Host 'APP IDENTITY'
        [pscustomobject]@{
            bundle_identifier                = $App.bundle_identifier
            bundle_name                      = $App.bundle_name
            display_name                     = $App.display_name
            short_version                    = $App.short_version
            build_version                    = $App.build_version
            icon_name                        = $App.icon_name
            icon_files                       = (@($App.icon_files) -join ', ')
            primary_icon_dictionary_present  = $App.primary_icon_dictionary_present
            icons_dictionary_present         = $App.icons_dictionary_present
        } | Format-List *
    }

    Write-Host 'WORKOUT SOURCE'
    $Workout = $Saved.workout
    if ($null -eq $Workout) {
        Write-Host 'Aucune restauration HealthKit générée.'
    }
    else {
        [pscustomobject]@{
            uuid                            = $Workout.uuid
            activity                       = $Workout.activity
            activity_raw                   = $Workout.activity_raw
            distance_m                     = $Workout.distance_m
            duration_s                     = $Workout.duration_s
            source_name                    = $Workout.source_name
            source_bundle                  = $Workout.source_bundle
            source_version                 = $Workout.source_version
            source_product_type            = $Workout.source_product_type
            source_os                      = $Workout.source_os
            source_matches_installed_bundle = $Workout.source_matches_installed_bundle
            brand_name                     = $Workout.brand_name
            generation                     = $Workout.generation
            attempt_id                     = $Workout.attempt_id
            device                         = if ($null -eq $Workout.device) { 'none' } else { ($Workout.device | ConvertTo-Json -Compress -Depth 8) }
        } | Format-List *
    }

    Write-Host 'SAVED ROUTES'
    $RouteRows = foreach ($Route in @($Saved.routes)) {
        $Hop = $Route.largest_internal_hop
        [pscustomobject]@{
            segment       = $Route.segment_index
            total_segments = $Route.segment_count
            points        = $Route.point_count
            geometry_m    = if ($null -ne $Route.geometry_m) { [math]::Round([double]$Route.geometry_m, 1) } else { $null }
            first         = if ($null -ne $Route.first) { Format-DiagnosticTimestamp $Route.first.iso } else { '?' }
            last          = if ($null -ne $Route.last) { Format-DiagnosticTimestamp $Route.last.iso } else { '?' }
            max_hop_m     = if ($null -ne $Hop) { [math]::Round([double]$Hop.distance_m, 1) } else { $null }
            max_hop_s     = if ($null -ne $Hop) { [math]::Round([double]$Hop.time_gap_s, 1) } else { $null }
            uuid          = $Route.uuid
        }
    }
    if (@($RouteRows).Count -gt 0) {
        $RouteRows | Format-Table -AutoSize -Wrap
    }
    else {
        Write-Host 'Aucune route HealthKit sauvegardée.'
    }

    Write-Host 'ROUTE BOUNDARIES / POSSIBLE FITNESS CONNECTORS'
    $BoundaryRows = foreach ($Boundary in @($Saved.route_boundaries)) {
        [pscustomobject]@{
            from_segment = $Boundary.from_segment_index
            to_segment   = $Boundary.to_segment_index
            distance_m   = [math]::Round([double]$Boundary.distance_m, 1)
            time_gap_s   = [math]::Round([double]$Boundary.time_gap_s, 1)
            from_time    = Format-DiagnosticTimestamp $Boundary.from.iso
            to_time      = Format-DiagnosticTimestamp $Boundary.to.iso
            from_lat     = [math]::Round([double]$Boundary.from.latitude, 6)
            from_lon     = [math]::Round([double]$Boundary.from.longitude, 6)
            to_lat       = [math]::Round([double]$Boundary.to.latitude, 6)
            to_lon       = [math]::Round([double]$Boundary.to.longitude, 6)
        }
    }
    if (@($BoundaryRows).Count -gt 0) {
        $BoundaryRows | Format-Table -AutoSize -Wrap
    }
    else {
        Write-Host 'Aucune frontière inter-route.'
    }

    Write-Host 'SAVED ROUTE SUMMARY'
    [pscustomobject]@{
        generated_workout_count = $Saved.generated_workout_count
        normal_workout_count    = $Saved.normal_workout_count
        saved_route_count       = $Saved.saved_route_count
        saved_location_count    = $Saved.saved_location_count
        saved_geometry_m        = $Saved.saved_geometry_m
        largest_route_boundary  = if ($null -eq $Saved.largest_route_boundary) { 'none' } else { ($Saved.largest_route_boundary | ConvertTo-Json -Compress -Depth 12) }
        largest_internal_hop    = if ($null -eq $Saved.largest_internal_hop) { 'none' } else { ($Saved.largest_internal_hop | ConvertTo-Json -Compress -Depth 12) }
    } | Format-List *
}

if ($Command -eq 'recovery' -and [string]::IsNullOrWhiteSpace($SessionId)) {
    throw '.\apps\watch-sensor-lab\WSL.ps1 recovery <session_id>'
}

$Python = Resolve-Python
$HostPort = Get-FreeTcpPort
$TempBase = Join-Path $env:TEMP ("wsl-diag-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
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

    $Client = Connect-DiagnosticPort -Port $HostPort -ForwardProcess $Forward
    if ($null -eq $Client) {
        $Details = ''
        if (Test-Path $ForwardStderr) {
            $Details = (Get-Content $ForwardStderr -Raw -ErrorAction SilentlyContinue).Trim()
        }
        if ($Details) {
            throw "Impossible de joindre l'API diagnostic via USB. $Details"
        }
        throw "Impossible de joindre l'API diagnostic via USB. Garde l'iPhone branché, déverrouillé et l'app ouverte au premier plan."
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
        limit    = $Limit
    }
    if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
        $Request['session_id'] = $SessionId
    }
    if (-not [string]::IsNullOrWhiteSpace($Kind)) {
        $Request['kind'] = $Kind
    }

    $Writer.WriteLine(($Request | ConvertTo-Json -Compress -Depth 8))
    $ResponseLine = $Reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($ResponseLine)) {
        throw "L'API diagnostic a fermé la connexion sans réponse. Vérifie que l'app est ouverte au premier plan et que le build installé correspond au HEAD attendu."
    }

    $Response = $ResponseLine | ConvertFrom-Json
    if (-not [bool]$Response.ok) {
        throw ("Diagnostic API error: {0}" -f $Response.error)
    }

    if ($Json) {
        $Response | ConvertTo-Json -Depth 64
        return
    }

    Write-Host ''
    Write-Host '=== WATCH SENSOR LAB - DIAGNOSTIC API ==='
    Write-Host ("COMMAND   = {0}" -f $Response.command)
    Write-Host ("BUILD SHA = {0}" -f $Response.build_sha)
    Write-Host ("TRANSPORT = USB / usbmux / device:{0}" -f $DevicePort)
    Write-Host ''

    $Data = $Response.data
    switch ($Command) {
        'ping' {
            $Data | Format-List *
        }

        'status' {
            [pscustomobject]@{
                phase                       = $Data.phase
                selected_activity           = $Data.selected_activity
                effective_activity          = $Data.effective_activity
                session_id                  = $Data.session_id
                elapsed_s                   = $Data.elapsed_s
                distance_m                  = $Data.distance_m
                speed_mps                   = $Data.speed_mps
                heart_rate_bpm              = $Data.heart_rate_bpm
                route_points                = $Data.route_points
                watch_reachable             = $Data.watch_reachable
                health_authorized           = $Data.health_authorized
                status_message              = $Data.status_message
                pending_command              = $Data.pending_command
                finish_review_required      = $Data.finish_review_required
                historical_repair_session   = $Data.historical_repair_session_id
                historical_repair_status    = $Data.historical_repair_status
            } | Format-List *
        }

        'recovery' {
            [pscustomobject]@{
                session_id          = $Data.session_id
                status              = $Data.status
                active              = $Data.active
                internally_verified = $Data.internally_verified
                timed_out           = $Data.timed_out
            } | Format-List *

            if ($null -ne $Data.audit) {
                Write-Host 'AUDIT'
                $Data.audit | Format-List *
            }
            else {
                Write-Host 'AUDIT = aucune donnée retournée'
            }

            $RouteDiagnosticsProperty = $Data.PSObject.Properties['route_diagnostics']
            if ($null -ne $RouteDiagnosticsProperty -and $null -ne $RouteDiagnosticsProperty.Value) {
                $RouteDiagnostics = $RouteDiagnosticsProperty.Value
                Write-Host ''
                Write-Host 'ROUTE DIAGNOSTICS (READ-ONLY)'
                [pscustomobject]@{
                    counter_source       = $RouteDiagnostics.counter_source
                    watch_points         = $RouteDiagnostics.watch_points
                    iphone_points        = $RouteDiagnostics.iphone_points
                    watch_counter_points = $RouteDiagnostics.watch_counter_points
                } | Format-List *

                Show-RouteDiagnosticWindows `
                    -Title 'WATCH GPS vs WATCH COUNTER - WORST WINDOWS' `
                    -Windows @($RouteDiagnostics.watch_windows)
                Show-RouteDiagnosticWindows `
                    -Title 'IPHONE GPS vs WATCH COUNTER - WORST WINDOWS' `
                    -Windows @($RouteDiagnostics.iphone_windows)
            }
            else {
                $RouteErrorProperty = $Data.PSObject.Properties['route_diagnostics_error']
                if ($null -ne $RouteErrorProperty -and $RouteErrorProperty.Value) {
                    Write-Host ("ROUTE DIAGNOSTICS ERROR = {0}" -f $RouteErrorProperty.Value)
                }
            }

            $SavedProperty = $Data.PSObject.Properties['saved_healthkit']
            if ($null -ne $SavedProperty -and $null -ne $SavedProperty.Value) {
                Show-SavedHealthKitDiagnostic -Saved $SavedProperty.Value
            }
            else {
                $SavedErrorProperty = $Data.PSObject.Properties['saved_healthkit_error']
                if ($null -ne $SavedErrorProperty -and $SavedErrorProperty.Value) {
                    Write-Host ("SAVED HEALTHKIT DIAGNOSTIC ERROR = {0}" -f $SavedErrorProperty.Value)
                }
            }
        }

        { $_ -in @('errors', 'logs') } {
            $Rows = foreach ($Record in @($Data.records)) {
                $Fields = ''
                if ($null -ne $Record.fields) {
                    $Fields = $Record.fields | ConvertTo-Json -Compress -Depth 16
                }
                [pscustomobject]@{
                    timestamp = $Record.timestamp
                    platform  = $Record.platform
                    kind      = $Record.kind
                    name      = $Record.name
                    screen    = $Record.screen
                    fields    = $Fields
                }
            }

            if (@($Rows).Count -eq 0) {
                Write-Host 'Aucun enregistrement.'
            }
            else {
                $Rows | Format-Table -AutoSize -Wrap
            }
        }
    }
}
finally {
    if ($null -ne $Writer) { $Writer.Dispose() }
    if ($null -ne $Reader) { $Reader.Dispose() }
    if ($null -ne $Client) { $Client.Dispose() }

    if ($null -ne $Forward -and -not $Forward.HasExited) {
        Stop-Process -Id $Forward.Id -Force -ErrorAction SilentlyContinue
        try { $Forward.WaitForExit(2000) | Out-Null } catch {}
    }

    Remove-Item $ForwardStdout, $ForwardStderr -Force -ErrorAction SilentlyContinue
}
