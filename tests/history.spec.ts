import { test, expect } from '@playwright/test';
import { initialState, reducer, restoreState } from '../src/store';
import { dayKey, focusSecondsAt } from '../src/session';

test('focus accounting excludes breaks and pauses, survives reset, and archives exactly once', () => {
  const start = new Date(2026, 8, 24, 9).getTime();
  let state = initialState();
  state = reducer(state, { type: 'add', task: { id: 'a', title: '写完方案' }, now: start });
  state = reducer(state, { type: 'duration', minutes: 35 });
  state = reducer(state, { type: 'toggle', now: start, sessionId: 'first' });
  state = reducer(state, { type: 'distraction', id: 'reminder-1', sessionId: 'first', at: start + 20_000 });
  state = reducer(state, { type: 'distraction', id: 'reminder-1', sessionId: 'first', at: start + 21_000 });
  state = reducer(state, { type: 'toggle', now: start + 600_000 });
  expect(state.tasks[0].focusSeconds).toBe(600);
  state = restoreState(JSON.parse(JSON.stringify(state)));
  state = reducer(state, { type: 'toggle', now: start + 720_000 });
  state = reducer(state, { type: 'reset', now: start + 1_200_000 }); // 18 elapsed minutes: 15 focus + 3 break.
  expect(state.tasks[0].focusSeconds).toBe(900);
  state = reducer(state, { type: 'toggle', now: start + 2_000_000, sessionId: 'second' });
  state = reducer(state, { type: 'distraction', id: 'stale', sessionId: 'first', at: start + 2_020_000 });
  state = reducer(state, { type: 'distraction', id: 'reminder-2', sessionId: 'second', at: start + 2_020_000 });
  state = reducer(state, { type: 'complete', id: 'a', now: start + 2_120_000 });
  state = reducer(state, { type: 'complete', id: 'a', now: start + 2_120_001 });
  expect(state.history).toEqual([{ id: 'a', title: '写完方案', completedAt: start + 2_120_000, focusSeconds: 1020, distractions: 2 }]);
  expect(state.tasks).toEqual([]);
  expect(state.session).toBeNull();
});

test('timer completion credits focus once without claiming the task is complete', () => {
  const start = new Date(2026, 8, 23, 23, 0).getTime();
  let state = reducer(initialState(), { type: 'add', task: { id: 'a', title: '读书' }, now: start });
  state = reducer(state, { type: 'duration', minutes: 35 });
  state = reducer(state, { type: 'toggle', now: start, sessionId: 'a-session' });
  state = reducer(state, { type: 'tick', now: start + 3_600_000 * 3 });
  state = reducer(state, { type: 'tick', now: start + 3_600_000 * 4 });
  expect(state.tasks[0].focusSeconds).toBe(1800);
  expect(state.history).toEqual([]);
  expect(state.stats).toEqual({ day: dayKey(start + 2_100_000), count: 1 });
  state = reducer(state, { type: 'complete', id: 'a', now: start + 3_600_000 * 4 });
  expect(state.history[0].focusSeconds).toBe(1800);
  expect(state.history[0].completedAt).toBe(start + 3_600_000 * 4);
});

test('native pause at a delayed timer deadline settles time without starting another session', () => {
  const start = Date.now();
  let state = reducer(initialState(), { type: 'add', task: { id: 'a', title: '最后一段' }, now: start });
  state = reducer(state, { type: 'duration', minutes: 1 });
  state = reducer(state, { type: 'toggle', now: start, sessionId: 'ending' });
  state = reducer(state, { type: 'pause', now: start + 61_000 });
  state = reducer(state, { type: 'pause', now: start + 62_000 });
  expect(state.session?.startedAt).toBeNull();
  expect(state.session?.done).toBe(true);
  expect(state.session?.id).toBe('ending');
  expect(state.stats.count).toBe(1);
  expect(state.tasks[0].focusSeconds).toBe(60);
});

test('anonymous time, queued tasks, break alerts and old saved data do not leak statistics', () => {
  const start = Date.now();
  let state = reducer(initialState(), { type: 'toggle', now: start, sessionId: 'anonymous' });
  state = reducer(state, { type: 'add', task: { id: 'a', title: '后添加的任务' }, now: start + 60_000 });
  state = reducer(state, { type: 'add', task: { id: 'b', title: '队列任务' }, now: start + 65_000 });
  state = reducer(state, { type: 'remove', id: 'b' });
  state = reducer(state, { type: 'complete', id: 'a', now: start + 120_000 });
  expect(state.history[0].focusSeconds).toBe(60);
  expect(state.history).toHaveLength(1);

  const legacy = restoreState({ minutes: 35, tasks: [{ id: 'old', title: '旧任务' }],
    session: { minutes: 35, elapsed: 960, startedAt: null, done: false } });
  expect(legacy.history).toEqual([]);
  expect(legacy.session?.taskId).toBe('old');
  const pausedEvent = reducer(legacy, { type: 'distraction', id: 'paused', sessionId: legacy.session!.id, at: start });
  expect(pausedEvent.tasks[0].distractions).toBe(0);
  const resumed = reducer(legacy, { type: 'toggle', now: start });
  const duringBreak = reducer(resumed, { type: 'distraction', id: 'break', sessionId: resumed.session!.id, at: start + 10_000 });
  expect(duringBreak.tasks[0].distractions).toBe(0);
  expect(reducer(duringBreak, { type: 'complete', id: 'old', now: start + 10_000 }).history[0].focusSeconds).toBe(900);
  expect(focusSecondsAt({ minutes: 60, elapsed: 99999, startedAt: null, done: true }, start)).toBe(3000);
});

test('history records native reminders, completion time and focused time across pause and reload', async ({ page }) => {
  await page.clock.install({ time: new Date(2026, 8, 24, 10, 0) });
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.addInitScript(() => {
    window.__FOCUS_NATIVE__ = true;
    window.webkit = { messageHandlers: { focusOn: { postMessage: () => {} } } };
  });
  await page.goto('/');
  const input = page.getByRole('textbox');
  await input.fill('写完今天的提纲'); await input.press('Enter');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.clock.fastForward(20_000);
  await page.evaluate(() => {
    const session = JSON.parse(localStorage.getItem('focus-on.v1')!).session;
    for (let i = 0; i < 2; i++) window.dispatchEvent(new CustomEvent('focus-native-distraction', {
      detail: { id: 'one-reminder', sessionId: session.id, at: Date.now() },
    }));
    // Generic status changes, including a return that fails, are not new reminders.
    for (const code of ['returning', 'distracted']) window.dispatchEvent(new CustomEvent('focus-native-status', { detail: { code, message: 'test' } }));
  });
  await page.getByRole('button', { name: '暂停任务' }).click();
  await page.clock.fastForward(120_000);
  await page.reload();
  await page.getByRole('button', { name: '继续任务' }).click();
  await page.clock.fastForward(10_000);
  await page.getByRole('button', { name: '完成任务：写完今天的提纲', exact: true }).click();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  await expect(page.getByRole('heading', { name: '历史任务', exact: true })).toBeFocused();
  await expect(page.locator('.timer-section')).toBeHidden();
  await expect(page.locator('.task-section')).toBeHidden();
  await expect(page.locator('.start-button')).toBeHidden();
  await expect(input).toBeHidden();
  await expect(page.locator('.history-title')).toHaveText('写完今天的提纲');
  await expect(page.locator('.history-details')).toHaveText('10:02 完成专注 30 秒分神 1 次');
  expect(await page.locator('.history-title').evaluate(el => getComputedStyle(el).textDecorationLine)).toBe('line-through');
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button', { name: '查看历史任务' })).toBeFocused();
  await page.reload();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  await expect(page.locator('.history-title')).toHaveCount(1);
  await expect(page.locator('.history-details')).toContainText('专注 30 秒');
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await input.fill('下一件事'); await input.press('Enter');
  await expect(page.getByRole('heading', { name: '下一件事', exact: true })).toBeVisible();
  await expect(page.locator('.history-sheet')).toHaveCount(0);
});

test('history groups newest dates first and uses the page without a composer', async ({ page }) => {
  const start = new Date(2026, 8, 24, 16, 30).getTime();
  const history = Array.from({ length: 12 }, (_, index) => ({
    id: `done-${index}`, title: ['整理项目思路与下一步计划', '读完设计里的这一章', '完成首页交互细节'][index % 3],
    completedAt: start - Math.floor(index / 3) * 86400_000 - index * 120_000,
    focusSeconds: (index + 1) * 300, distractions: index % 3,
  }));
  await page.addInitScript(history => localStorage.setItem('focus-on.v1', JSON.stringify({ minutes: 25,
    tasks: [{ id: 'active', title: '继续手上的任务' }], session: null, history: [...history].reverse() })), history);
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  const shellBefore = await page.locator('.app-shell').boundingBox();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  expect(await page.locator('.app-shell').boundingBox()).toEqual(shellBefore);
  await expect(page.locator('.history-day')).toHaveCount(4);
  await expect(page.locator('.history-day').first().locator('h2')).toContainText('2026年9月24日');
  await expect(page.locator('.history-details').first()).toHaveText('16:30 完成专注 5 分钟分神 0 次');
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.screenshot({ path: 'artifacts/history-desktop.png' });
  await page.locator('.history-scroll').evaluate(el => { el.scrollTop = el.scrollHeight; });
  const scroll = await page.locator('.history-scroll').boundingBox();
  const historyPage = await page.locator('.history-page').boundingBox();
  expect(historyPage!.y + historyPage!.height - scroll!.y - scroll!.height).toBeCloseTo(28, 0);
  await expect(page.locator('.history-page input')).toHaveCount(0);
  await expect(page.getByRole('textbox')).toBeHidden();
  await page.setViewportSize({ width: 375, height: 812 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth && document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.locator('.history-scroll').evaluate(el => { el.scrollTop = 0; });
  await page.screenshot({ path: 'artifacts/history-mobile.png' });
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await expect(page.getByRole('heading', { name: '继续手上的任务' })).toBeVisible();
});

test('empty history has a clear return path and does not pause a running timer', async ({ page }) => {
  await page.clock.install();
  await page.goto('/');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  await expect(page.getByText('还没有已完成的任务')).toBeVisible();
  await page.clock.fastForward(60_000);
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await expect(page.locator('.dial-time')).toHaveText('24:00');
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
});

test('home and history travel together as adjoining pages in both directions', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' });
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  const initial = await page.locator('.home-page').boundingBox();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  const frame = await page.evaluate(() => new Promise<{ homeTop: number; homeBottom: number; historyTop: number; visibility: string }>((resolve, reject) => {
    const deadline = performance.now() + 2000;
    const sample = () => {
      const home = document.querySelector('.home-page')!;
      const rect = home.getBoundingClientRect();
      const viewport = document.querySelector('.page-viewport')!.getBoundingClientRect();
      const displacement = viewport.top - rect.top;
      if (displacement > 5 && displacement < rect.height - 5) resolve({ homeTop: rect.top, homeBottom: rect.bottom,
        historyTop: document.querySelector('.history-page')!.getBoundingClientRect().top, visibility: getComputedStyle(home).visibility });
      else if (performance.now() > deadline) reject(new Error('No shared scrolling animation observed'));
      else requestAnimationFrame(sample);
    };
    sample();
  }));
  expect(frame.homeTop).toBeLessThan(initial!.y);
  expect(frame.homeBottom).toBeCloseTo(frame.historyTop, 1);
  expect(frame.visibility).toBe('visible');
  await expect(page.locator('#history-heading')).toBeFocused();
  await expect(page.locator('.home-page')).toBeHidden();
  const viewport = await page.locator('.page-viewport').boundingBox();
  const history = await page.locator('.history-page').boundingBox();
  expect(history!.y).toBeCloseTo(viewport!.y, 1);
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await expect(page.getByRole('button', { name: '查看历史任务' })).toBeFocused();
  expect(await page.locator('.home-page').boundingBox()).toEqual(initial);
  await expect(page.locator('.history-page')).toHaveCount(0);
});

test('deleting history persists, removes empty date groups and preserves current tasks and totals', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await page.evaluate(() => localStorage.setItem('focus-on.v1', JSON.stringify({ minutes: 25,
    tasks: [{ id: 'active', title: '继续写方案', focusSeconds: 70, distractions: 1 }], session: null,
    stats: { day: '2026-9-24', count: 4 }, history: [
      { id: 'new', title: '今天完成的事', completedAt: new Date(2026, 8, 24, 10).getTime(), focusSeconds: 600, distractions: 2 },
      { id: 'old', title: '昨天完成的事', completedAt: new Date(2026, 8, 23, 10).getTime(), focusSeconds: 900, distractions: 0 },
    ] })));
  await page.reload();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  await page.getByRole('button', { name: '删除历史任务：今天完成的事', exact: true }).click();
  await expect(page.locator('.history-day')).toHaveCount(1);
  await expect(page.locator('.history-title')).toHaveText('昨天完成的事');
  await expect(page.getByRole('button', { name: '删除历史任务：昨天完成的事', exact: true })).toBeFocused();
  await page.reload();
  await page.getByRole('button', { name: '查看历史任务' }).click();
  await expect(page.locator('.history-title')).toHaveCount(1);
  await page.getByRole('button', { name: '删除历史任务：昨天完成的事', exact: true }).click();
  await expect(page.getByText('还没有已完成的任务')).toBeVisible();
  await expect(page.locator('#history-heading')).toBeFocused();
  const stored = await page.evaluate(() => JSON.parse(localStorage.getItem('focus-on.v1')!));
  expect(stored.history).toEqual([]);
  expect(stored.stats.count).toBe(4);
  expect(stored.tasks).toEqual([{ id: 'active', title: '继续写方案', focusSeconds: 70, distractions: 1 }]);
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await expect(page.getByRole('heading', { name: '继续写方案' })).toBeVisible();
});
