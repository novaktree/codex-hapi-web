import React, { useMemo, useState } from 'react';
import { formatTimestamp } from '../lib/format';

function TerminalCard({ message }) {
  const metaParts = [];
  if (message.workdir) metaParts.push(message.workdir);
  if (Number.isFinite(message.exitCode)) metaParts.push(`exit ${message.exitCode}`);
  if (Number.isFinite(message.durationMs)) metaParts.push(`${Math.round(message.durationMs)} ms`);
  const isMobile = useMemo(() => window.matchMedia('(max-width: 979px)').matches, []);
  const [collapsed, setCollapsed] = useState(isMobile);

  return (
    <article className="terminal-card">
      <div className="terminal-card-header">
        <div className="terminal-title-wrap">
          <span className="terminal-icon">{'>_'}</span>
          <div>
            <div className="terminal-title">{message.toolName || 'Terminal'}</div>
            <div className="terminal-meta">{metaParts.join('  ') || 'shell command'}</div>
          </div>
        </div>
        <span className={`terminal-badge ${Number.isFinite(message.exitCode) && message.exitCode !== 0 ? 'error' : 'ok'}`}>
          {Number.isFinite(message.exitCode) ? `done ${message.exitCode}` : 'run'}
        </span>
      </div>
      <div className="terminal-collapse-row">
        <button
          type="button"
          className="terminal-toggle"
          onClick={() => setCollapsed((current) => !current)}
          aria-expanded={!collapsed}
        >
          {collapsed ? 'Show terminal details' : 'Hide terminal details'}
        </button>
      </div>
      {!collapsed ? (
        <>
          {message.command ? <pre className="terminal-command">{message.command}</pre> : null}
          {message.output ? <pre className="terminal-output">{message.output}</pre> : null}
        </>
      ) : null}
    </article>
  );
}

export function MessageBubble({ message }) {
  if (message.type === 'terminal') {
    return (
      <div className="message-row agent terminal-row">
        <TerminalCard message={message} />
      </div>
    );
  }

  return (
    <article className={`message-row ${message.role}`}>
      <div className="message-meta">
        <span>{message.role === 'agent' ? 'codex' : 'you'}</span>
        <span>{formatTimestamp(message.createdAt)}</span>
        {message.status ? <span className={`message-status ${message.status}`}>{message.status}</span> : null}
      </div>
      <div className={`message-bubble ${message.role}`}>
        <pre>{message.text || ' '}</pre>
      </div>
    </article>
  );
}
