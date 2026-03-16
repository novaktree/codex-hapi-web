param(
    [int]$Port = 3113,
    [int]$TailLines = 120
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

if (-not $PSBoundParameters.ContainsKey('Port') -and $env:CODEX_HAPI_PORT) {
  $Port = [int]$env:CODEX_HAPI_PORT
}

$runtime = Join-Path $root '.runtime'
$cloudflareRuntime = Join-Path $runtime 'cloudflare-quick'
New-Item -ItemType Directory -Force -Path $cloudflareRuntime | Out-Null

$out = Join-Path $cloudflareRuntime "trycloudflare-$Port.out.log"
$err = Join-Path $cloudflareRuntime "trycloudflare-$Port.err.log"

$cloudflaredPath = $null
$command = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($command) {
  $cloudflaredPath = $command.Source
}
if (-not $cloudflaredPath) {
  $fallbacks = @(
    'C:\Program Files\cloudflared\cloudflared.exe',
    'C:\Program Files (x86)\cloudflared\cloudflared.exe',
    "$env:ProgramFiles\Cloudflare\Cloudflared\cloudflared.exe"
  )
  $cloudflaredPath = $fallbacks | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $cloudflaredPath) {
  throw "cloudflared not found. Run .\\scripts\\install-cloudflared.ps1 first."
}

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^cloudflared(\.exe)?$' -and (
    $_.CommandLine -match 'trycloudflare\.com' -or
    $_.CommandLine -match "tunnel --url http://127.0.0.1:$Port" -or
    $_.CommandLine -match "tunnel --url http://localhost:$Port"
  )
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

Start-Process -FilePath $cloudflaredPath `
  -ArgumentList 'tunnel', '--no-autoupdate', '--url', "http://127.0.0.1:$Port" `
  -WorkingDirectory $root `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err

Start-Sleep -Seconds 8

if (Test-Path $out) {
  Get-Content $out -Tail $TailLines
}

if (Test-Path $err) {
  Get-Content $err -Tail $TailLines
}
