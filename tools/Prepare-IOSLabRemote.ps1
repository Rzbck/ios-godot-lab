[CmdletBinding()]
param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8787
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TailscaleCommand {
    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidate = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    throw 'Tailscale CLI introuvable.'
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not $IsWindows) {
    throw 'Ce helper est prévu pour Windows.'
}

$tailscale = Get-TailscaleCommand

Write-Host ''
Write-Host '=== IOSLAB REMOTE / TAILSCALE PREP ===' -ForegroundColor Cyan

$status = & $tailscale status 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Tailscale status a échoué:`n$status"
}

$ip = (& $tailscale ip -4 2>$null | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($ip)) {
    throw 'Aucune IPv4 Tailscale détectée. Vérifie que Tailscale est connecté.'
}
$ip = $ip.Trim()

Write-Host "TAILSCALE IP = $ip" -ForegroundColor Green
Write-Host "TELEMETRY    = ws://${ip}:$Port/telemetry"
Write-Host "HTTP FALLBACK= http://${ip}:$Port/telemetry"

$ruleName = "IOSLab Tailscale TCP $Port"

if (-not (Test-IsAdministrator)) {
    Write-Host ''
    Write-Host 'Le contrôle/création de la règle Firewall nécessite PowerShell Admin.' -ForegroundColor Yellow
    Write-Host 'Relance UNE FOIS ce script en administrateur pour préparer le PC au test 5G/Tailscale.' -ForegroundColor Yellow
    Write-Host ''
    exit 2
}

$existing = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existing) {
    Set-NetFirewallRule `
        -DisplayName $ruleName `
        -Enabled True `
        -Action Allow `
        -Profile Any | Out-Null

    $existing | Get-NetFirewallPortFilter |
        Set-NetFirewallPortFilter -Protocol TCP -LocalPort $Port | Out-Null

    $existing | Get-NetFirewallAddressFilter |
        Set-NetFirewallAddressFilter -RemoteAddress '100.64.0.0/10' | Out-Null

    Write-Host "FIREWALL     = EXISTING RULE UPDATED" -ForegroundColor Green
}
else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Enabled True `
        -Profile Any `
        -Protocol TCP `
        -LocalPort $Port `
        -RemoteAddress '100.64.0.0/10' `
        -Description 'Allows IOSLab telemetry from Tailscale peers only.' | Out-Null

    Write-Host "FIREWALL     = RULE CREATED" -ForegroundColor Green
}

Write-Host ''
Write-Host 'REMOTE READY.' -ForegroundColor Green
Write-Host "1. Laisse Tailscale connecté sur le PC."
Write-Host "2. Lance Receive-IOSLabTelemetry.ps1 sur le port $Port."
Write-Host "3. Sur iPhone (Wi-Fi OU 5G), active Tailscale puis utilise $ip`:$Port."
Write-Host ''
