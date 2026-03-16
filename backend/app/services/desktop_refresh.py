from __future__ import annotations

import asyncio

from app.core.settings import settings
from app.services.sessions import find_session_file_by_thread_id


async def refresh_desktop_thread(thread_id: str, timeout: float = 120.0) -> dict:
    if not settings.official_ui_refresh_script.exists():
        raise RuntimeError(f"Desktop refresh script not found: {settings.official_ui_refresh_script}")

    session_file = await find_session_file_by_thread_id(thread_id)
    if not session_file:
        raise RuntimeError(f"No session file found for thread_id {thread_id}")

    args = [
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(settings.official_ui_refresh_script),
        thread_id,
    ]

    process = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        cwd=str(settings.project_root),
    )
    try:
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
    except asyncio.TimeoutError:
        process.kill()
        raise RuntimeError(f"Desktop refresh timed out after {timeout:.0f}s")

    out_text = stdout.decode("utf-8", errors="replace").strip()
    err_text = stderr.decode("utf-8", errors="replace").strip()
    if process.returncode != 0:
        raise RuntimeError("\n".join(part for part in [out_text, err_text] if part) or f"Desktop refresh exited with code {process.returncode}")

    return {"ok": True, "threadId": thread_id, "stdout": out_text, "stderr": err_text}
