import { clampMinutes, dayKey, elapsedAt, focusSecondsAt, sessionView } from './session';
import type { Session } from './session';

export type FocusSpan = { at: number; seconds: number; session: string };
export type Task = { id: string; title: string; focusSeconds: number; distractions: number; spans: FocusSpan[] };
export type HistoryTask = Task & { completedAt: number };
type TrackedSession = Session & { id: string; taskId: string | null; creditedFocusSeconds: number; distractionIDs: string[] };
export type State = {
  minutes: number; tasks: Task[]; history: HistoryTask[]; session: TrackedSession | null;
  stats: { day: string; count: number }; sound: boolean;
};
export type Action =
  | { type: 'duration'; minutes: number }
  | { type: 'add'; task: { id: string; title: string }; now: number }
  | { type: 'remove' | 'select'; id: string }
  | { type: 'delete-history'; id: string }
  | { type: 'complete'; id: string; now: number }
  | { type: 'toggle' | 'pause' | 'reset' | 'tick' | 'skip-break'; now: number; sessionId?: string }
  | { type: 'distraction'; sessionId: string; id: string; at: number }
  | { type: 'sound'; enabled: boolean };

export const STORAGE = 'focus-on.v1';
export const initialState = (): State => ({ minutes: 25, tasks: [], history: [], session: null, stats: { day: dayKey(), count: 0 }, sound: false });
export const createID = () => crypto.randomUUID?.() ?? Array.from(crypto.getRandomValues(new Uint32Array(4)), n => n.toString(16)).join('-');
const nonnegative = (value: unknown): number => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;

export function restoreState(saved: unknown): State {
  const initial = initialState();
  if (!saved || typeof saved !== 'object') return initial;
  const data = saved as Record<string, any>;
  if (!Number.isFinite(data.minutes) || !Array.isArray(data.tasks)) return initial;
  function task(value: any): Task | null {
    if (typeof value?.id !== 'string' || typeof value?.title !== 'string' || !value.title.trim()) return null;
    const spans: FocusSpan[] = (Array.isArray(value.spans) ? value.spans : []).flatMap((span: any) =>
      Number.isFinite(span?.at) && span.at > 0 && span.at <= 8.64e15 && Number.isFinite(span?.seconds) && span.seconds > 0 && typeof span?.session === 'string'
        ? [{ at: span.at, seconds: span.seconds, session: span.session }] : []);
    return { id: value.id, title: value.title.slice(0, 160), focusSeconds: nonnegative(value.focusSeconds), distractions: Math.floor(nonnegative(value.distractions)), spans };
  }
  const tasks = data.tasks.map(task).filter((t: Task | null): t is Task => t !== null);
  const history: HistoryTask[] = (Array.isArray(data.history) ? data.history : []).flatMap((value: any) => {
    const parsed = task(value);
    return parsed && Number.isFinite(value.completedAt) && value.completedAt > 0 && value.completedAt <= 8.64e15 ? [{ ...parsed, completedAt: value.completedAt }] : [];
  });
  const s = data.session;
  let session: TrackedSession | null = null;
  if (s && Number.isFinite(s.minutes) && s.minutes >= 1 && s.minutes <= 120 && Number.isFinite(s.elapsed) && s.elapsed >= 0 &&
      (s.startedAt === null || Number.isFinite(s.startedAt)) && typeof s.done === 'boolean') {
    session = {
      minutes: s.minutes, elapsed: s.elapsed, startedAt: s.done ? null : s.startedAt, done: s.done,
      id: typeof s.id === 'string' ? s.id : createID(),
      taskId: s.taskId === null ? null : tasks.find((t: Task) => t.id === s.taskId)?.id ?? tasks[0]?.id ?? null,
      creditedFocusSeconds: Math.min(nonnegative(s.creditedFocusSeconds), focusSecondsAt(s, Date.now())),
      distractionIDs: Array.isArray(s.distractionIDs) ? s.distractionIDs.filter((id: unknown) => typeof id === 'string') : [],
    };
  }
  return { ...initial, minutes: clampMinutes(data.minutes), tasks, history, session, sound: data.sound === true,
    stats: typeof data.stats?.day === 'string' && Number.isInteger(data.stats.count) && data.stats.count >= 0 ? data.stats : initial.stats };
}

export function loadState(): State {
  try { return restoreState(JSON.parse(localStorage.getItem(STORAGE) || 'null')); }
  catch { return initialState(); }
}

/** Settle at lifecycle boundaries; ticks do not write to storage four times a second. */
function settle(state: State, now: number): State {
  const s = state.session;
  if (!s) return state;
  const focused = focusSecondsAt(s, now);
  const added = Math.max(0, focused - s.creditedFocusSeconds);
  const view = sessionView(s, state.minutes, now);
  const ended = !s.done && view.finished;
  const completedAt = s.startedAt === null ? now : s.startedAt + Math.max(0, view.total - s.elapsed) * 1000;
  // Focus belongs to the task even when the task itself is not finished yet: log each span.
  const credit = (task: Task): Task => {
    const endAt = ended ? completedAt : now;
    const last = task.spans[task.spans.length - 1];
    const spans = last?.session === s.id
      ? [...task.spans.slice(0, -1), { ...last, seconds: last.seconds + added }]
      : [...task.spans, { at: endAt - added * 1000, seconds: added, session: s.id }];
    return { ...task, focusSeconds: task.focusSeconds + added, spans };
  };
  return { ...state,
    tasks: added > 0 ? state.tasks.map(task => task.id === s.taskId ? credit(task) : task) : state.tasks,
    session: { ...s, creditedFocusSeconds: focused, ...(ended ? { elapsed: view.total, startedAt: null, done: true } : {}) },
    stats: ended ? { day: dayKey(completedAt), count: (state.stats.day === dayKey(completedAt) ? state.stats.count : 0) + 1 } : state.stats,
  };
}

export function reducer(state: State, action: Action): State {
  switch (action.type) {
    case 'duration': return state.session && !state.session.done ? state : { ...state, minutes: clampMinutes(action.minutes), session: null };
    case 'add': {
      const task = { ...action.task, focusSeconds: 0, distractions: 0, spans: [] };
      // A task added to an anonymous timer only owns time from this point onward.
      const session = state.session && !state.session.done && !state.session.taskId && !state.tasks.length
        ? { ...state.session, taskId: task.id, creditedFocusSeconds: focusSecondsAt(state.session, action.now) } : state.session;
      return { ...state, session, tasks: [...state.tasks, task] };
    }
    case 'remove': return { ...state, tasks: state.tasks.filter(t => t.id !== action.id), session: state.session?.taskId === action.id ? null : state.session };
    case 'delete-history': return { ...state, history: state.history.filter(t => t.id !== action.id) };
    case 'select': return state.session && !state.session.done ? state : { ...state, session: null, tasks: [...state.tasks.filter(t => t.id === action.id), ...state.tasks.filter(t => t.id !== action.id)] };
    case 'complete': {
      if (!state.tasks.some(t => t.id === action.id)) return state;
      const next = settle(state, action.now);
      const task = next.tasks.find(t => t.id === action.id)!;
      return { ...next, tasks: next.tasks.filter(t => t.id !== action.id),
        session: next.session?.taskId === task.id ? null : next.session,
        history: [{ ...task, completedAt: action.now }, ...next.history] };
    }
    case 'sound': return { ...state, sound: action.enabled };
    case 'reset': return { ...settle(state, action.now), session: null };
    case 'skip-break': {
      const s = state.session;
      if (!s || s.done) return state;
      const view = sessionView(s, state.minutes, action.now);
      // Re-evaluate at click time: a delayed or duplicate click must not skip focus.
      if (view.finished || view.phase.kind !== 'break') return state;
      const next = settle(state, action.now);
      const elapsed = view.plan.slice(0, view.index + 1).reduce((sum, phase) => sum + phase.seconds, 0);
      return { ...next, session: { ...next.session!, elapsed, startedAt: action.now } };
    }
    case 'pause': {
      if (state.session?.startedAt == null) return state;
      const next = settle(state, action.now);
      const s = next.session!;
      return { ...next, session: { ...s, elapsed: elapsedAt(s, action.now), startedAt: null } };
    }
    case 'toggle': {
      const next = settle(state, action.now);
      const s = next.session;
      if (!s || s.done) {
        // A fresh session needs at least one minute; native controls reach here too.
        if (next.minutes < 1) return next;
        return { ...next, session: { id: action.sessionId ?? String(action.now), taskId: next.tasks[0]?.id ?? null,
          creditedFocusSeconds: 0, distractionIDs: [], minutes: next.minutes, elapsed: 0, startedAt: action.now, done: false } };
      }
      return { ...next, session: { ...s, elapsed: elapsedAt(s, action.now), startedAt: s.startedAt === null ? action.now : null } };
    }
    case 'tick': return state.session && !state.session.done && sessionView(state.session, state.minutes, action.now).finished ? settle(state, action.now) : state;
    case 'distraction': {
      const s = state.session;
      if (!s || s.done || s.startedAt === null || s.id !== action.sessionId || s.distractionIDs.includes(action.id) ||
          !Number.isFinite(action.at) || action.at < s.startedAt) return state;
      const view = sessionView(s, state.minutes, action.at);
      if (view.finished || view.phase.kind !== 'focus') return state;
      return { ...state, session: { ...s, distractionIDs: [...s.distractionIDs, action.id] },
        tasks: state.tasks.map(task => task.id === s.taskId ? { ...task, distractions: task.distractions + 1 } : task) };
    }
  }
}
