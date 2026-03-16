param(
    [int]$Port = 3113
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
    $Port = [int]$env:CODEX_HAPI_PORT
}

$tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
if (-not $tailscale) {
    throw "tailscale command not found. Install Tailscale first."
}

$ip = & tailscale ip -4 2>$null | Select-Object -First 1
$ip = ($ip | Out-String).Trim()

if ([string]::IsNullOrWhiteSpace($ip)) {
    throw "Could not resolve a Tailscale IPv4 address. Make sure this machine is logged into Tailscale."
}

Write-Output "http://$ip`:$Port"
