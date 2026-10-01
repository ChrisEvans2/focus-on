import { memo, useRef, useState } from 'react';
import type { KeyboardEvent, PointerEvent } from 'react';
import { angleDelta, clampMinutes, clockText } from './session';

type Props = {
  minutes: number; onChange: (minutes: number) => void; locked: boolean;
  remaining: number; phaseSeconds: number; phase: 'focus' | 'break'; nextPhase?: 'focus' | 'break'; done: boolean;
};
const point = (angle: number, radius: number) => ({ x: 180 + Math.sin(angle * Math.PI / 180) * radius, y: 180 - Math.cos(angle * Math.PI / 180) * radius });
const ticks = Array.from({ length: 60 }, (_, i) => {
  const major = i % 5 === 0;
  const start = point(i * 6, major ? 120 : 126);
  const end = point(i * 6, 132);
  return <line key={i} className={major ? 'tick major' : 'tick'} x1={start.x} y1={start.y} x2={end.x} y2={end.y} />;
});

export const Dial = memo(function Dial({ minutes, onChange, locked, remaining, phaseSeconds, phase, nextPhase, done }: Props) {
  const svg = useRef<SVGSVGElement>(null);
  const drag = useRef<{ angle: number; value: number; pointer: number; bounds: DOMRect } | null>(null);
  const [dragging, setDragging] = useState(false);
  const shownMinutes = locked ? remaining / 60 : minutes;
  const fraction = locked ? remaining / phaseSeconds : Math.min(minutes, 60) / 60;
  const handle = point((locked ? fraction * 60 : minutes) * 6, 151);
  const second = !locked && minutes > 60;
  const showOutcome = locked && !done;
  const outcome = nextPhase === 'break' ? '后休息' : nextPhase === 'focus' ? '后继续' : '后停止';
  function pointerAngle(e: PointerEvent, rect: DOMRect) {
    return (Math.atan2(e.clientX - rect.left - rect.width / 2, -(e.clientY - rect.top - rect.height / 2)) * 180 / Math.PI + 360) % 360;
  }
  function start(e: PointerEvent<SVGSVGElement>) {
    if (locked || e.button !== 0) return;
    const bounds = e.currentTarget.getBoundingClientRect();
    const distance = Math.hypot(e.clientX - bounds.left - bounds.width / 2, e.clientY - bounds.top - bounds.height / 2) / bounds.width * 360;
    if (distance < 132 || distance > 178) return;
    const angle = pointerAngle(e, bounds);
    const delta = Math.abs(angleDelta(angle, (minutes * 6) % 360));
    // Track clicks seek within the current lap; grabbing the thumb never jumps.
    let value = minutes;
    if (delta > 12) {
      value = clampMinutes((minutes > 60 ? 60 : 0) + angle / 6);
      onChange(value);
    }
    drag.current = { angle, value, pointer: e.pointerId, bounds };
    e.currentTarget.setPointerCapture(e.pointerId);
    setDragging(true);
    e.preventDefault();
  }
  function move(e: PointerEvent<SVGSVGElement>) {
    const d = drag.current;
    if (!d || d.pointer !== e.pointerId) return;
    const angle = pointerAngle(e, d.bounds);
    d.value = Math.min(120, Math.max(0, d.value + angleDelta(angle, d.angle) / 6));
    d.angle = angle;
    onChange(clampMinutes(d.value));
  }
  function end() { drag.current = null; setDragging(false); }
  function key(e: KeyboardEvent) {
    if (locked) return;
    const values: Record<string, number> = { ArrowRight: minutes + 1, ArrowUp: minutes + 1, ArrowLeft: minutes - 1, ArrowDown: minutes - 1, PageUp: minutes + 5, PageDown: minutes - 5, Home: 0, End: 120 };
    if (e.key in values) { e.preventDefault(); onChange(clampMinutes(values[e.key])); }
  }
  return <div className={`dial ${dragging ? 'dragging' : ''} ${phase === 'break' && locked ? 'on-break' : ''} ${minutes >= 35 ? 'includes-break' : ''} ${showOutcome ? 'has-outcome' : ''}`}>
    <svg ref={svg} viewBox="0 0 360 360" className="dial-svg" onPointerDown={start} onPointerMove={move} onPointerUp={end} onPointerCancel={end} onLostPointerCapture={end} aria-label="专注时钟">
      <circle className="dial-face" cx="180" cy="180" r="164" />
      <circle className="dial-track" cx="180" cy="180" r="151" />
      <circle className={`dial-progress ${second ? 'first-lap' : ''}`} cx="180" cy="180" r="151" pathLength="100" strokeDasharray={`${fraction * 100} 100`} transform="rotate(-90 180 180)" />
      {second && <circle className="dial-progress second-lap" cx="180" cy="180" r="141" pathLength="100" strokeDasharray={`${(minutes - 60) / 60 * 100} 100`} transform="rotate(-90 180 180)" />}
      <g aria-hidden="true">{ticks}</g>
      {[0, 15, 30, 45].map(n => { const p = point(n * 6, 104); return <text key={n} x={p.x} y={p.y} className="dial-number" dominantBaseline="central" textAnchor="middle">{n === 0 ? '60' : n}</text>; })}
      {!locked && <g className="dial-handle" transform={`translate(${handle.x} ${handle.y})`} role="slider" tabIndex={0} aria-label="专注时长" aria-valuemin={0} aria-valuemax={120} aria-valuenow={minutes} aria-valuetext={`${minutes} 分钟，${minutes > 60 ? '第二圈' : '第一圈'}，${minutes >= 35 ? '含休息' : '无休息'}`} onKeyDown={key}>
        <circle className="handle-hit" r="22" /><circle className="handle-outer" r="13" /><circle className="handle-inner" r="5" />
      </g>}
    </svg>
    <div className="dial-content">
      <strong className="dial-time">{clockText(locked ? remaining : shownMinutes * 60)}</strong>
      {showOutcome && <span className={`dial-outcome ${nextPhase === 'break' ? 'rest-next' : ''}`}>{outcome}</span>}
    </div>
  </div>;
});
