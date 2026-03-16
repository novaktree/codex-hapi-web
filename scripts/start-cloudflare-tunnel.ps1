param(
    [string]$Token = '',
    [string]$TokenFile = '',
    [int]$TailLines = 80
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common.ps1')
Import-ProjectDotEnv -ProjectRoot $root | Out-Null

$runtime = Join-Path $root '.runtime'
$cloudflareRuntime = Join-Path $runtime 'cloudflare'
New-Item -ItemType Directory -Force -Path $cloudflareRuntime | Out-Null

$out = Join-Path $cloudflareRuntime 'cloudflared.out.log'
$err = Join-Path $cloudflareRuntime 'cloudflared.err.log'

$resolvedToken = $Token
if (-not $resolvedToken) {
  $resolvedToken = $env:CLOUDFLARE_TUNNEL_TOKEN
}

$resolvedTokenFile = $TokenFile
if (-not $resolvedTokenFile) {
  $resolvedTokenFile = $env:CLOUDFLARE_TUNNEL_TOKEN_FILE
}
if (-not $resolvedTokenFile) {
  $resolvedTokenFile = Join-Path $cloudflareRuntime 'tunnel-token.txt'
}
$resolvedTokenFile = Resolve-ProjectPath -ProjectRoot $root -PathValue $resolvedTokenFile

$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
if (-not $cloudflared) {
  throw "cloudflared not found. Run .\\scripts\\install-cloudflared.ps1 first."
}

if (-not $resolvedToken -and -not (Test-Path $resolvedTokenFile)) {
  throw "Missing Cloudflare tunnel token. Set CLOUDFLARE_TUNNEL_TOKEN or write the token to $resolvedTokenFile."
}

if ($resolvedToken) {
  Set-Content -Path $resolvedTokenFile -Value $resolvedToken -NoNewline -Encoding ascii
}

$existing = Get-CimInstance Win32_Process | Where-Object {
  $_.Name -match '^cloudflared(\.exe)?$' -and $_.CommandLine -match 'tunnel run'
}

foreach ($proc in $existing) {
  try {
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
  } catch {}
}

Start-Process -FilePath $cloudflared.Source `
  -ArgumentList 'tunnel', '--no-autoupdate', 'run', '--token-file', $resolvedTokenFile `
  -WorkingDirectory $root `
  -RedirectStandardOutput $out `
  -RedirectStandardError $err

Start-Sleep -Seconds 6

if (Test-Path $out) {
  Get-Content $out -Tail $TailLines
}

if (Test-Path $err) {
  Get-Content $err -Tail $TailLines
}
