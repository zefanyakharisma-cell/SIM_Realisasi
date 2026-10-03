'use client';

/**
 * "Mode Demo" preference: per-browser (localStorage), shared between the login page and the app
 * shell, synced across tabs. The server snapshot is always "off" so SSR markup never depends on it.
 */
import * as React from 'react';

const ENABLED_KEY = 'sim-realisasi:demo-guide';
const STEP_KEY = 'sim-realisasi:demo-guide-step';
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
    // Storage unavailable (private mode, blocked): the toggle still works for this page view.
  }
  window.dispatchEvent(new Event(EVENT));
}

// Fallback when storage is blocked, so the switch still responds within the page view.
let memoryEnabled = false;

function subscribe(onChange: () => void): () => void {
  const onStorage = (e: StorageEvent) => {
    if (e.key === ENABLED_KEY || e.key === STEP_KEY) onChange();
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
const getStep = () => read(STEP_KEY) ?? '';
const getServerEnabled = () => false;
const getServerStep = () => '';

export function useDemoGuide() {
  const enabled = React.useSyncExternalStore(subscribe, getEnabled, getServerEnabled);
  const stepId = React.useSyncExternalStore(subscribe, getStep, getServerStep);
  const setEnabled = React.useCallback((on: boolean) => {
    memoryEnabled = on;
    write(ENABLED_KEY, on ? '1' : null);
  }, []);
  const setStepId = React.useCallback((id: string) => write(STEP_KEY, id), []);
  return { enabled, setEnabled, stepId, setStepId };
}
