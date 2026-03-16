from __future__ import annotations

import base64

import httpx

from app.core.settings import settings


async def transcribe_audio(
    *,
    audio_base64: str,
    mime_type: str,
    file_name: str,
    language: str | None,
) -> dict:
    if settings.voice_backend == "local":
        return await _transcribe_audio_locally(
            audio_base64=audio_base64,
            mime_type=mime_type,
            file_name=file_name,
            language=language,
        )
    if settings.voice_backend == "openai":
        return await _transcribe_audio_openai(
            audio_base64=audio_base64,
            mime_type=mime_type,
            file_name=file_name,
            language=language,
        )
    raise RuntimeError(f"Unsupported CODEX_HAPI_VOICE_BACKEND: {settings.voice_backend}")


async def _transcribe_audio_locally(*, audio_base64: str, mime_type: str, file_name: str, language: str | None) -> dict:
    async with httpx.AsyncClient(timeout=300.0) as client:
        response = await client.post(
            settings.local_transcription_url,
            json={
                "audioBase64": audio_base64,
                "mimeType": mime_type,
                "fileName": file_name,
                "language": language,
            },
        )
    payload = response.json()
    if response.is_error:
        raise RuntimeError(payload.get("error", {}).get("message") or payload.get("message") or response.text)
    text = (payload.get("text") or "").strip()
    if not text:
        raise RuntimeError("Local transcription returned empty text")
    return {"text": text, "model": payload.get("model") or "local-faster-whisper"}


async def _transcribe_audio_openai(*, audio_base64: str, mime_type: str, file_name: str, language: str | None) -> dict:
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not configured")
    files = {
        "file": (
            file_name or "recording.webm",
            base64.b64decode(audio_base64),
            mime_type or "application/octet-stream",
        )
    }
    data = {
        "model": settings.openai_transcription_model,
        "response_format": "json",
    }
    if language:
        data["language"] = language
    async with httpx.AsyncClient(timeout=300.0) as client:
        response = await client.post(
            "https://api.openai.com/v1/audio/transcriptions",
            headers={"Authorization": f"Bearer {settings.openai_api_key}"},
            data=data,
            files=files,
        )
    payload = response.json()
    if response.is_error:
        raise RuntimeError(payload.get("error", {}).get("message") or payload.get("message") or response.text)
    text = (payload.get("text") or "").strip()
    if not text:
        raise RuntimeError("Transcription returned empty text")
    return {"text": text, "model": settings.openai_transcription_model}
