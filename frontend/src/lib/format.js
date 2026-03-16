export const MOBILE_BREAKPOINT = 980;
export const LIST_SCROLL_KEY = 'codex-hapi-projection:list-scroll-top';
export const GROUP_STATE_KEY = 'codex-hapi-projection:collapsed-groups';
export const MAX_ATTACHMENT_INLINE_TEXT = 4000;

export function formatRelativeTime(value) {
  if (!value) return '';
  const ms = value < 1_000_000_000_000 ? value * 1000 : value;
  const delta = Date.now() - ms;
  if (delta < 60_000) return 'just now';
  const minutes = Math.floor(delta / 60_000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(ms).toLocaleDateString('zh-CN', { month: 'numeric', day: 'numeric' });
}

export function formatTimestamp(value) {
  if (!value) return '';
  const ms = value < 1_000_000_000_000 ? value * 1000 : value;
  return new Date(ms).toLocaleString('zh-CN', {
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
}

export function formatBytes(value) {
  const size = Number(value || 0);
  if (!Number.isFinite(size) || size <= 0) return '';
  if (size < 1024) return `${size} B`;
  if (size < 1024 * 1024) return `${(size / 1024).toFixed(1)} KB`;
  return `${(size / (1024 * 1024)).toFixed(1)} MB`;
}

export function summarizeDirectory(directory) {
  if (!directory) return 'Other';
  const parts = directory.split(/[\\/]+/).filter(Boolean);
  if (parts.length <= 2) return parts.join('/');
  return `${parts.at(-2)}/${parts.at(-1)}`;
}

export function dedupeSessions(items) {
  const byId = new Map();
  for (const session of items) {
    const existing = byId.get(session.id);
    if (!existing || Number(session.updatedAt || 0) > Number(existing.updatedAt || 0)) {
      byId.set(session.id, session);
    }
  }
  return [...byId.values()];
}

export function groupSessions(items) {
  const groups = new Map();
  for (const session of items) {
    const directory = session.metadata?.worktree?.basePath || session.metadata?.path || 'Other';
    if (!groups.has(directory)) groups.set(directory, []);
    groups.get(directory).push(session);
  }

  return [...groups.entries()]
    .map(([directory, sessions]) => ({
      directory,
      label: summarizeDirectory(directory),
      sessions: [...sessions].sort((left, right) => Number(right.updatedAt || 0) - Number(left.updatedAt || 0)),
      updatedAt: Math.max(...sessions.map((session) => Number(session.updatedAt || 0)))
    }))
    .sort((left, right) => right.updatedAt - left.updatedAt);
}

export function getHashSessionId() {
  const match = (window.location.hash || '').match(/^#\/sessions\/(.+)$/);
  return match ? decodeURIComponent(match[1]) : null;
}

export function setHashSessionId(sessionId) {
  const nextHash = sessionId ? `#/sessions/${encodeURIComponent(sessionId)}` : '#/sessions';
  if (window.location.hash !== nextHash) {
    window.location.hash = nextHash;
  }
}

export function readCollapsedGroups() {
  try {
    const raw = localStorage.getItem(GROUP_STATE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

export function writeCollapsedGroups(value) {
  localStorage.setItem(GROUP_STATE_KEY, JSON.stringify(value));
}

export function getSessionStatus(session) {
  if (!session) return { label: 'not loaded', tone: 'muted' };
  if (session.thinking || session.active) return { label: 'imagining...', tone: 'thinking' };
  return { label: 'synced', tone: 'idle' };
}

export function normalizeMessages(items) {
  return (items || []).map((message, index) => {
    const content = message?.content?.content || {};
    const type = content.type || 'text';
    return {
      id: message.id || `message-${index}`,
      role: message?.content?.role === 'agent' ? 'agent' : 'user',
      type,
      text: content.text || '',
      createdAt: message.createdAt || Date.now(),
      status: message.status || null,
      command: content.command || '',
      workdir: content.workdir || '',
      toolName: content.toolName || 'Terminal',
      output: content.output || '',
      exitCode: content.exitCode,
      durationMs: content.durationMs
    };
  });
}

