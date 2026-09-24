import { useEffect, useState } from 'react';
import { makePlan } from './session';
import type { Session } from './session';

type MonitorStatus = { code: string; message: string };
declare global {
  interface Window {
    __FOCUS_NATIVE__?: boolean;
    webkit?: { messageHandlers?: { focusOn?: { postMessage: (message: unknown) => void } } };
  }
}
export const isNative = () => window.__FOCUS_NATIVE__ === true;
export function nativeCommand(command: string, extra: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers?.focusOn?.postMessage({ command, ...extra });
}
export type DistractionEvent = { id: string; sessionId: string; at: number };
export function useNativeDistractions(onDistraction: (event: DistractionEvent) => void) {
  useEffect(() => {
    const receive = (event: Event) => {
      const detail = (event as CustomEvent<DistractionEvent>).detail;
      if (isNative() && typeof detail?.id === 'string' && typeof detail.sessionId === 'string' && Number.isFinite(detail.at)) onDistraction(detail);
    };
    window.addEventListener('focus-native-distraction', receive);
    return () => window.removeEventListener('focus-native-distraction', receive);
  }, [onDistraction]);
}
export function useNativeMonitoring(session: Session | null, onPause: () => void, taskTitle: string, minutes: number) {
  const [enabled, setEnabled] = useState(() => {
    try { return localStorage.getItem('focus-on.camera') !== 'off'; } catch { return true; }
  });
  const [status, setStatus] = useState<MonitorStatus>({ code: 'idle', message: '摄像头仅在专注时开启' });
  useEffect(() => {
    const receive = (event: Event) => {
      const detail = (event as CustomEvent<MonitorStatus>).detail;
      if (typeof detail?.code === 'string' && typeof detail?.message === 'string') setStatus(detail);
    };
    window.addEventListener('focus-native-status', receive);
    nativeCommand('ready');
    return () => window.removeEventListener('focus-native-status', receive);
  }, []);
  useEffect(() => {
    window.addEventListener('focus-native-pause', onPause);
    return () => window.removeEventListener('focus-native-pause', onPause);
  }, [onPause]);
  useEffect(() => {
    if (!isNative()) return;
    nativeCommand('sync', { taskTitle, schedule: {
      sessionId: session?.id ?? null,
      running: session?.startedAt != null && !session.done,
      startedAt: session?.startedAt == null ? null : session.startedAt / 1000,
      elapsed: session?.elapsed ?? 0,
      phases: makePlan(session?.minutes ?? minutes),
      monitoring: enabled,
    } });
  }, [session, enabled, taskTitle, minutes]);
  const changeEnabled = (value: boolean) => {
    setEnabled(value);
    try { localStorage.setItem('focus-on.camera', value ? 'on' : 'off'); } catch { /* still works this session */ }
  };
  return { native: isNative(), enabled, setEnabled: changeEnabled, status };
}
