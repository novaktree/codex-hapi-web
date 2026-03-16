from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any

import websockets

from app.core.settings import settings
from app.services.state import active_turn_by_thread_id, get_runtime_state, set_runtime_state


def as_record(value: Any) -> dict | None:
    return value if isinstance(value, dict) else None


def as_string(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def merge_text_delta(previous_text: str, next_delta: str) -> str:
    prev = previous_text or ""
    nxt = next_delta or ""
    if not prev:
        return nxt
    if not nxt or nxt == prev:
        return prev
    if nxt.startswith(prev):
        return nxt
    max_overlap = min(len(prev), len(nxt))
    for size in range(max_overlap, 0, -1):
        if prev[-size:] == nxt[:size]:
            return prev + nxt[size:]
    return prev + nxt


class CodexAppServerClient:
    def __init__(self, endpoint_url: str):
        self.endpoint_url = endpoint_url
        self.websocket = None
        self.next_id = 1
        self.pending: dict[int, asyncio.Future] = {}
        self.notification_handler = None
        self.reader_task = None

    async def connect(self) -> None:
        if self.websocket:
            return
        self.websocket = await websockets.connect(self.endpoint_url, max_size=None)
        self.reader_task = asyncio.create_task(self._reader())

    async def disconnect(self) -> None:
        if self.reader_task:
            self.reader_task.cancel()
        if self.websocket:
            await self.websocket.close()
        self.websocket = None

    async def initialize(self) -> None:
        await self.send_request(
            "initialize",
            {"clientInfo": {"name": "codex-hapi-web", "version": "0.1.0"}},
            timeout=30.0,
        )
        await self.send_notification("initialized")

    async def resume_thread(self, params: dict) -> dict:
        return await self.send_request("thread/resume", params)

    async def start_thread(self, params: dict) -> dict:
        return await self.send_request("thread/start", params)

    async def start_turn(self, params: dict) -> dict:
        return await self.send_request("turn/start", params)

    async def interrupt_turn(self, params: dict) -> dict:
        return await self.send_request("turn/interrupt", params)

    async def send_notification(self, method: str, params: dict | None = None) -> None:
        await self.websocket.send(json.dumps({"method": method, "params": params}))

    async def send_request(self, method: str, params: dict, timeout: float = 14 * 24 * 60 * 60) -> dict:
        if not self.websocket:
            await self.connect()
        message_id = self.next_id
        self.next_id += 1
        future = asyncio.get_running_loop().create_future()
        self.pending[message_id] = future
        await self.websocket.send(json.dumps({"id": message_id, "method": method, "params": params}))
        try:
            return await asyncio.wait_for(future, timeout=timeout)
        finally:
            self.pending.pop(message_id, None)

    async def _reader(self) -> None:
        async for raw in self.websocket:
            message = json.loads(raw)
            record = as_record(message)
            if not record:
                continue
            if "method" in record and "id" not in record:
                if self.notification_handler:
                    await self.notification_handler(record["method"], record.get("params"))
                continue
            future = self.pending.get(record.get("id"))
            if not future or future.done():
                continue
            if record.get("error"):
                error_record = as_record(record["error"]) or {}
                future.set_exception(RuntimeError(as_string(error_record.get("message")) or "Unknown app-server error"))
            else:
                future.set_result(record.get("result") or {})


_cached_endpoint = settings.codex_app_server_url or ""


async def probe_endpoint(endpoint_url: str, timeout: float = 1.2) -> bool:
    try:
        async with websockets.connect(endpoint_url, open_timeout=timeout):
            return True
    except Exception:
        return False


async def resolve_endpoint() -> str:
    global _cached_endpoint
    candidates: list[str] = []
    if settings.codex_app_server_url:
        candidates.append(settings.codex_app_server_url)
    if _cached_endpoint and _cached_endpoint not in candidates:
        candidates.append(_cached_endpoint)
    for endpoint in settings.fallback_endpoints:
        if endpoint not in candidates:
            candidates.append(endpoint)
    for endpoint in candidates:
        if await probe_endpoint(endpoint):
            _cached_endpoint = endpoint
            return endpoint
    raise RuntimeError(f"Failed to connect to codex app-server. Tried: {', '.join(candidates)}")


@dataclass
class TurnCollector:
    timeout_ms: int = 10 * 60 * 1000

    def __post_init__(self) -> None:
        self.agent_message_buffers: dict[str, str] = {}
        self.completed_agent_message_ids: set[str] = set()
        self.assistant_messages: list[str] = []
        self.current_turn_id: str | None = None
        self.future: asyncio.Future = asyncio.get_running_loop().create_future()
        self.timeout_handle = asyncio.get_running_loop().call_later(
            self.timeout_ms / 1000,
            self._finish_error,
            RuntimeError(f"Timed out waiting for Codex turn completion after {self.timeout_ms}ms"),
        )

    def _finish_success(self) -> None:
        if self.future.done():
            return
        self.timeout_handle.cancel()
        self.future.set_result({"turnId": self.current_turn_id, "text": "\n\n".join(self.assistant_messages).strip()})

    def _finish_error(self, error: Exception) -> None:
        if self.future.done():
            return
        self.timeout_handle.cancel()
        self.future.set_exception(error)

    def handle_notification(self, method: str, params: Any) -> None:
        for event in self._unwrap_wrapped_event(method, params):
            event_method = event["method"]
            event_params = as_record(event.get("params")) or {}
            if event_method in {"turn/started", "task_started"}:
                self.current_turn_id = as_string(event_params.get("turnId") or (as_record(event_params.get("turn")) or {}).get("id")) or self.current_turn_id
                continue
            if event_method == "item/agentMessage/delta":
                item_id = as_string(event_params.get("itemId") or event_params.get("item_id"))
                delta = as_string(event_params.get("delta"))
                if item_id and delta:
                    self.agent_message_buffers[item_id] = merge_text_delta(self.agent_message_buffers.get(item_id, ""), delta)
                continue
            if event_method == "item/completed":
                item = as_record(event_params.get("item")) or event_params
                item_id = as_string(event_params.get("itemId") or item.get("id") or item.get("itemId"))
                item_type = (as_string(item.get("type")) or "").lower().replace("_", "").replace("-", "").replace(" ", "")
                if item_type == "agentmessage" and item_id and item_id not in self.completed_agent_message_ids:
                    text = as_string(item.get("text") or item.get("message")) or self.agent_message_buffers.get(item_id)
                    if text:
                        self.assistant_messages.append(text)
                    self.completed_agent_message_ids.add(item_id)
                continue
            if event_method in {"turn/completed", "task_complete"}:
                self._finish_success()
                continue
            if event_method == "turn_aborted":
                self._finish_error(RuntimeError("Codex turn was interrupted"))
                continue
            if event_method == "task_failed":
                self._finish_error(RuntimeError(as_string(event_params.get("error")) or "Codex turn failed"))

    def _unwrap_wrapped_event(self, method: str, params: Any) -> list[dict]:
        if not method.startswith("codex/event/"):
            return [{"method": method, "params": params}]
        params_record = as_record(params) or {}
        msg = as_record(params_record.get("msg")) or {}
        msg_type = as_string(msg.get("type"))
        if not msg_type:
            return []
        if msg_type in {"item_started", "item_completed"}:
            return [{
                "method": "item/started" if msg_type == "item_started" else "item/completed",
                "params": {
                    "item": as_record(msg.get("item")) or {},
                    "itemId": as_string(msg.get("item_id") or msg.get("itemId")),
                    "turnId": as_string(msg.get("turn_id") or msg.get("turnId")),
                },
            }]
        if msg_type in {"task_started", "task_complete", "turn_aborted", "task_failed"}:
            return [{
                "method": msg_type,
                "params": {"turnId": as_string(msg.get("turn_id") or msg.get("turnId")), "error": as_string(msg.get("error") or msg.get("message"))},
            }]
        if msg_type in {"agent_message_delta", "agent_message_content_delta"}:
            return [{
                "method": "item/agentMessage/delta",
                "params": {"itemId": as_string(msg.get("item_id") or msg.get("itemId") or msg.get("id")), "delta": as_string(msg.get("delta") or msg.get("text") or msg.get("message"))},
            }]
        if msg_type == "error":
            return [{"method": "task_failed", "params": {"error": as_string(msg.get("message") or (as_record(msg.get("error")) or {}).get("message"))}}]
        return []


async def run_codex_turn(*, thread_id: str | None, message: str, model: str | None = None) -> dict:
    endpoint = await resolve_endpoint()
    client = CodexAppServerClient(endpoint)
    collector = TurnCollector()
    final_thread_id = thread_id

    async def notification_handler(method: str, params: Any) -> None:
        collector.handle_notification(method, params)

    client.notification_handler = notification_handler
    try:
        await client.connect()
        await client.initialize()
        effective_thread_id = thread_id
        if effective_thread_id:
            final_thread_id = effective_thread_id
            set_runtime_state(effective_thread_id, {"state": "thinking", "label": "thinking"})
            resume_response = await client.resume_thread({"threadId": effective_thread_id})
            resumed_thread = as_record(as_record(resume_response).get("thread")) if as_record(resume_response) else None
            effective_thread_id = as_string((resumed_thread or {}).get("id")) or effective_thread_id
        else:
            thread_response = await client.start_thread({**({"model": model} if model else {})})
            new_thread = as_record(as_record(thread_response).get("thread")) if as_record(thread_response) else None
            effective_thread_id = as_string((new_thread or {}).get("id"))
            if not effective_thread_id:
                raise RuntimeError("thread/start did not return thread.id")
            final_thread_id = effective_thread_id
            set_runtime_state(effective_thread_id, {"state": "thinking", "label": "thinking"})

        turn_response = await client.start_turn({"threadId": effective_thread_id, "input": [{"type": "text", "text": message}], **({"model": model} if model else {})})
        turn = as_record(as_record(turn_response).get("turn")) if as_record(turn_response) else None
        turn_id = as_string((turn or {}).get("id"))
        if turn_id:
            active_turn_by_thread_id[effective_thread_id] = {"threadId": effective_thread_id, "turnId": turn_id, "endpointUrl": endpoint}
            set_runtime_state(effective_thread_id, {"turnId": turn_id})

        result = await collector.future
        set_runtime_state(effective_thread_id, {"state": "idle", "label": "idle", "error": None, "turnId": None})
        return {"threadId": effective_thread_id, "turnId": result.get("turnId") or turn_id, "text": result.get("text") or "", "runtime": get_runtime_state(effective_thread_id)}
    except Exception as error:
        if final_thread_id:
            set_runtime_state(final_thread_id, {"state": "failed", "label": "failed", "error": str(error), "turnId": None})
        raise
    finally:
        if final_thread_id:
            active_turn_by_thread_id.pop(final_thread_id, None)
        await client.disconnect()


async def interrupt_thread_turn(thread_id: str) -> dict:
    active_turn = active_turn_by_thread_id.get(thread_id)
    if not active_turn:
        return {"ok": False, "reason": "No active turn"}
    client = CodexAppServerClient(active_turn["endpointUrl"] or await resolve_endpoint())
    try:
        await client.connect()
        await client.initialize()
        await client.interrupt_turn({"threadId": active_turn["threadId"], "turnId": active_turn["turnId"]})
        active_turn_by_thread_id.pop(thread_id, None)
        set_runtime_state(thread_id, {"state": "idle", "label": "idle", "error": None, "turnId": None})
        return {"ok": True}
    finally:
        await client.disconnect()
