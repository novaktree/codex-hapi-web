import React from 'react';
import { formatRelativeTime, getSessionStatus } from '../lib/format';

function StatusDot({ tone }) {
  return <span className={`status-dot ${tone}`} aria-hidden="true" />;
}

export function SessionList({ groups, selectedSessionId, collapsedGroups, onToggleGroup, onSelect, listRef }) {
  return (
    <div className="session-list-scroll" ref={listRef}>
      <div className="session-list-content">
        {groups.map((group) => {
          const collapsed = Boolean(collapsedGroups[group.directory]);
          return (
            <section className="group-card" key={group.directory}>
              <button className="group-header" onClick={() => onToggleGroup(group.directory)} type="button">
                <span className={`group-chevron ${collapsed ? '' : 'expanded'}`}>{'>'}</span>
                <div className="group-heading">
                  <div className="group-title">{group.label}</div>
                  <div className="group-subtitle">{group.directory}</div>
                </div>
                <div className="group-meta">{group.sessions.length}</div>
              </button>
              {!collapsed ? (
                <div className="group-sessions">
                  {group.sessions.map((session) => {
                    const status = getSessionStatus(session);
                    return (
                      <button
                        type="button"
                        key={session.id}
                        className={`session-card ${selectedSessionId === session.id ? 'selected' : ''}`}
                        onClick={() => onSelect(session.id)}
                      >
                        <div className="session-card-row">
                          <div className="session-card-title-wrap">
                            <StatusDot tone={status.tone} />
                            <div className="session-card-title">{session.metadata?.name || session.id.slice(0, 8)}</div>
                          </div>
                          <div className={`status-pill ${status.tone}`}>{status.label}</div>
                        </div>
                        <div className="session-card-summary">
                          {session.metadata?.summary?.text || session.metadata?.path || 'No preview'}
                        </div>
                        <div className="session-card-footer">
                          <span>{session.metadata?.worktree?.name || session.metadata?.path || 'Local'}</span>
                          <span>{formatRelativeTime(session.updatedAt)}</span>
                        </div>
                      </button>
                    );
                  })}
                </div>
              ) : null}
            </section>
          );
        })}
      </div>
    </div>
  );
}

