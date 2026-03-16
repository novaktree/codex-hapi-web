from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any

from app.core.settings import settings
from app.services.state import get_pending_local_messages, get_runtime_state


thread_summary_cache: dict[str, tuple[str, dict]] = {}
thread_history_cache: dict[str, tuple[str, dict]] = {}
session_file_cache: dict[str, str] = {}
session_file_list_cache: dict[str, Any] = {"expiresAt": 0, "files": []}


def as_record(value: Any) -> dict | None:
    return value if isinstance(value, dict) else None


def as_string(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def timestamp_to_millis(value: str | None) -> int:
    if not value:
        return 0
    try:
        import datetime as _dt

        return int(_dt.datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp() * 1000)
    except Exception:
        return 0


def summarize_text(text: str, max_length: int = 140) -> str:
    normalized = re.sub(r"\s+", " ", str(text or "")).strip()
    if len(normalized) <= max_length:
        return normalized
    return f"{normalized[: max_length - 1]}…"


def extract_text_content(content: Any) -> str | None:
    if not isinstance(content, list):
        return None
    text_parts = []
    for part in content:
        record = as_record(part)
        if not record:
            continue
        text = as_string(record.get("text")) or as_string(record.get("content"))
        if text:
            text_parts.append(text)
    joined = "\n".join(text_parts).strip()
    return joined or None


def is_bootstrap_message(text: str) -> bool:
    return text.startswith("# AGENTS.md instructions for ") or "<environment_context>" in text


def normalize_history_text(text: str) -> str:
    return text[5:] if text.startswith("???: ") else text


def sanitize_terminal_output(text: str) -> dict:
    normalized = str(text or "").replace("\0", "").replace("\r\n", "\n").strip()
    if not normalized:
        return {"output": ""}
    lines = normalized.split("\n")
    next_text = normalized
    if any(marker in normalized for marker in ['"conversation_id"', '"response_item"', '"function_call_output"', "# AGENTS.md instructions for ", "<environment_context>"]) and len(normalized) > 1600:
        next_text = "\n".join(lines[:48]) + "\n\n[projection note] terminal output looked like a transcript dump and was truncated."
    elif len(lines) > settings.max_terminal_output_lines:
        next_text = "\n".join(lines[: settings.max_terminal_output_lines]) + f"\n\n[output truncated: {len(lines) - settings.max_terminal_output_lines} more lines]"
    if len(next_text) > settings.max_terminal_output_chars:
        next_text = next_text[: settings.max_terminal_output_chars] + f"\n\n[output truncated: {len(normalized) - settings.max_terminal_output_chars} more chars]"
    return {"output": next_text}


def parse_json_string(value: Any) -> dict | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return json.loads(value)
    except Exception:
        return None


def parse_shell_call_arguments(payload: dict) -> dict:
    raw_args = parse_json_string(as_string(payload.get("arguments")))
    return {"command": as_string((raw_args or {}).get("command")) or "", "workdir": as_string((raw_args or {}).get("workdir")) or ""}


def parse_function_output(output_text: str | None) -> dict:
    output = output_text or ""
    exit_match = re.search(r"Exit code:\s*(-?\d+)", output, re.I)
    time_match = re.search(r"Wall time:\s*([0-9.]+)\s*s", output, re.I)
    trimmed = re.sub(r"^Exit code:\s*-?\d+\s*", "", output, flags=re.I)
    trimmed = re.sub(r"^Wall time:\s*[0-9.]+\s*seconds?\s*", "", trimmed, flags=re.I)
    trimmed = re.sub(r"^Output:\s*", "", trimmed, flags=re.I).strip()
    sanitized = sanitize_terminal_output(trimmed)
    return {
        "exitCode": int(exit_match.group(1)) if exit_match else None,
        "durationMs": round(float(time_match.group(1)) * 1000) if time_match else None,
        "output": sanitized["output"],
    }


def get_file_signature(path: Path) -> str:
    stat = path.stat()
    return f"{stat.st_mtime_ns}:{stat.st_size}"


def extract_thread_id_from_filename(session_file: str) -> str | None:
    match = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$", session_file, re.I)
    return match.group(1) if match else None


async def list_session_files() -> list[str]:
    if session_file_list_cache["expiresAt"] > time.time() * 1000:
        return list(session_file_list_cache["files"])
    files = [str(path) for path in settings.session_root.rglob("*.jsonl")]
    session_file_list_cache["expiresAt"] = time.time() * 1000 + settings.session_file_list_ttl_ms
    session_file_list_cache["files"] = files
    return files


async def find_session_file_by_thread_id(thread_id: str) -> str | None:
    cached = session_file_cache.get(thread_id)
    if cached and Path(cached).exists():
        return cached
    for path in await list_session_files():
        if thread_id in path:
            session_file_cache[thread_id] = path
            return path
    return None


def build_session_metadata(summary: dict) -> dict:
    path = summary.get("cwd") or summary.get("sessionFile") or summary["id"]
    worktree_name = Path(path).name or path
    metadata = {"name": summary.get("title"), "path": path, "host": "local-codex", "flavor": "codex", "codexSessionId": summary["id"]}
    if summary.get("preview"):
        metadata["summary"] = {"text": summary["preview"], "updatedAt": timestamp_to_millis(summary.get("updatedAt"))}
    if summary.get("cwd"):
        metadata["worktree"] = {"basePath": summary["cwd"], "branch": "main", "name": worktree_name}
    return metadata


def build_session_summary_payload(summary: dict) -> dict:
    runtime = summary.get("runtime") or {}
    return {
        "id": summary["id"],
        "active": runtime.get("state") == "thinking",
        "thinking": runtime.get("state") == "thinking",
        "activeAt": timestamp_to_millis(runtime.get("startedAt") or summary.get("updatedAt") or summary.get("createdAt")),
        "updatedAt": timestamp_to_millis(summary.get("updatedAt") or summary.get("createdAt")),
        "metadata": build_session_metadata(summary),
        "todoProgress": None,
        "pendingRequestsCount": 0,
        "modelMode": "default",
    }


def build_session_payload(summary: dict) -> dict:
    runtime = summary.get("runtime") or {}
    return {
        "id": summary["id"],
        "namespace": "codex-projection",
        "seq": summary.get("messageCount", 0),
        "createdAt": timestamp_to_millis(summary.get("createdAt")),
        "updatedAt": timestamp_to_millis(summary.get("updatedAt") or summary.get("createdAt")),
        "active": runtime.get("state") == "thinking",
        "activeAt": timestamp_to_millis(runtime.get("startedAt") or summary.get("updatedAt") or summary.get("createdAt")),
        "metadata": build_session_metadata(summary),
        "metadataVersion": 1,
        "agentState": None,
        "agentStateVersion": 0,
        "thinking": runtime.get("state") == "thinking",
        "thinkingAt": timestamp_to_millis(runtime.get("updatedAt") or summary.get("updatedAt") or summary.get("createdAt")),
        "permissionMode": "default",
        "modelMode": "default",
    }


def build_hapi_message(*, id: str, role: str, content: str, timestamp: str | None, local_id: str | None = None, status: str | None = None, original_text: str | None = None, content_type: str = "text", extra_content: dict | None = None) -> dict:
    payload = {
        "id": id,
        "seq": None,
        "localId": local_id,
        "content": {
            "role": "agent" if role == "assistant" else "user",
            "content": {"type": "text", "text": content} if content_type == "text" else {"type": content_type, **(extra_content or {})},
        },
        "createdAt": timestamp_to_millis(timestamp),
    }
    if status:
        payload["status"] = status
    if original_text:
        payload["originalText"] = original_text
    return payload


def should_hide_pending_message(pending_message: dict, persisted_messages: list[dict]) -> bool:
    if (pending_message.get("content") or {}).get("role") != "user":
        return False
    pending_text = pending_message.get("originalText") or ((pending_message.get("content") or {}).get("content") or {}).get("text") or ""
    if not pending_text:
        return False
    pending_created_at = int(pending_message.get("createdAt") or 0)
    for persisted in persisted_messages:
        if ((persisted.get("content") or {}).get("role") != "user"):
            continue
        persisted_text = ((persisted.get("content") or {}).get("content") or {}).get("text") or ""
        if persisted_text != pending_text:
            continue
        persisted_created_at = int(persisted.get("createdAt") or 0)
        if not pending_created_at or not persisted_created_at or abs(persisted_created_at - pending_created_at) <= 2 * 60 * 1000:
            return True
    return False


async def build_thread_summary(session_file: str) -> dict | None:
    if not session_file:
        return None
    path = Path(session_file)
    signature = get_file_signature(path)
    cached = thread_summary_cache.get(session_file)
    if cached and cached[0] == signature:
        summary = cached[1]
        return {**summary, "runtime": get_runtime_state(summary["id"])}
    raw_text = path.read_text(encoding="utf-8")
    lines = [line for line in raw_text.splitlines() if line]
    thread_id = extract_thread_id_from_filename(session_file)
    created_at = None
    updated_at = None
    cwd = None
    title = None
    preview = None
    message_count = 0
    for line in lines:
        try:
            record = json.loads(line)
        except Exception:
            continue
        timestamp = as_string(record.get("timestamp"))
        if not created_at and timestamp:
            created_at = timestamp
        if timestamp:
            updated_at = timestamp
        if record.get("type") == "session_meta":
            payload = as_record(record.get("payload")) or {}
            thread_id = as_string(payload.get("id")) or as_string(payload.get("thread_id")) or as_string(payload.get("threadId")) or as_string(payload.get("session_id")) or thread_id
            cwd = as_string(payload.get("cwd")) or cwd
            continue
        if record.get("type") != "response_item":
            continue
        payload = as_record(record.get("payload")) or {}
        if payload.get("type") != "message":
            continue
        role = as_string(payload.get("role"))
        if role not in {"user", "assistant"}:
            continue
        text = normalize_history_text(extract_text_content(payload.get("content")) or "")
        if not text or (role == "user" and is_bootstrap_message(text)):
            continue
        message_count += 1
        preview = summarize_text(text)
        if not title and role == "user":
            title = summarize_text(text.split("\n")[0], max_length=72)
    if not thread_id:
        return None
    summary = {"id": thread_id, "title": title or preview or thread_id, "preview": preview or "", "updatedAt": updated_at, "createdAt": created_at, "cwd": cwd, "sessionFile": session_file, "messageCount": message_count}
    thread_summary_cache[session_file] = (signature, summary)
    return {**summary, "runtime": get_runtime_state(thread_id)}


async def list_recent_threads(limit: int = 80) -> list[dict]:
    summaries = []
    for session_file in await list_session_files():
        try:
            summary = await build_thread_summary(session_file)
        except Exception:
            summary = None
        if summary:
            summaries.append(summary)
    summaries.sort(key=lambda item: (timestamp_to_millis(item.get("updatedAt")), item["id"]), reverse=True)
    return summaries[:limit]


async def load_thread_history(thread_id: str) -> dict:
    session_file = await find_session_file_by_thread_id(thread_id)
    if not session_file:
        raise RuntimeError(f"No session file found for thread_id {thread_id}")
    path = Path(session_file)
    signature = get_file_signature(path)
    cached = thread_history_cache.get(session_file)
    if cached and cached[0] == signature:
        history = cached[1]
        return {"threadId": thread_id, "sessionFile": session_file, "messages": history["messages"], "runtime": get_runtime_state(thread_id)}
    raw_text = path.read_text(encoding="utf-8")
    lines = [line for line in raw_text.splitlines() if line]
    messages: list[dict] = []
    terminal_index_by_call_id: dict[str, int] = {}
    for line in lines:
        try:
            record = json.loads(line)
        except Exception:
            continue
        if record.get("type") != "response_item":
            continue
        payload = as_record(record.get("payload")) or {}
        if payload.get("type") == "message":
            role = as_string(payload.get("role"))
            if role not in {"user", "assistant"}:
                continue
            text = extract_text_content(payload.get("content"))
            if not text or (role == "user" and is_bootstrap_message(text)):
                continue
            messages.append({"type": "text", "role": role, "content": normalize_history_text(text), "timestamp": as_string(record.get("timestamp"))})
            continue
        if payload.get("type") == "function_call" and as_string(payload.get("name")) == "shell_command":
            call_id = as_string(payload.get("call_id")) or f"call-{len(messages)}"
            args = parse_shell_call_arguments(payload)
            terminal_index_by_call_id[call_id] = len(messages)
            messages.append({"type": "terminal", "role": "assistant", "timestamp": as_string(record.get("timestamp")), "toolName": "Terminal", "command": args["command"], "workdir": args["workdir"], "output": "", "exitCode": None, "durationMs": None})
            continue
        if payload.get("type") == "function_call_output":
            call_id = as_string(payload.get("call_id"))
            output_info = parse_function_output(as_string(payload.get("output")) or "")
            target_index = terminal_index_by_call_id.get(call_id or "")
            if target_index is not None and target_index < len(messages):
                messages[target_index] = {**messages[target_index], "output": output_info["output"], "exitCode": output_info["exitCode"], "durationMs": output_info["durationMs"], "timestamp": as_string(record.get("timestamp")) or messages[target_index].get("timestamp")}
            else:
                messages.append({"type": "terminal", "role": "assistant", "timestamp": as_string(record.get("timestamp")), "toolName": "Terminal", "command": "", "workdir": "", "output": output_info["output"], "exitCode": output_info["exitCode"], "durationMs": output_info["durationMs"]})
    history = {"sessionFile": session_file, "messages": messages}
    thread_history_cache[session_file] = (signature, history)
    return {"threadId": thread_id, "sessionFile": session_file, "messages": messages, "runtime": get_runtime_state(thread_id)}


async def build_messages_response(thread_id: str) -> dict:
    history = await load_thread_history(thread_id)
    total_messages = len(history["messages"])
    projected = history["messages"][-settings.max_projected_messages :] if total_messages > settings.max_projected_messages else history["messages"]
    persisted = []
    if total_messages > len(projected):
        persisted.append(build_hapi_message(id=f"{thread_id}-projection-note", role="assistant", content=f"Projection limited to the latest {len(projected)} items. {total_messages - len(projected)} older items stay in the native Codex session file.", timestamp=(projected[0].get("timestamp") if projected else None)))
    for index, message in enumerate(projected):
        persisted.append(build_hapi_message(id=f"{thread_id}-persisted-{index}", role=message["role"], content=message.get("content", ""), timestamp=message.get("timestamp"), content_type="terminal" if message.get("type") == "terminal" else "text", extra_content={"command": message.get("command", ""), "workdir": message.get("workdir", ""), "toolName": message.get("toolName", "Terminal"), "output": message.get("output", ""), "exitCode": message.get("exitCode"), "durationMs": message.get("durationMs")} if message.get("type") == "terminal" else None))
    pending = [m for m in get_pending_local_messages(thread_id) if not should_hide_pending_message(m, persisted)]
    messages = [*persisted, *pending]
    return {"messages": messages, "page": {"limit": len(messages), "beforeSeq": None, "nextBeforeSeq": None, "hasMore": False}}
