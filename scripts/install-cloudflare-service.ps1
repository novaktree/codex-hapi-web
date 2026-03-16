param(
    [string]$Token = '',
    [switch]$ForceReinstall
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

$resolvedToken = $Token
if (-not $resolvedToken) {
  $resolvedToken = $env:CLOUDFLARE_TUNNEL_TOKEN
}

if (-not $resolvedToken) {
  throw "Missing Cloudflare tunnel token. Set CLOUDFLARE_TUNNEL_TOKEN or pass -Token."
}

$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
  throw "cloudflared not found. Run .\\scripts\\install-cloudflared.ps1 first."
}

$service = Get-Service cloudflared -ErrorAction SilentlyContinue
if ($service -and -not $ForceReinstall) {
  throw "cloudflared service already exists. Rerun with -ForceReinstall if you want to replace it."
}

if ($service -and $ForceReinstall) {
  & $cloudflared.Source service uninstall
  Start-Sleep -Seconds 2
}

& $cloudflared.Source service install $resolvedToken
Write-Host "cloudflared service installed. Use 'Get-Service cloudflared' to verify status."
