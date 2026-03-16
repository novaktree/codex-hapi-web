import React from 'react';
import { getSessionStatus } from '../lib/format';
import { MessageBubble } from './MessageBubble';

function AttachmentChip({ item, onRemove }) {
  return (
    <div className={`attachment-chip ${item.status}`}>
      <div className="attachment-chip-main">
        <span className="attachment-chip-name">{item.name}</span>
        <span className="attachment-chip-meta">{item.sizeLabel || item.status}</span>
      </div>
      <button type="button" className="attachment-chip-remove" onClick={() => onRemove(item.id)}>
        x
      </button>
    </div>
  );
}

export function ChatPane({
  session,
  messages,
  composerValue,
  onComposerChange,
  onSend,
  onStop,
  sending,
  stopping,
  syncState,
  messagesRef,
  bottomRef,
  onBack,
  mobile,
  attachments,
  onRemoveAttachment,
  onPickAttachment,
  onRefreshDesktopThread,
  refreshingDesktopThread
}) {
  const hasReadyAttachment = attachments.some((item) => item.status === 'ready');
  const hasUploadingAttachment = attachments.some((item) => item.status === 'uploading');
  const canSend = !sending && !hasUploadingAttachment && (Boolean(composerValue.trim()) || hasReadyAttachment);

  return (
    <div className="chat-shell">
      <header className="chat-header">
        <div className="chat-header-top">
          {mobile ? (
            <button className="ghost-button" type="button" onClick={onBack}>
              ←
            </button>
          ) : <span />}
          <div className="header-status-row">
            <button className="ghost-button" type="button" onClick={onRefreshDesktopThread} disabled={refreshingDesktopThread}>
              {refreshingDesktopThread ? 'Refreshing Desktop' : 'Refresh Desktop'}
            </button>
            <span className={`status-pill ${syncState.tone}`}>{syncState.label}</span>
          </div>
        </div>
        <div className="chat-title-row">
          <div className="chat-title">{session?.metadata?.name || 'Select a session'}</div>
          <div className="chat-title-meta">
            <span className="header-meta">codex</span>
            <span className="header-meta">mode: default</span>
          </div>
        </div>
        <div className="chat-subtitle">{session?.metadata?.path || 'Codex native session projection'}</div>
      </header>

      <div className="chat-scroll" ref={messagesRef}>
        <div className="chat-scroll-inner">
          {messages.length === 0 ? (
            <div className="empty-state">
              <h2>No messages yet</h2>
              <p>Select a session, then this panel will show the thread transcript and terminal cards.</p>
            </div>
          ) : (
            messages.map((message) => <MessageBubble key={message.id} message={message} />)
          )}
          <div ref={bottomRef} />
        </div>
      </div>

      <div className="thinking-row">{session?.thinking || sending ? 'imagining...' : 'ready'}</div>

      <form
        className="composer"
        onSubmit={(event) => {
          event.preventDefault();
          onSend();
        }}
      >
        <div className="composer-shell">
          {attachments.length > 0 ? (
            <div className="attachment-row">
              {attachments.map((item) => (
                <AttachmentChip key={item.id} item={item} onRemove={onRemoveAttachment} />
              ))}
            </div>
          ) : null}
          <textarea
            value={composerValue}
            onChange={(event) => onComposerChange(event.target.value)}
            placeholder="Type a message..."
            rows={1}
          />
          <div className="composer-toolbar">
            <div className="composer-actions">
              <button className="composer-icon-button" type="button" onClick={onPickAttachment} title="Attach file">
                +
              </button>
              <button
                className="composer-icon-button stop"
                type="button"
                onClick={onStop}
                disabled={stopping || !(session?.thinking || sending)}
                title="Stop current turn"
              >
                Stop
              </button>
            </div>
            <button
              className="send-button inline"
              type="submit"
              disabled={!canSend}
            >
              {sending ? 'Sending' : 'Send'}
            </button>
          </div>
        </div>
      </form>
    </div>
  );
}
