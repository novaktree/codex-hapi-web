# Architecture

## Frontend

- React + Vite
- Polling client for sessions and messages
- Attachments, voice recording, desktop refresh trigger

## Backend

- FastAPI for API and static frontend delivery
- WebSocket client for local Codex app-server
- Native session projection from `~/.codex/sessions`
- Desktop refresh delegated to PowerShell UI automation
