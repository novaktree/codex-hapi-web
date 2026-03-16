from __future__ import annotations

from typing import Any


runtime_state_by_thread_id: dict[str, dict[str, Any]] = {}
pending_local_messages_by_thread_id: dict[str, list[dict[str, Any]]] = {}
active_turn_by_thread_id: dict[str, dict[str, Any]] = {}


def get_runtime_state(thread_id: str) -> dict[str, Any]:
    runtime = runtime_state_by_thread_id.get(thread_id)
    if not runtime:
        return {"active": False, "thinking": False, "state": "idle", "label": "idle"}
    return {
        "active": runtime.get("state") == "thinking",
        "thinking": runtime.get("state") == "thinking",
        "state": runtime.get("state"),
        "label": runtime.get("label"),
        "startedAt": runtime.get("startedAt"),
        "updatedAt": runtime.get("updatedAt"),
        "error": runtime.get("error"),
    }


def set_runtime_state(thread_id: str, next_state: dict[str, Any]) -> None:
    if not thread_id:
        return
    current = runtime_state_by_thread_id.get(thread_id, {})
    runtime_state_by_thread_id[thread_id] = {**current, **next_state}


def get_pending_local_messages(thread_id: str) -> list[dict[str, Any]]:
    return pending_local_messages_by_thread_id.get(thread_id, [])


def add_pending_local_message(thread_id: str, message: dict[str, Any]) -> None:
    if not thread_id:
        return
    pending_local_messages_by_thread_id[thread_id] = [*get_pending_local_messages(thread_id), message]


def remove_pending_local_message(thread_id: str, local_id: str) -> None:
    if not thread_id or not local_id:
        return
    next_messages = [m for m in get_pending_local_messages(thread_id) if m.get("localId") != local_id]
    if next_messages:
        pending_local_messages_by_thread_id[thread_id] = next_messages
    else:
        pending_local_messages_by_thread_id.pop(thread_id, None)
