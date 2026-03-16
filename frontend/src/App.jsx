import React, { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { api } from './api/client';
import { ChatPane } from './components/ChatPane';
import { SessionList } from './components/SessionList';
import { useIsMobile, usePolling } from './hooks';
import {
  dedupeSessions,
  formatBytes,
  getHashSessionId,
  groupSessions,
  LIST_SCROLL_KEY,
  normalizeMessages,
  readCollapsedGroups,
  setHashSessionId,
  writeCollapsedGroups
} from './lib/format';
import {
  buildMessagePayload,
  uploadSelectedFiles
} from './lib/files';

export function App() {
  const isMobile = useIsMobile();
  const [selectedSessionId, setSelectedSessionId] = useState(() => getHashSessionId());
  const [sessions, setSessions] = useState([]);
  const [sessionMap, setSessionMap] = useState({});
  const [messages, setMessages] = useState([]);
  const [composerValue, setComposerValue] = useState('');
  const [sending, setSending] = useState(false);
  const [stopping, setStopping] = useState(false);
  const [loadingSession, setLoadingSession] = useState(false);
  const [syncState, setSyncState] = useState({ label: 'syncing', tone: 'syncing' });
  const [collapsedGroups, setCollapsedGroups] = useState(() => readCollapsedGroups());
  const [attachments, setAttachments] = useState([]);
  const [refreshingDesktopThread, setRefreshingDesktopThread] = useState(false);

  const listRef = useRef(null);
  const messagesRef = useRef(null);
  const bottomRef = useRef(null);
  const shouldSnapToBottomRef = useRef(true);
  const fileInputRef = useRef(null);

  const selectedSession = selectedSessionId ? sessionMap[selectedSessionId] || null : null;
  const groupedSessions = useMemo(() => groupSessions(dedupeSessions(sessions)), [sessions]);

  useEffect(() => {
    const onHashChange = () => setSelectedSessionId(getHashSessionId());
    window.addEventListener('hashchange', onHashChange);
    if (!window.location.hash) window.location.hash = '#/sessions';
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);

  useEffect(() => {
    if (!isMobile || selectedSessionId) return;
    const scrollTop = Number(sessionStorage.getItem(LIST_SCROLL_KEY) || 0);
    [0, 40, 120, 260].forEach((delay) => {
      window.setTimeout(() => {
        listRef.current?.scrollTo({ top: scrollTop, behavior: 'auto' });
      }, delay);
    });
  }, [isMobile, selectedSessionId]);

  useLayoutEffect(() => {
    if (!selectedSessionId || !shouldSnapToBottomRef.current) return;
    [0, 40, 120, 260].forEach((delay) => {
      window.setTimeout(() => {
        bottomRef.current?.scrollIntoView({ block: 'end' });
      }, delay);
    });
  }, [selectedSessionId, messages.length]);

  useEffect(() => {
    const element = messagesRef.current;
    if (!element) return undefined;
    const onScroll = () => {
      const remaining = element.scrollHeight - element.scrollTop - element.clientHeight;
      shouldSnapToBottomRef.current = remaining < 72;
    };
    element.addEventListener('scroll', onScroll);
    return () => element.removeEventListener('scroll', onScroll);
  }, [selectedSessionId]);

  async function fetchSessions({ quiet = false } = {}) {
    try {
      const data = await api.sessions();
      const nextSessions = dedupeSessions(data.sessions || []);
      setSessions(nextSessions);
      setSessionMap(Object.fromEntries(nextSessions.map((session) => [session.id, session])));
      setSyncState({ label: quiet ? 'synced' : 'online', tone: 'idle' });
    } catch (error) {
      console.error(error);
      setSyncState({ label: 'offline', tone: 'offline' });
    }
  }

  async function fetchSessionMessages(sessionId, { quiet = false } = {}) {
    if (!sessionId) return;
    setLoadingSession(!quiet);
    try {
      const [sessionData, messagesData] = await Promise.all([
        api.session(sessionId),
        api.messages(sessionId)
      ]);
      setSessionMap((current) => ({ ...current, [sessionId]: sessionData.session }));
      setMessages(normalizeMessages(messagesData.messages));
      setSyncState({ label: quiet ? 'synced' : 'online', tone: 'idle' });
    } catch (error) {
      console.error(error);
      setSyncState({ label: 'sync failed', tone: 'offline' });
    } finally {
      setLoadingSession(false);
    }
  }

  useEffect(() => {
    fetchSessions();
  }, []);

  useEffect(() => {
    if (!selectedSessionId) {
      setMessages([]);
      setAttachments([]);
      return;
    }
    shouldSnapToBottomRef.current = true;
    fetchSessionMessages(selectedSessionId);
  }, [selectedSessionId]);

  usePolling(() => {
    fetchSessions({ quiet: true });
  }, 4000);

  usePolling(() => {
    if (!selectedSessionId) return;
    fetchSessionMessages(selectedSessionId, { quiet: true });
  }, selectedSession?.thinking || sending ? 1500 : selectedSessionId ? 3500 : null);

  async function handleSend() {
    const payload = buildMessagePayload(composerValue, attachments);
    if (!payload.hasContent || !selectedSessionId || sending) return;
    setSending(true);
    const previousComposerValue = composerValue;
    const previousAttachments = attachments;
    setComposerValue('');
    setAttachments([]);
    shouldSnapToBottomRef.current = true;
    try {
      const result = await api.sendMessage(selectedSessionId, {
        text: payload.text,
        attachments: payload.attachments,
        localId: `local-${Date.now()}`
      });
      if (result.interrupted) {
        setSyncState({ label: 'stopped', tone: 'offline' });
      }
      await Promise.all([
        fetchSessionMessages(selectedSessionId, { quiet: true }),
        fetchSessions({ quiet: true })
      ]);
    } catch (error) {
      console.error(error);
      setComposerValue(previousComposerValue);
      setAttachments(previousAttachments);
      setSyncState({ label: 'send failed', tone: 'offline' });
    } finally {
      setSending(false);
    }
  }

  async function handleStop() {
    if (!selectedSessionId || stopping || !(selectedSession?.thinking || sending)) return;
    setStopping(true);
    try {
      await api.interrupt(selectedSessionId);
      setSyncState({ label: 'stopped', tone: 'offline' });
      await Promise.all([
        fetchSessionMessages(selectedSessionId, { quiet: true }),
        fetchSessions({ quiet: true })
      ]);
    } catch (error) {
      console.error(error);
      setSyncState({ label: 'stop failed', tone: 'offline' });
    } finally {
      setSending(false);
      setStopping(false);
    }
  }

  async function handleRefreshDesktopThread() {
    if (!selectedSessionId || refreshingDesktopThread) return;
    const sessionName = selectedSession?.metadata?.name || selectedSessionId;
    const confirmed = window.confirm([
      'Refresh the official Codex desktop thread?',
      '',
      `Title: ${sessionName}`,
      `Thread ID: ${selectedSessionId}`,
      '',
      'This will drive the desktop UI to archive and unarchive the thread.'
    ].join('\n'));

    if (!confirmed) return;

    setRefreshingDesktopThread(true);
    setSyncState({ label: 'refreshing desktop', tone: 'syncing' });
    try {
      await api.desktopRefresh(selectedSessionId);
      await Promise.all([
        fetchSessionMessages(selectedSessionId, { quiet: true }),
        fetchSessions({ quiet: true })
      ]);
      setSyncState({ label: 'synced', tone: 'idle' });
    } catch (error) {
      console.error(error);
      setSyncState({ label: 'desktop refresh failed', tone: 'offline' });
    } finally {
      setRefreshingDesktopThread(false);
    }
  }

  async function handleFileSelection(fileList) {
    const files = [...(fileList || [])];
    if (files.length === 0) return;

    const pending = files.map((file) => ({
      id: `attachment-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      name: file.name,
      type: file.type || 'application/octet-stream',
      size: file.size,
      sizeLabel: formatBytes(file.size),
      status: 'uploading',
      inlineText: '',
      serverFile: null
    }));

    setAttachments((current) => [...current, ...pending]);
    const uploaded = await uploadSelectedFiles(
      files,
      async (payload) => (await api.upload(payload)).file,
      formatBytes
    );
    setAttachments((current) => current.map((item) => uploaded.find((candidate) => candidate.id === item.id) || item));
  }

  function handlePickAttachment() {
    fileInputRef.current?.click();
  }

  function handleRemoveAttachment(id) {
    setAttachments((current) => current.filter((item) => item.id !== id));
  }

  function handleSelect(sessionId) {
    if (isMobile && listRef.current) {
      sessionStorage.setItem(LIST_SCROLL_KEY, String(listRef.current.scrollTop || 0));
    }
    shouldSnapToBottomRef.current = true;
    setHashSessionId(sessionId);
  }

  function handleBack() {
    setHashSessionId(null);
  }

  function handleToggleGroup(directory) {
    setCollapsedGroups((current) => {
      const next = { ...current, [directory]: !current[directory] };
      writeCollapsedGroups(next);
      return next;
    });
  }

  const showListOnly = isMobile && !selectedSessionId;
  const showChatOnly = isMobile && selectedSessionId;

  return (
    <div className="app-shell">
      <aside className={`sidebar ${showChatOnly ? 'mobile-hidden' : ''}`}>
        <div className="sidebar-hero">
          <div>
            <div className="eyebrow">local projection</div>
            <h1>Sessions</h1>
            <p>Codex native sessions stay as the source of truth. This UI is the HAPI-like projection layer.</p>
          </div>
          <div className="hero-badges">
            <span className={`status-pill ${syncState.tone}`}>{syncState.label}</span>
            <span className="status-pill muted">{sessions.length} sessions</span>
          </div>
        </div>
        <SessionList
          groups={groupedSessions}
          selectedSessionId={selectedSessionId}
          collapsedGroups={collapsedGroups}
          onToggleGroup={handleToggleGroup}
          onSelect={handleSelect}
          listRef={listRef}
        />
      </aside>

      <main className={`main-pane ${showListOnly ? 'mobile-hidden' : ''}`}>
        {selectedSession ? (
          <ChatPane
            session={selectedSession}
            messages={messages}
            composerValue={composerValue}
            onComposerChange={setComposerValue}
            onSend={handleSend}
            onStop={handleStop}
            sending={sending}
            stopping={stopping}
            syncState={syncState}
            messagesRef={messagesRef}
            bottomRef={bottomRef}
            onBack={handleBack}
            mobile={isMobile}
            attachments={attachments}
            onRemoveAttachment={handleRemoveAttachment}
            onPickAttachment={handlePickAttachment}
            onRefreshDesktopThread={handleRefreshDesktopThread}
            refreshingDesktopThread={refreshingDesktopThread}
          />
        ) : (
          <div className="empty-shell">
            <div className="empty-state">
              <h2>{loadingSession ? 'Loading session...' : 'Pick a session'}</h2>
              <p>Next step is replacing more of this custom shell with real HAPI components.</p>
            </div>
          </div>
        )}
      </main>
      <input
        ref={fileInputRef}
        type="file"
        hidden
        multiple
        onChange={(event) => {
          handleFileSelection(event.target.files);
          event.target.value = '';
        }}
      />
    </div>
  );
}
