from __future__ import annotations

import base64
import uuid

from app.core.settings import settings


def sanitize_upload_filename(name: str) -> str:
    safe = "".join("-" if ch in '<>:"/\\|?*' or ord(ch) < 32 else ch for ch in (name or "upload.bin"))
    safe = " ".join(safe.split()).strip()[:120]
    return safe or "upload.bin"


def save_uploaded_file(name: str, content_base64: str) -> str:
    settings.uploads_dir.mkdir(parents=True, exist_ok=True)
    absolute_path = settings.uploads_dir / f"{uuid.uuid4()}-{sanitize_upload_filename(name)}"
    absolute_path.write_bytes(base64.b64decode(content_base64))
    return str(absolute_path)
