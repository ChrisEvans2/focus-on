import { test, expect } from '@playwright/test';
import { initialState, reducer } from '../src/store';

for (const theme of ['light', 'dark']) {
  test(`${theme}: rest has one action and shares the long-session slider color`, async ({ page }) => {
    const start = new Date('2026-09-26T08:00:00Z');
    await page.clock.pauseAt(start);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.addInitScript(theme => localStorage.setItem('focus-on.theme', theme), theme);
    await page.goto('/');
    const slider = page.getByRole('slider');
    await slider.press('PageUp'); await slider.press('PageUp');
    const restColor = await page.locator('.handle-outer').evaluate(el => getComputedStyle(el).fill);
    expect(restColor).toBe(theme === 'dark' ? 'rgb(127, 150, 227)' : 'rgb(168, 98, 52)');
    await page.getByRole('textbox').fill('休息后继续写作');
    await page.getByRole('button', { name: '开始任务' }).click();
    await page.mouse.move(0, 0);
    await page.clock.runFor(400);
    await page.clock.fastForward(930_000);
    await expect(page.locator('.dial-time')).toHaveText('04:30');
    await expect(page.locator('.session-controls button')).toHaveCount(1);
    await expect(page.getByRole('button', { name: '跳过休息' })).toHaveCSS('background-color', restColor);
    await expect(page.locator('.dial-progress').last()).toHaveCSS('stroke', restColor);
    await page.screenshot({ path: `artifacts/break-${theme}.png` });
    await page.getByRole('textbox').fill('保留的草稿');
    await page.getByRole('button', { name: '跳过休息' }).click();
    await expect(page.locator('.dial-time')).toHaveText('15:00');
    await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
    await expect(page.getByRole('textbox')).toHaveValue('保留的草稿');
    await page.reload();
    await expect(page.locator('.dial-time')).toHaveText('15:00');
    await page.clock.fastForward(900_000);
    await expect(page.locator('.app-footer strong')).toHaveText('1');
    const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('focus-on.v1')!));
    expect(saved.tasks[0].focusSeconds).toBe(1800);
    expect(saved.stats.count).toBe(1);
    expect(saved.session.done).toBe(true);
  });
}

test('native skip advances the persisted plan and ignores a late duplicate', async ({ page }) => {
  const start = new Date('2026-09-26T08:00:00Z');
  await page.clock.install({ time: start });
  await page.clock.pauseAt(start);
  await page.addInitScript(() => {
    window.__FOCUS_NATIVE__ = true;
    window.webkit = { messageHandlers: { focusOn: { postMessage: (message: unknown) => {
      const payload = message as { command: string; schedule?: unknown };
      if (payload.command === 'sync') sessionStorage.setItem('schedule', JSON.stringify(payload.schedule));
    } } } };
  });
  await page.goto('/');
  await page.getByRole('slider').press('PageUp'); await page.getByRole('slider').press('PageUp');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.clock.fastForward(900_000);
  await page.evaluate(() => window.dispatchEvent(new Event('focus-native-pause')));
  await expect(page.getByRole('button', { name: '跳过休息' })).toBeVisible();
  for (let i = 0; i < 2; i++) {
    await page.evaluate(() => window.dispatchEvent(new CustomEvent('focus-native-control', { detail: { action: 'skip-break' } })));
  }
  await expect(page.locator('.dial-time')).toHaveText('15:00');
  const schedule = await page.evaluate(() => JSON.parse(sessionStorage.getItem('schedule')!));
  expect(schedule.running).toBe(true);
  expect(schedule.elapsed).toBe(1200);
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
});

test('skipping multiple breaks preserves focus totals and cannot skip an ended session', () => {
  let state = { ...initialState(), minutes: 60 };
  state = reducer(state, { type: 'add', task: { id: 'task', title: '写作' }, now: 0 });
  state = reducer(state, { type: 'toggle', now: 0 });
  state = reducer(state, { type: 'skip-break', now: 1000_000 });
  expect(state.session?.elapsed).toBe(1300);
  state = reducer(state, { type: 'skip-break', now: 2000_000 });
  expect(state.session?.elapsed).toBe(2600);
  state = reducer(state, { type: 'tick', now: 3000_000 });
  expect(state.tasks[0].focusSeconds).toBe(3000);
  expect(state.stats.count).toBe(1);
  expect(reducer(state, { type: 'skip-break', now: 3001_000 })).toBe(state);
});
