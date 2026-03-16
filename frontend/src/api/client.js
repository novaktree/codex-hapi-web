export async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const data = await response.json();
  if (!response.ok) {
    throw new Error(data?.detail || data?.error?.message || `HTTP ${response.status}`);
  }
  return data;
}

export const api = {
  sessions: () => fetchJson('/api/sessions', { cache: 'no-store' }),
  session: (sessionId) => fetchJson(`/api/sessions/${encodeURIComponent(sessionId)}`, { cache: 'no-store' }),
  messages: (sessionId) => fetchJson(`/api/sessions/${encodeURIComponent(sessionId)}/messages`, { cache: 'no-store' }),
  sendMessage: (sessionId, payload) => fetchJson(`/api/sessions/${encodeURIComponent(sessionId)}/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  }),
  interrupt: (sessionId) => fetchJson(`/api/sessions/${encodeURIComponent(sessionId)}/interrupt`, { method: 'POST' }),
  desktopRefresh: (sessionId) => fetchJson(`/api/sessions/${encodeURIComponent(sessionId)}/desktop-refresh`, { method: 'POST' }),
  upload: (payload) => fetchJson('/api/uploads', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  }),
  transcribe: (payload) => fetchJson('/api/transcriptions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  })
};
