param()

$ErrorActionPreference = 'Stop'

$existing = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($existing) {
  Write-Host "cloudflared already installed at: $($existing.Source)"
  exit 0
}

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
  throw "winget not found. Install cloudflared manually from https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/ and rerun."
}

Write-Host "Installing cloudflared with winget..."
& $winget.Source install --id Cloudflare.cloudflared --exact --accept-source-agreements --accept-package-agreements

$installed = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $installed) {
  $fallbacks = @(
    'C:\Program Files\cloudflared\cloudflared.exe',
    'C:\Program Files (x86)\cloudflared\cloudflared.exe',
    "$env:ProgramFiles\Cloudflare\Cloudflared\cloudflared.exe"
  )
  $installed = $fallbacks | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if (-not $installed) {
  throw "cloudflared install command finished, but cloudflared was not found. Open a new shell and try again."
}

if ($installed -is [string]) {
  Write-Host "cloudflared installed at: $installed"
} else {
  Write-Host "cloudflared installed at: $($installed.Source)"
}
