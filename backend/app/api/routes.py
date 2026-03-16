from __future__ import annotations

from uuid import uuid4

from fastapi import APIRouter, HTTPException

from app.core.settings import settings
from app.services.codex_app_server import interrupt_thread_turn, resolve_endpoint, run_codex_turn
from app.services.desktop_refresh import refresh_desktop_thread
from app.services.sessions import (
    build_hapi_message,
    build_messages_response,
    build_session_payload,
    build_session_summary_payload,
    build_thread_summary,
    find_session_file_by_thread_id,
    list_recent_threads,
)
from app.services.state import add_pending_local_message, get_pending_local_messages, pending_local_messages_by_thread_id, remove_pending_local_message
from app.services.transcription import transcribe_audio
from app.services.uploads import save_uploaded_file

router = APIRouter()


def build_codex_input_text(text: str, attachments: list[dict] | None) -> str:
    trimmed = (text or "").strip()
    safe_attachments = []
    for item in attachments or []:
        path = item.get("path")
        if not path:
            continue
        attachment_type = item.get("type") or ""
        size = item.get("size") or 0
        meta = ", ".join(part for part in [attachment_type, f"{size} bytes" if size else ""] if part)
        safe_attachments.append(f"- {item.get('name') or 'attachment'}: {path}{f' ({meta})' if meta else ''}")
    if not safe_attachments:
        return trimmed
    return "\n".join([trimmed, "", "Attached files available on disk:", *safe_attachments, "", "Use these local file paths if you need to inspect the attachments."]).strip()


@router.get("/health")
async def health() -> dict:
    endpoint = await resolve_endpoint()
    return {
        "ok": True,
        "service": "codex-hapi-web",
        "endpoint": endpoint,
        "sessionRoot": str(settings.session_root),
        "voiceBackend": settings.voice_backend,
        "localTranscriptionUrl": settings.local_transcription_url if settings.voice_backend == "local" else None,
    }


@router.get("/api/sessions")
async def sessions() -> dict:
    threads = await list_recent_threads(limit=120)
    return {"sessions": [build_session_summary_payload(thread) for thread in threads]}


@router.get("/api/sessions/{session_id}")
async def session_detail(session_id: str) -> dict:
    session_file = await find_session_file_by_thread_id(session_id)
    summary = await build_thread_summary(session_file or "")
    if not summary:
        raise HTTPException(status_code=404, detail="Session not found")
    return {"session": build_session_payload(summary)}


@router.get("/api/sessions/{session_id}/messages")
async def session_messages(session_id: str) -> dict:
    return await build_messages_response(session_id)


@router.post("/api/sessions/{session_id}/messages")
async def send_message(session_id: str, body: dict) -> dict:
    text = (body.get("text") or "").strip()
    attachments = body.get("attachments") or []
    local_id = body.get("localId") or f"local-{uuid4()}"
    if not text:
        raise HTTPException(status_code=400, detail="Missing text")

    codex_input = build_codex_input_text(text, attachments)
    add_pending_local_message(
        session_id,
        build_hapi_message(
            id=local_id,
            role="user",
            content=text,
            timestamp=None,
            local_id=local_id,
            status="sending",
            original_text=text,
        ),
    )

    try:
        await run_codex_turn(thread_id=session_id, message=codex_input)
        remove_pending_local_message(session_id, local_id)
        return {"ok": True}
    except Exception as error:
        pending_local_messages_by_thread_id[session_id] = [
            ({**message, "status": "failed"} if message.get("localId") == local_id else message)
            for message in get_pending_local_messages(session_id)
        ]
        raise HTTPException(status_code=500, detail=str(error))


@router.post("/api/sessions/{session_id}/interrupt")
async def interrupt(session_id: str) -> dict:
    result = await interrupt_thread_turn(session_id)
    if not result.get("ok"):
        raise HTTPException(status_code=409, detail=result.get("reason"))
    return result


@router.post("/api/sessions/{session_id}/desktop-refresh")
async def desktop_refresh(session_id: str) -> dict:
    return await refresh_desktop_thread(session_id)


@router.post("/api/uploads")
async def uploads(body: dict) -> dict:
    content_base64 = body.get("contentBase64") or ""
    if not content_base64:
        raise HTTPException(status_code=400, detail="Missing contentBase64")
    path = save_uploaded_file(body.get("name") or "upload.bin", content_base64)
    return {
        "ok": True,
        "file": {
            "name": body.get("name") or "upload.bin",
            "type": body.get("type") or "application/octet-stream",
            "size": body.get("size") or 0,
            "path": path,
        },
    }


@router.post("/api/transcriptions")
async def transcriptions(body: dict) -> dict:
    return await transcribe_audio(
        audio_base64=body.get("audioBase64") or "",
        mime_type=body.get("mimeType") or "audio/webm",
        file_name=body.get("fileName") or "recording.webm",
        language=body.get("language") or "zh",
    )
