# Cloudflare Tunnel

This project's public/mobile entrypoint should use a remotely managed Cloudflare Tunnel.

`localtunnel` remains available only as a temporary fallback for testing.

## Recommended deployment model

- FastAPI backend runs locally on `http://127.0.0.1:3113`
- Cloudflare Tunnel publishes a public hostname to that local port
- Mobile users open the Cloudflare hostname directly
- No `loca.lt` password page

## Prerequisites

- A Cloudflare account
- A domain managed in Cloudflare DNS
- A remotely managed tunnel created in the Cloudflare dashboard
- A published application route pointing to `http://127.0.0.1:3113`
- The tunnel token copied from the dashboard

Official references:

- [Set up Cloudflare Tunnel](https://developers.cloudflare.com/tunnel/setup/)
- [Tunnel tokens](https://developers.cloudflare.com/tunnel/advanced/tunnel-tokens/)

## Dashboard setup

1. In Cloudflare, go to `Networking -> Tunnels`.
2. Create a remotely managed tunnel.
3. Add a `Published application` route.
4. Set the service URL to `http://127.0.0.1:3113`.
5. Copy the install command shown by Cloudflare and extract the token from it.

The token is the long `eyJ...` value.

## Local setup

### 1. Install cloudflared

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-cloudflared.ps1
```

### 2. Save the token

Option A: environment variable

```powershell
$env:CLOUDFLARE_TUNNEL_TOKEN='eyJ...'
```

Option B: token file

```powershell
New-Item -ItemType Directory -Force -Path .\.runtime\cloudflare | Out-Null
Set-Content .\.runtime\cloudflare\tunnel-token.txt 'eyJ...' -NoNewline
```

## Run modes

### Foreground debug run

Use this while validating the tunnel:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-cloudflare-tunnel.ps1
```

Logs are written to:

- `.\.runtime\cloudflare\cloudflared.out.log`
- `.\.runtime\cloudflare\cloudflared.err.log`

### Windows service

Use this for the formal always-on deployment path:

```powershell
$env:CLOUDFLARE_TUNNEL_TOKEN='eyJ...'
powershell -ExecutionPolicy Bypass -File .\scripts\install-cloudflare-service.ps1
```

This follows Cloudflare's Windows service model:

```text
cloudflared.exe service install <TUNNEL_TOKEN>
```

After install:

```powershell
Get-Service cloudflared
Start-Service cloudflared
Restart-Service cloudflared
```

## Validation

1. Start the backend:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\start-backend.ps1
```

2. Verify local health:

```powershell
Invoke-WebRequest http://127.0.0.1:3113/health
```

3. Open the public hostname from mobile.

## Notes

- Anyone with the tunnel token can run the tunnel. Treat it as a secret.
- Quick Tunnel / `trycloudflare.com` is for testing only.
- `localtunnel` is retained only as a fallback script, not the recommended deployment path.
