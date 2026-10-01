import React, { useEffect, useReducer, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { AnimatePresence, motion, MotionConfig, useReducedMotion } from 'motion/react';
import { ArrowElbowDownLeft, Check, GearSix, Minus, Pause, PencilSimple, Play, Plus, ArrowCounterClockwise, Medal, List, X, SkipForward } from '@phosphor-icons/react';
import { Dial } from './Dial';
import { dayKey, sessionView } from './session';
import { HistoryPanel } from './HistoryPanel';
import { createID, loadState, reducer, STORAGE } from './store';
import type { Action, Task } from './store';
import { applyTheme, loadTheme, saveTheme } from './theme';
import type { Theme } from './theme';
import './styles.css';
import { isNative, nativeCommand, useNativeDistractions, useNativeMonitoring } from './native';

function TaskQueue({ tasks, locked, dispatch }: { tasks: Task[]; locked: boolean; dispatch: React.Dispatch<Action> }) {
  const list = useRef<HTMLDivElement>(null);
  const [moreBelow, setMoreBelow] = useState(tasks.length > 4);
  function updateShadow() {
    const el = list.current;
    setMoreBelow(!!el && tasks.length > 4 && el.scrollHeight - el.scrollTop - el.clientHeight > 1);
  }
  useEffect(updateShadow, [tasks.length]);
  return <div className={`queue${moreBelow ? ' has-more' : ''}`}>
    <div ref={list} className="queue-list" onScroll={updateShadow} role="region" aria-label="接下来要做的任务" tabIndex={0}>
      {tasks.map(task => <div className="queue-item" key={task.id}>
        <button className="queue-select" disabled={locked} onClick={() => dispatch({ type: 'select', id: task.id })} title={task.title}>
          <span className="queue-dot" /><span className="queue-title">{task.title}</span>
        </button>
        <button className="icon-button" aria-label={`删除任务：${task.title}`} onClick={() => dispatch({ type: 'remove', id: task.id })}><X size={15} /></button>
      </div>)}
    </div>
  </div>;
}

function App() {
  const [state, dispatch] = useReducer(reducer, undefined, loadState);
  const [theme, setTheme] = useState(loadTheme);
  const [draft, setDraft] = useState('');
  const [focusMode, setFocusMode] = useState<'pointer' | 'keyboard'>('keyboard');
  const [historyOpen, setHistoryOpen] = useState(false);
  const [historyMounted, setHistoryMounted] = useState(false);
  const [sliding, setSliding] = useState(false);
  const reducedMotion = useReducedMotion();
  function openHistory() {
    setHistoryMounted(true); setSliding(true); setHistoryOpen(true);
  }
  const historyButton = useRef<HTMLButtonElement>(null);
  function closeHistory() {
    setSliding(true); setHistoryOpen(false);
  }
  const [now, setNow] = useState(Date.now());
  const [notice, setNotice] = useState('');
  const dialog = useRef<HTMLDialogElement>(null);
  const audio = useRef<AudioContext | null>(null);
  const previousPhase = useRef('');
  const hasTasks = state.tasks.length > 0;
  const running = state.session?.startedAt != null;
  const locked = !!state.session && !state.session.done;
  const view = sessionView(state.session, state.minutes, now);
  const resting = locked && view.phase.kind === 'break';
  const current = state.tasks[0];
  const phaseKey = state.session ? `${view.index}:${state.session.done}` : '';
  const monitor = useNativeMonitoring(state.session, () => {
    const time = Date.now(); setNow(time); dispatch({ type: 'pause', now: time });
  }, current?.title ?? '', state.minutes);

  useNativeDistractions(event => dispatch({ type: 'distraction', ...event }));

  useEffect(() => {
    const control = (event: Event) => {
      if (!isNative()) return;
      const action = (event as CustomEvent<{ action?: string }>).detail?.action;
      if (action !== 'toggle' && action !== 'reset' && action !== 'skip-break') return;
      const time = Date.now();
      setNow(time);
      // Menu-bar controls affect the saved session without submitting an unfinished draft.
      dispatch({ type: action, now: time, sessionId: createID() });
    };
    window.addEventListener('focus-native-control', control);
    return () => window.removeEventListener('focus-native-control', control);
  }, []);

  useEffect(() => { try { localStorage.setItem(STORAGE, JSON.stringify(state)); } catch { setNotice('浏览器未允许保存，当前页面仍可正常使用'); } }, [state]);
  useEffect(() => {
    if (!running) return;
    const update = () => { const time = Date.now(); setNow(time); dispatch({ type: 'tick', now: time }); };
    update();
    const id = window.setInterval(update, 250);
    document.addEventListener('visibilitychange', update);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', update); };
  }, [running]);
  useEffect(() => { if (!notice) return; const timer = setTimeout(() => setNotice(''), 3000); return () => clearTimeout(timer); }, [notice]);
  useEffect(() => {
    if (phaseKey && previousPhase.current && phaseKey !== previousPhase.current && state.sound && audio.current) {
      const ctx = audio.current;
      const oscillator = ctx.createOscillator(); const gain = ctx.createGain();
      oscillator.connect(gain); gain.connect(ctx.destination);
      oscillator.frequency.value = 660; gain.gain.setValueAtTime(0.07, ctx.currentTime); gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.8);
      oscillator.start(); oscillator.stop(ctx.currentTime + 0.8);
    }
    previousPhase.current = phaseKey;
  }, [phaseKey, state.sound]);
  function toggle() {
    if (resting) {
      const time = Date.now(); setNow(time); dispatch({ type: 'skip-break', now: time });
      return;
    }
    // Starting a fresh session needs at least one minute; the button is disabled then too.
    if (!locked && state.minutes < 1) return;
    if (state.sound) { audio.current ??= new AudioContext(); void audio.current.resume(); }
    const time = Date.now();
    // Submit a draft on start/resume; pausing must leave unfinished input alone.
    if (!running && draft.trim()) {
      dispatch({ type: 'add', task: { id: createID(), title: draft.trim() }, now: time });
      setDraft('');
    }
    setNow(time); dispatch({ type: 'toggle', now: time, sessionId: createID() });
  }
  useEffect(() => {
    const key = (e: globalThis.KeyboardEvent) => {
      if (dialog.current?.open || e.isComposing) return;
      if (historyOpen && e.key === 'Escape') { e.preventDefault(); closeHistory(); return; }
      if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') { e.preventDefault(); toggle(); }
    };
    window.addEventListener('keydown', key); return () => window.removeEventListener('keydown', key);
  });
  function addTask(e: React.FormEvent) {
    e.preventDefault();
    if (!draft.trim()) return;
    dispatch({ type: 'add', task: { id: createID(), title: draft.trim() }, now: Date.now() }); setDraft('');
  }
  const duration = (minutes: number) => dispatch({ type: 'duration', minutes });

  function renderComposer() {
    return <div className="composer-section">
            <form onSubmit={addTask} className="task-form">
              <label htmlFor="task-input" className="sr-only">{hasTasks ? '添加下一个任务' : '当前要专注的任务'}</label>
              {hasTasks ? <Plus size={20} /> : <PencilSimple size={22} />}
              <input id="task-input" value={draft} onChange={e => setDraft(e.target.value)} onKeyDown={e => { if (e.nativeEvent.isComposing && e.key === 'Enter') e.preventDefault(); }} maxLength={160} autoComplete="off" placeholder="接下来要做什么" />
              <button type="submit" className="submit-task" aria-label="添加任务" disabled={!draft.trim()}><ArrowElbowDownLeft size={19} /></button>
            </form>
          </div>;
  }

  return <MotionConfig reducedMotion="user" transition={{ type: 'spring', stiffness: 240, damping: 30 }}>
    <div className="app-shell" data-focus-mode={focusMode}
      onPointerDownCapture={() => setFocusMode('pointer')}
      onKeyDownCapture={event => {
        if (!['Shift', 'Control', 'Alt', 'Meta'].includes(event.key)) setFocusMode('keyboard');
      }}>
      <div className={`page-viewport${historyOpen ? ' is-history' : ''}`}>
      <motion.div className="page-track" initial={false} animate={{ y: historyOpen ? '-100%' : '0%' }}
        transition={{ type: 'tween', duration: reducedMotion ? 0 : 0.55, ease: [0.65, 0, 0.35, 1] }}
        onAnimationComplete={() => {
          if (!sliding) return;
          setSliding(false);
          if (historyOpen) document.getElementById('history-heading')?.focus({ preventScroll: true });
          else {
            setHistoryMounted(false);
            historyButton.current?.focus({ preventScroll: true });
          }
        }}>
      <div className={`home-page${historyOpen && !sliding ? ' page-inactive' : ''}`} inert={historyOpen} aria-hidden={historyOpen}>
      <header className="app-header">
        <div className="brand"><span className="brand-symbol"><span /></span><span className="brand-en">focus on</span></div>
        <div className="header-actions">
          {monitor.native && <span className={`monitor-status monitor-${monitor.status.code}`} title={monitor.enabled ? monitor.status.message : '仅计时 · 摄像头已关闭'}>
            <span className="monitor-dot" aria-hidden="true" />{!monitor.enabled ? '仅计时' : monitor.status.code === 'focused' ? '本地监测中' : monitor.status.code === 'suspected' ? '正在确认偏离' : monitor.status.code === 'idle' ? '摄像头已关闭' : monitor.status.code === 'calibrating' ? '自动适应中' : ['denied', 'unavailable'].includes(monitor.status.code) ? '监测未开启' : monitor.status.code === 'permission' ? '等待摄像头权限' : monitor.status.code === 'unknown' ? '暂时无法判断' : '看回屏幕就好'}
          </span>}
          {monitor.native && <button className="icon-button minimize-button" aria-label="最小化到菜单栏" title="最小化到菜单栏，计时继续" onClick={() => nativeCommand('minimizeToMenuBar')}><Minus size={22} /></button>}
        <button className="icon-button settings-button" aria-label="设置" onClick={() => dialog.current?.showModal()}><GearSix size={22} /></button></div>
      </header>
      <main className={`main${hasTasks ? ' has-tasks' : ''}`}>
        <div className="workspace">
          <AnimatePresence>
            {hasTasks && <motion.section className="task-section" initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: 8 }} transition={{ duration: 0.3 }} aria-label="任务列表">
              <div className="current-task">
                <h1>{current.title}</h1>
                <button className="complete-task" aria-label={`完成任务：${current.title}`} onClick={() => { dispatch({ type: 'complete', id: current.id, now: Date.now() }); setNotice('又完成了一件事，做得很好。'); }}><Check size={21} /></button>
              </div>
              {state.tasks.length > 1 && <TaskQueue tasks={state.tasks.slice(1)} locked={locked} dispatch={dispatch} />}
            </motion.section>}
          </AnimatePresence>

          <motion.section layout className="timer-section" aria-label="专注计时器">
            <Dial minutes={state.minutes} onChange={duration} locked={locked || !!state.session?.done} remaining={view.remaining} phaseSeconds={view.phase.seconds} phase={view.phase.kind} nextPhase={view.plan[view.index + 1]?.kind} done={!!state.session?.done} />
            <div className="timer-adjust" style={resting ? { visibility: 'hidden' } : undefined}>
              <button className="adjust-button" aria-label="减少 5 分钟" disabled={locked || state.minutes <= 0} onClick={() => duration(state.minutes - 5)}><Minus size={16} /></button>
              <button className="adjust-button" aria-label="增加 5 分钟" disabled={locked || state.minutes >= 120} onClick={() => duration(state.minutes + 5)}><Plus size={16} /></button>
            </div>
          </motion.section>
        </div>
        {renderComposer()}

        <div className="session-controls">
          <div className="action-row">
            <button className={`start-button${resting ? ' rest-button' : ''}`} disabled={!locked && state.minutes < 1} onClick={toggle}>{resting ? <SkipForward size={20} weight="fill" /> : running ? <Pause size={20} weight="fill" /> : <Play size={20} weight="fill" />}<span>{resting ? '跳过休息' : running ? '暂停任务' : locked ? '继续任务' : '开始任务'}</span></button>
            {state.session && !resting && <button className="reset-button icon-button" aria-label="重置计时" onClick={() => { dispatch({ type: 'reset', now: Date.now() }); setNotice('计时已重置'); }}><ArrowCounterClockwise size={21} /></button>}
          </div>
        </div>
        <footer className="app-footer"><span><Medal size={18} />今日已完成 <strong>{state.stats.day === dayKey(now) ? state.stats.count : 0}</strong> 次专注</span>
          <button ref={historyButton} className="icon-button history-toggle" aria-label="查看历史任务" title="查看历史任务" aria-expanded={historyOpen} aria-controls={historyOpen ? 'task-history' : undefined} onClick={openHistory}><List size={21} /></button>
        </footer>
      </main>
      </div>
      {historyMounted && <div className="history-page" inert={!historyOpen} aria-hidden={!historyOpen}>
        <HistoryPanel tasks={state.history} onClose={closeHistory} onDelete={id => { dispatch({ type: 'delete-history', id }); setNotice('历史记录已删除'); }} />
      </div>}
      </motion.div>
      </div>
      <div className="sr-only" role="status" aria-live="polite">{state.session?.done ? '本次专注已完成' : locked ? view.phase.kind === 'break' ? '进入五分钟休息' : `第 ${Math.floor(view.index / 2) + 1} 段专注${running ? '进行中' : '已暂停'}` : ''}</div>
      <div className="sr-only" role="status">{notice}</div>
      <dialog ref={dialog} className="settings-dialog" onClick={e => { if (e.target === dialog.current) dialog.current.close(); }}>
        <div className="dialog-heading"><h2>专注偏好</h2><button className="icon-button" aria-label="关闭设置" onClick={() => dialog.current?.close()}><X size={20} /></button></div>
        <div className="theme-setting"><span>外观主题</span>
          <div className="theme-options" role="radiogroup" aria-label="外观主题">
            {(['light', 'dark'] as Theme[]).map(value => <label className="theme-option" key={value}>
              <input className="sr-only" type="radio" name="theme" value={value} checked={theme === value}
                onChange={() => { saveTheme(value); setTheme(value); }} />
              <span>{value === 'light' ? '浅色' : '深色'}</span>
            </label>)}
          </div>
        </div>
        <label className="setting-row"><span><strong>阶段结束提示音</strong><small>专注或休息结束时，轻声提醒。</small></span><input type="checkbox" role="switch" checked={state.sound} onChange={e => { dispatch({ type: 'sound', enabled: e.target.checked }); if (e.target.checked) { audio.current ??= new AudioContext(); void audio.current.resume(); } }} /></label>
        <div className="settings-info"><span>总时长包含休息</span><p>满 35 分钟后自动分段，每段专注不超过 25 分钟，段间休息 5 分钟。休息结束后自动继续。</p></div>
        <div className="settings-info camera-settings">
          {monitor.native ? <>
            <label className="setting-row"><span><strong>摄像头专注提醒</strong><small>持续偏离屏幕时，宠物轻轻提醒你。</small></span><input type="checkbox" role="switch" aria-label="摄像头专注提醒" checked={monitor.enabled} onChange={e => monitor.setEnabled(e.target.checked)} /></label>
            <p role="status">{monitor.enabled ? monitor.status.message : '仅计时 · 摄像头已关闭'}</p>
            {monitor.enabled && <div className="camera-actions">
              {monitor.status.code === 'denied' ? <button onClick={() => nativeCommand('settings')}>打开摄像头权限设置</button> : <button disabled={!running || view.phase.kind === 'break'} onClick={() => nativeCommand(['unavailable', 'unknown'].includes(monitor.status.code) ? 'retry' : 'calibrate')}>{['unavailable', 'unknown'].includes(monitor.status.code) ? '重试监测' : '重新适应坐姿'}</button>}
              {monitor.status.code === 'denied' && <button disabled={!running} onClick={() => nativeCommand('retry')}>已授权，重试</button>}
            </div>}
          </> : <><span>摄像头提醒需使用 macOS 应用</span><p>当前浏览器版可使用任务与计时功能。</p></>}
          {monitor.native && <div className="camera-actions"><button onClick={() => nativeCommand('monitorDiagnostics')}>监测诊断</button><button onClick={() => nativeCommand('eyeTest')}>眼动测试（实验）</button></div>}
          {monitor.native && <p>开始后自动适应，无需逐点校准。调整屏幕或坐姿后若提醒不准，可面向工作屏幕，点“重新适应坐姿”。</p>}
          <p>头部与近似视线共同判断，眼部信号不足时只用头部。画面仅在本机处理，不录像、不保存、不上传。暂停、休息或结束后关闭摄像头，不能判断真实注意力或是否在用手机。</p>
        </div>
        <p className="settings-local">任务和计时进度自动保存在此设备。</p>
      </dialog>
    </div>
  </MotionConfig>;
}

applyTheme(loadTheme());
createRoot(document.getElementById('root')!).render(<React.StrictMode><App /></React.StrictMode>);
