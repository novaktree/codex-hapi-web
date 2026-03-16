# Local Voice Backend

Use the bundled `voice-local/` Flask service for local `faster-whisper` transcription.

## Start with Docker

```powershell
docker-compose -f .\docker-compose.voice-local.yml up -d --build
```

## Or run directly

```powershell
cd .\voice-local
pip install -r requirements.txt
python app.py
```
