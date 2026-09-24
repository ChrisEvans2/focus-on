import { test, expect } from '@playwright/test';

test('popover controls preserve drafts and reset all phases while retaining task effort', async ({ page }) => {
  const start = new Date('2026-09-24T08:00:00Z');
  await page.clock.install({ time: start });
  await page.clock.pauseAt(start);
  await nativeFixture(page);
  const slider = page.getByRole('slider');
  await slider.focus(); await slider.press('PageUp'); await slider.press('PageUp');
  await page.getByRole('textbox').fill('完整多轮专注');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.getByRole('textbox').fill('未提交的下一项');
  await page.clock.fastForward(1230_000);
  await page.evaluate(() => window.dispatchEvent(new Event('focus-native-pause')));
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('focus-native-control', { detail: { action: 'toggle' } })));
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
  await expect(page.getByRole('textbox')).toHaveValue('未提交的下一项');
  await expect(page.locator('.queue-item')).toHaveCount(0);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('focus-native-control', { detail: { action: 'reset' } })));
  await expect(page.getByRole('button', { name: '开始任务' })).toBeVisible();
  await expect(page.locator('.dial-time')).toHaveText('35:00');
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('focus-on.v1')!));
  expect(saved.session).toBeNull();
  expect(saved.tasks).toHaveLength(1);
  expect(saved.tasks[0].focusSeconds).toBe(930);
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('focus-native-control', { detail: { action: 'toggle' } })));
  await expect(page.locator('.dial-time')).toHaveText('15:00');
  expect((await lastSchedule(page))?.elapsed).toBe(0);
});

test('menu-bar minimize sends the current task and leaves the countdown running', async ({ page }) => {
  await nativeFixture(page);
  await page.getByRole('textbox').fill('菜单栏中的任务');
  await page.getByRole('button', { name: '开始任务' }).click();
  const minimize = page.getByRole('button', { name: '最小化到菜单栏' });
  await expect(minimize).toBeVisible();
  const minimizeBox = await minimize.boundingBox();
  const settingsBox = await page.getByRole('button', { name: '设置', exact: true }).boundingBox();
  expect(minimizeBox!.x + minimizeBox!.width).toBeLessThan(settingsBox!.x);
  expect(minimizeBox!.y).toBe(settingsBox!.y);
  await page.getByRole('button', { name: '最小化到菜单栏' }).click();
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
  const messages = await page.evaluate(() => (window as unknown as { nativeMessages: Array<{ command: string; taskTitle?: string }> }).nativeMessages);
  expect(messages.at(-1)?.command).toBe('minimizeToMenuBar');
  expect(messages.filter(m => m.command === 'sync').at(-1)?.taskTitle).toBe('菜单栏中的任务');
  expect((await lastSchedule(page))?.running).toBe(true);
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await expect(page.getByRole('dialog').getByRole('button', { name: '最小化到菜单栏' })).toHaveCount(0);
});

test('browser settings do not offer native menu-bar minimize', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await expect(page.getByRole('button', { name: '最小化到菜单栏' })).toHaveCount(0);
});

async function nativeFixture(page: import('@playwright/test').Page) {
  await page.addInitScript(() => {
    const target = window as unknown as { __FOCUS_NATIVE__: boolean; webkit: unknown; nativeMessages: Array<{ command: string; schedule?: unknown }> };
    target.__FOCUS_NATIVE__ = true;
    target.nativeMessages = [];
    target.webkit = { messageHandlers: { focusOn: { postMessage: (message: { command: string; schedule?: unknown }) => target.nativeMessages.push(message) } } };
  });
  await page.goto('/');
}
async function lastSchedule(page: import('@playwright/test').Page) {
  return page.evaluate(() => {
    const messages = (window as unknown as { nativeMessages: Array<{ command: string; schedule: { running: boolean; monitoring: boolean; elapsed: number; startedAt: number | null; phases: Array<{ kind: string; seconds: number }> } }> }).nativeMessages;
    return messages.filter(message => message.command === 'sync').at(-1)?.schedule;
  });
}

test('native bridge carries the full plan and pause/reset/completion lifecycle', async ({ page }) => {
  const start = new Date('2026-09-24T08:00:00Z');
  await page.clock.install({ time: start });
  await page.clock.pauseAt(start);
  await nativeFixture(page);
  expect((await lastSchedule(page))?.running).toBe(false);
  const slider = page.getByRole('slider');
  await slider.focus(); await slider.press('PageUp'); await slider.press('PageUp');
  await page.getByRole('button', { name: '开始任务' }).click();
  expect((await lastSchedule(page))?.phases).toEqual([{ kind: 'focus', seconds: 900 }, { kind: 'break', seconds: 300 }, { kind: 'focus', seconds: 900 }]);
  expect((await lastSchedule(page))?.monitoring).toBe(true);
  await page.clock.fastForward(30_000);
  await page.evaluate(() => window.dispatchEvent(new Event('focus-native-pause')));
  await expect(page.getByRole('button', { name: '继续任务' })).toBeVisible();
  expect((await lastSchedule(page))?.running).toBe(false);
  expect((await lastSchedule(page))?.elapsed).toBeCloseTo(30, 1);
  await page.getByRole('button', { name: '继续任务' }).click();
  expect((await lastSchedule(page))?.running).toBe(true);
  await page.clock.fastForward(2070_000);
  await expect(page.locator('[role="status"]').first()).toHaveText('本次专注已完成');
  expect((await lastSchedule(page))?.running).toBe(false);
  await page.getByRole('button', { name: '重置计时' }).click();
  expect((await lastSchedule(page))?.elapsed).toBe(0);
});

test('camera preference, unavailable status and recovery actions are explicit', async ({ page }) => {
  await nativeFixture(page);
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.evaluate(() => window.dispatchEvent(new CustomEvent('focus-native-status', { detail: { code: 'denied', message: '未获摄像头权限，仍可继续计时' } })));
  await expect(page.locator('.monitor-status')).toHaveText('监测未开启');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByRole('button', { name: '监测诊断', exact: true }).click();
  await page.getByRole('button', { name: '眼动测试（实验）' }).click();
  await page.getByRole('button', { name: '打开摄像头权限设置' }).click();
  await page.getByRole('button', { name: '已授权，重试' }).click();
  const commands = await page.evaluate(() => (window as unknown as { nativeMessages: Array<{ command: string }> }).nativeMessages.map(m => m.command));
  expect(commands).toContain('monitorDiagnostics'); expect(commands).toContain('eyeTest'); expect(commands).toContain('settings'); expect(commands).toContain('retry');
  await page.getByRole('switch', { name: '摄像头专注提醒' }).uncheck();
  expect((await lastSchedule(page))?.monitoring).toBe(false);
  await expect(page.locator('.monitor-status')).toHaveText('仅计时');
  await page.reload();
  expect((await lastSchedule(page))?.monitoring).toBe(false);
});

test('completing the active task ends its monitoring schedule', async ({ page }) => {
  await nativeFixture(page);
  await page.getByLabel('当前要专注的任务').fill('完成当前任务');
  await page.getByLabel('当前要专注的任务').press('Enter');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.getByRole('button', { name: '完成任务：完成当前任务', exact: true }).click();
  expect((await lastSchedule(page))?.running).toBe(false);
  await expect(page.getByRole('button', { name: '开始任务' })).toBeVisible();
});
