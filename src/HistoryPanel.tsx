import { useRef } from 'react';
import { ArrowUp, Check, Trash } from '@phosphor-icons/react';
import { dayKey } from './session';
import type { HistoryTask } from './store';

export function focusDuration(seconds: number) {
  const total = Math.floor(seconds);
  if (total < 60) return `${total} 秒`;
  const minutes = Math.floor(total / 60);
  if (minutes < 60) return `${minutes} 分钟${total % 60 ? ` ${total % 60} 秒` : ''}`;
  return `${Math.floor(minutes / 60)} 小时${minutes % 60 ? ` ${minutes % 60} 分钟` : ''}`;
}

export function HistoryPanel({ tasks, onClose, onDelete }: { tasks: HistoryTask[]; onClose: () => void; onDelete: (id: string) => void }) {
  const heading = useRef<HTMLHeadingElement>(null);
  const list = useRef<HTMLDivElement>(null);
  function remove(id: string) {
    const buttons = Array.from(list.current?.querySelectorAll<HTMLButtonElement>('.history-delete') ?? []);
    const index = buttons.findIndex(button => button.dataset.taskId === id);
    const next = buttons[index + 1] ?? buttons[index - 1];
    onDelete(id);
    requestAnimationFrame(() => (next?.isConnected ? next : heading.current)?.focus({ preventScroll: true }));
  }
  const groups = new Map<string, HistoryTask[]>();
  for (const task of [...tasks].sort((a, b) => b.completedAt - a.completedAt)) {
    const key = dayKey(task.completedAt);
    groups.set(key, [...(groups.get(key) ?? []), task]);
  }
  const dateFormat = new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: 'long', day: 'numeric', weekday: 'long' });
  const timeFormat = new Intl.DateTimeFormat('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });

  return <section id="task-history" className="history-sheet" aria-labelledby="history-heading">
    <div className="history-heading">
      <div><h1 id="history-heading" ref={heading} tabIndex={-1}>历史任务</h1><p>{tasks.length} 件已完成</p></div>
      <button className="icon-button history-return" aria-label="关闭历史任务" title="向上返回主页面" onClick={onClose}><ArrowUp size={22} /></button>
    </div>
    <div ref={list} className="history-scroll" role="region" aria-label="按日期查看已完成任务" tabIndex={0}>
      {tasks.length === 0 ? <div className="history-empty"><Check size={28} weight="light" /><p>还没有已完成的任务</p><span>完成一件事后，它会留在这里。</span></div> :
        [...groups].map(([day, items]) => <section className="history-day" key={day} aria-label={dateFormat.format(items[0].completedAt)}>
          <h2>{dateFormat.format(items[0].completedAt)}</h2>
          <ul>{items.map(task => <li className="history-task" key={task.id}>
            <Check size={18} className="history-check" aria-hidden="true" />
            <div className="history-task-content">
              <s className="history-title">{task.title}</s>
              <div className="history-details">
                <time dateTime={new Date(task.completedAt).toISOString()}>{timeFormat.format(task.completedAt)} 完成</time>
                <span>专注 {focusDuration(task.focusSeconds)}</span>
                <span title="记录摄像头触发的宠物提醒次数">分神 {task.distractions} 次</span>
              </div>
              {task.spans.length > 0 && <ul className="history-spans" aria-label="专注记录">
                {task.spans.map((span, index) => <li key={`${span.session}-${index}`}>
                  <time dateTime={new Date(span.at).toISOString()}>{timeFormat.format(span.at)}</time> 专注 {focusDuration(span.seconds)}
                </li>)}
              </ul>}
            </div>
            <button className="icon-button history-delete" data-task-id={task.id} aria-label={`删除历史任务：${task.title}`} title="删除这条历史记录" onClick={() => remove(task.id)}><Trash size={18} /></button>
          </li>)}</ul>
        </section>)}
    </div>
  </section>;
}
