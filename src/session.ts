export type Phase = { kind: 'focus' | 'break'; seconds: number };
export type Session = { minutes: number; elapsed: number; startedAt: number | null; done: boolean; id?: string };
export const clampMinutes = (n: number) => Math.min(120, Math.max(1, Math.round(n)));

export function makePlan(minutes: number): Phase[] {
  const totalMinutes = clampMinutes(minutes);
  if (totalMinutes < 35) return [{ kind: 'focus', seconds: totalMinutes * 60 }];
  // n focus blocks plus n - 1 five-minute breaks must fit the selected total.
  const blocks = Math.max(2, Math.ceil((totalMinutes + 5) / 30));
  const focusSeconds = (totalMinutes - (blocks - 1) * 5) * 60 / blocks;
  return Array.from({ length: blocks * 2 - 1 }, (_, index) => ({
    kind: index % 2 === 0 ? 'focus' : 'break',
    seconds: index % 2 === 0 ? focusSeconds : 300,
  }));
}

export function elapsedAt(session: Session, now: number) {
  return session.elapsed + (session.startedAt === null ? 0 : Math.max(0, now - session.startedAt) / 1000);
}

/** Count only elapsed focus phases, capped at the plan's end. */
export function focusSecondsAt(session: Session, now: number) {
  let remaining = elapsedAt(session, now);
  let focused = 0;
  for (const phase of makePlan(session.minutes)) {
    const used = Math.max(0, Math.min(remaining, phase.seconds));
    if (phase.kind === 'focus') focused += used;
    remaining -= used;
  }
  return focused;
}

export function sessionView(session: Session | null, minutes: number, now: number) {
  const plan = makePlan(session?.minutes ?? minutes);
  let elapsed = session ? elapsedAt(session, now) : 0;
  const total = plan.reduce((sum, phase) => sum + phase.seconds, 0);
  const finished = elapsed >= total;
  let index = 0;
  while (index < plan.length - 1 && elapsed >= plan[index].seconds) {
    elapsed -= plan[index].seconds;
    index++;
  }
  return { plan, index, phase: plan[index], remaining: Math.max(0, Math.ceil(plan[index].seconds - elapsed)), finished, total };
}

export function clockText(seconds: number) {
  return `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;
}

// Shortest angular delta preserves continuity when crossing twelve o'clock.
export function angleDelta(current: number, previous: number) {
  return ((current - previous + 540) % 360) - 180;
}

export function dayKey(now = Date.now()) {
  const d = new Date(now);
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}
