from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    project_root: Path
    frontend_dist_dir: Path
    runtime_dir: Path
    uploads_dir: Path
    codex_home: Path
    session_root: Path
    host: str
    port: int
    codex_app_server_url: str
    fallback_endpoints: tuple[str, ...]
    voice_backend: str
    local_transcription_url: str
    openai_api_key: str
    openai_transcription_model: str
    official_ui_refresh_script: Path
    max_projected_messages: int = 240
    max_terminal_output_chars: int = 6000
    max_terminal_output_lines: int = 160
    session_file_list_ttl_ms: int = 3000


def load_settings() -> Settings:
    project_root = Path(__file__).resolve().parents[3]
    explicit_endpoint = os.getenv("CODEX_APP_SERVER_URL", "").strip()
    fallback_endpoints = tuple(
        endpoint
        for endpoint in [explicit_endpoint, "ws://127.0.0.1:8766", "ws://127.0.0.1:8765"]
        if endpoint
    )
    codex_home = Path(os.getenv("CODEX_HOME", str(Path.home() / ".codex")))
    refresh_script_value = os.getenv(
        "CODEX_HAPI_DESKTOP_REFRESH_SCRIPT",
        str(project_root / "scripts" / "refresh-desktop-thread.ps1"),
    )
    refresh_script_path = Path(refresh_script_value)
    if not refresh_script_path.is_absolute():
        refresh_script_path = (project_root / refresh_script_path).resolve()
    return Settings(
        project_root=project_root,
        frontend_dist_dir=project_root / "frontend" / "dist",
        runtime_dir=project_root / ".runtime",
        uploads_dir=project_root / ".runtime" / "uploads",
        codex_home=codex_home,
        session_root=codex_home / "sessions",
        host=os.getenv("CODEX_HAPI_HOST", "0.0.0.0"),
        port=int(os.getenv("CODEX_HAPI_PORT", "3113")),
        codex_app_server_url=explicit_endpoint,
        fallback_endpoints=fallback_endpoints,
        voice_backend=os.getenv("CODEX_HAPI_VOICE_BACKEND", "local").strip().lower(),
        local_transcription_url=os.getenv("CODEX_HAPI_LOCAL_TRANSCRIPTION_URL", "http://127.0.0.1:8021/transcribe").strip(),
        openai_api_key=os.getenv("OPENAI_API_KEY", "").strip(),
        openai_transcription_model=os.getenv("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe").strip(),
        official_ui_refresh_script=refresh_script_path,
    )


settings = load_settings()
