'use client';

/**
 * "Mode Demo" preference and the tours already seen: per-browser (localStorage), shared between
 * the login page and the app shell, synced across tabs. The server snapshot is always "off" so SSR
 * markup never depends on it.
 */
import * as React from 'react';

const ENABLED_KEY = 'sim-realisasi:demo-guide';
const SEEN_KEY = 'sim-realisasi:demo-tours-seen';
const EVENT = 'sim-realisasi:demo-guide-change';

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function write(key: string, value: string | null): void {
  try {
    if (value === null) window.localStorage.removeItem(key);
    else window.localStorage.setItem(key, value);
  } catch {
    // Storage unavailable (private mode, blocked): the in-memory fallback keeps this page view working.
  }
  window.dispatchEvent(new Event(EVENT));
}

// Fallbacks when storage is blocked, so the switch and tours still behave within the page view.
let memoryEnabled = false;
let memorySeen = '[]';

function subscribe(onChange: () => void): () => void {
  const onStorage = (e: StorageEvent) => {
    if (e.key === ENABLED_KEY || e.key === SEEN_KEY) onChange();
  };
  window.addEventListener('storage', onStorage);
  window.addEventListener(EVENT, onChange);
  return () => {
    window.removeEventListener('storage', onStorage);
    window.removeEventListener(EVENT, onChange);
  };
}

const getEnabled = () => {
  const v = read(ENABLED_KEY);
  return v === null ? memoryEnabled : v === '1';
};
const getSeenRaw = () => read(SEEN_KEY) ?? memorySeen;
const getServerEnabled = () => false;
const getServerSeen = () => '[]';

function parseSeen(raw: string): string[] {
  try {
    const v: unknown = JSON.parse(raw);
    return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

function writeSeen(ids: string[]): void {
  memorySeen = JSON.stringify(ids);
  write(SEEN_KEY, memorySeen);
}

export function useDemoGuide() {
  const enabled = React.useSyncExternalStore(subscribe, getEnabled, getServerEnabled);
  const seenRaw = React.useSyncExternalStore(subscribe, getSeenRaw, getServerSeen);
  const seen = React.useMemo(() => new Set(parseSeen(seenRaw)), [seenRaw]);

  const setEnabled = React.useCallback((on: boolean) => {
    memoryEnabled = on;
    // Switching on starts the whole experience again: every page explains itself on its next visit.
    if (on) writeSeen([]);
    write(ENABLED_KEY, on ? '1' : null);
  }, []);
  const markSeen = React.useCallback((id: string) => {
    const ids = parseSeen(getSeenRaw());
    if (!ids.includes(id)) writeSeen([...ids, id]);
  }, []);

  return { enabled, setEnabled, seen, markSeen };
}
