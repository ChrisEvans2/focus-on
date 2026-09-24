import { test, expect } from '@playwright/test';
import { makePlan, sessionView, angleDelta } from '../src/session';

test('start submits a draft, animates the task layout and keeps pause drafts untouched', async ({ page }) => {
  await page.goto('/');
  const before = await page.locator('.timer-section').boundingBox();
  await page.getByRole('textbox').fill('  写完产品说明  ');
  await page.getByRole('button', { name: '开始任务' }).click();
  await expect(page.getByRole('heading', { name: '写完产品说明' })).toBeVisible();
  await expect(page.getByRole('textbox')).toHaveValue('');
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
  await page.waitForTimeout(650);
  const after = await page.locator('.timer-section').boundingBox();
  expect(after!.width).toBeLessThan(before!.width);
  expect(after!.x).toBeGreaterThan(before!.x);
  await page.screenshot({ path: 'artifacts/click-start-task.png' });
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('focus-on.v1')!));
  expect(saved.tasks).toHaveLength(1);
  expect(saved.session.taskId).toBe(saved.tasks[0].id);
  expect(saved.session.startedAt).not.toBeNull();
  await page.getByRole('textbox').fill('下一个任务草稿');
  await page.getByRole('button', { name: '暂停任务' }).click();
  await expect(page.getByRole('textbox')).toHaveValue('下一个任务草稿');
  await expect(page.locator('.queue-item')).toHaveCount(0);
  await page.getByRole('textbox').fill('');
  await page.getByRole('button', { name: '继续任务' }).click();
  await expect(page.locator('.queue-item')).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole('heading', { name: '写完产品说明' })).toBeVisible();
  await expect(page.getByRole('button', { name: '暂停任务' })).toBeVisible();
});

test('mouse-opened settings and history leave no focus ring; keyboard navigation retains it', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  const settings = page.getByRole('button', { name: '设置', exact: true });
  const closeSettings = page.getByRole('button', { name: '关闭设置' });
  const history = page.getByRole('button', { name: '查看历史任务' });
  // Reproduce the keyboard-to-pointer handoff after editing the task input.
  await page.getByRole('textbox').fill('保留输入的草稿');
  await settings.click();
  await expect(closeSettings).toBeFocused();
  await expect(closeSettings).toHaveCSS('outline-style', 'none');
  await page.keyboard.press('Tab');
  await page.keyboard.press('Shift+Tab');
  await expect(closeSettings).toBeFocused();
  await expect(closeSettings).toHaveCSS('outline-style', 'solid');
  await closeSettings.click();
  await expect(settings).toHaveCSS('outline-style', 'none');

  await settings.press('Enter');
  await expect(closeSettings).toBeFocused();
  await expect(closeSettings).toHaveCSS('outline-style', 'solid');
  await page.keyboard.press('Escape');
  await expect(settings).toBeFocused();
  await expect(settings).toHaveCSS('outline-style', 'solid');

  await history.click();
  await expect(page.locator('#history-heading')).toBeFocused();
  await page.getByRole('button', { name: '关闭历史任务' }).click();
  await expect(history).toBeFocused();
  await expect(history).toHaveCSS('outline-style', 'none');
  await history.press('Enter');
  await expect(page.locator('#history-heading')).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(history).toBeFocused();
  await expect(history).toHaveCSS('outline-style', 'solid');
  await page.getByRole('textbox').click();
  await expect(history).toHaveCSS('outline-style', 'none');
});

test('selected total includes breaks; split only at 35; split blocks stay within 25', () => {
  expect(makePlan(34)).toEqual([{ kind: 'focus', seconds: 2040 }]);
  expect(makePlan(35).map(p => p.seconds)).toEqual([900, 300, 900]);
  expect(makePlan(55).map(p => p.seconds)).toEqual([1500, 300, 1500]);
  expect(makePlan(60).map(p => p.seconds)).toEqual([1000, 300, 1000, 300, 1000]);
  expect(makePlan(120).map(p => p.seconds)).toEqual([1200, 300, 1200, 300, 1200, 300, 1200, 300, 1200]);
  for (let minutes = 1; minutes <= 120; minutes++) {
    const plan = makePlan(minutes);
    expect(plan.reduce((sum, p) => sum + p.seconds, 0)).toBe(minutes * 60);
    const focus = plan.filter(p => p.kind === 'focus');
    expect(new Set(focus.map(p => p.seconds)).size).toBe(1);
    if (minutes < 35) expect(plan).toHaveLength(1);
    else expect(focus.every(p => p.seconds <= 1500)).toBe(true);
    expect(plan.filter(p => p.kind === 'break').every(p => p.seconds === 300)).toBe(true);
  }
  expect(angleDelta(2, 358)).toBe(4);
  expect(angleDelta(358, 2)).toBe(-4);
});

test('elapsed wall time catches up through focus, break and completion', () => {
  const s = { minutes: 55, startedAt: 1000, elapsed: 0, done: false };
  expect(sessionView(s, 55, 1501000).phase.kind).toBe('break');
  expect(sessionView(s, 55, 1801000).index).toBe(2);
  expect(sessionView(s, 55, 3301000).finished).toBe(true);
  expect(sessionView({ ...s, startedAt: null, elapsed: 70 }, 55, 9999999).remaining).toBe(1430);
});

test('empty and task layouts, keyboard submission, persistence and completion', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('.dial-time')).toHaveText('25:00');
  await expect(page.locator('.tick')).toHaveCount(60);
  await expect(page.locator('.tick.major')).toHaveCount(12);
  await page.screenshot({ path: 'artifacts/empty-state.png', fullPage: true });
  const before = await page.locator('.timer-section').boundingBox();
  const composerBefore = await page.locator('.composer-section').boundingBox();
  const actionBefore = await page.locator('.start-button').boundingBox();
  await page.getByLabel('当前要专注的任务').fill('完成 Focus On 的首页设计');
  await page.getByLabel('当前要专注的任务').press('Enter');
  await expect(page.getByRole('heading', { name: '完成 Focus On 的首页设计' })).toBeVisible();
  await page.waitForTimeout(650);
  const after = await page.locator('.timer-section').boundingBox();
  expect(after!.width).toBeLessThan(before!.width);
  expect(after!.x).toBeGreaterThan(before!.x);
  expect(await page.locator('.composer-section').boundingBox()).toEqual(composerBefore);
  expect(await page.locator('.start-button').boundingBox()).toEqual(actionBefore);
  const task = await page.locator('.task-section').boundingBox();
  expect(task!.width).toBeGreaterThan(after!.width * 1.5);
  await page.screenshot({ path: 'artifacts/task-state.png', fullPage: true });
  await page.reload();
  await expect(page.getByRole('heading', { name: '完成 Focus On 的首页设计' })).toBeVisible();
  await page.getByRole('button', { name: '完成任务：完成 Focus On 的首页设计', exact: true }).click();
  await expect(page.getByLabel('当前要专注的任务')).toBeVisible();
});

test('two-lap drag, clamp at 120, reverse, keyboard and split preview', async ({ page }) => {
  await page.goto('/');
  const slider = page.getByRole('slider', { name: '专注时长' });
  await slider.focus();
  await slider.press('Home');
  const box = await page.locator('.dial-svg').boundingBox();
  const cx = box!.x + box!.width / 2, cy = box!.y + box!.height / 2, r = box!.width * 151 / 360;
  const move = async (degrees: number) => page.mouse.move(cx + Math.sin(degrees * Math.PI / 180) * r, cy - Math.cos(degrees * Math.PI / 180) * r);
  await move(6); await page.mouse.down();
  for (let d = 12; d <= 780; d += 6) await move(d);
  await expect(slider).toHaveAttribute('aria-valuenow', '120');
  await move(774); await page.mouse.up();
  await expect(slider).toHaveAttribute('aria-valuenow', '119');
  await slider.press('End');
  await expect(page.locator('.second-lap')).toHaveCount(1);
  await expect(page.locator('.dial-time')).toHaveText('120:00');
  await slider.press('Home');
  for (let i = 0; i < 7; i++) await slider.press('PageUp');
  await expect(slider).toHaveAttribute('aria-valuenow', '36');
  await expect(page.locator('.dial-time')).toHaveText('36:00');
  await slider.press('ArrowLeft');
  await expect(page.locator('.dial-time')).toHaveText('35:00');
});

test('timer pauses, reloads and advances into break and second focus', async ({ page }) => {
  await page.clock.install();
  await page.goto('/');
  const slider = page.getByRole('slider');
  await slider.focus();
  for (let i = 0; i < 6; i++) await slider.press('PageUp');
  await page.getByRole('button', { name: '开始任务' }).click();
  await page.clock.fastForward(61_000);
  await expect(page.locator('.dial-time')).toHaveText('23:59');
  await page.getByRole('button', { name: '暂停任务' }).click();
  await page.clock.fastForward(120_000);
  await expect(page.locator('.dial-time')).toHaveText('23:59');
  await page.reload();
  await expect(page.locator('.dial-time')).toHaveText('23:59');
  await page.getByRole('button', { name: '继续任务' }).click();
  await page.clock.fastForward(1439_000);
  await expect(page.locator('.dial')).toHaveClass(/on-break/);
  await expect(page.locator('.dial-time')).toHaveText('05:00');
  await page.clock.fastForward(300_000);
  await expect(page.locator('.dial')).not.toHaveClass(/on-break/);
  await expect(page.locator('.dial-time')).toHaveText('25:00');
  await page.clock.fastForward(1500_000);
  await expect(page.locator('[role="status"]').first()).toHaveText('本次专注已完成');
  await expect(page.locator('.app-footer strong')).toHaveText('1');
  await page.reload();
  await expect(page.locator('.app-footer strong')).toHaveText('1');
});

test('settings, queue, smaller windows and reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await page.getByRole('switch').check();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).not.toBeVisible();
  await page.getByLabel('当前要专注的任务').fill('读完这一章');
  await page.getByRole('button', { name: '添加任务', exact: true }).click();
  await page.getByLabel('添加下一个任务').fill('整理阅读笔记');
  await page.getByRole('button', { name: '添加任务', exact: true }).click();
  await page.getByRole('button', { name: '整理阅读笔记', exact: true }).click();
  await expect(page.getByRole('heading', { name: '整理阅读笔记' })).toBeVisible();
  for (const width of [1440, 1024, 820, 375]) {
    await page.setViewportSize({ width, height: 900 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await expect(page.getByRole('button', { name: '开始任务' })).toBeVisible();
    if (width === 820) await page.screenshot({ path: 'artifacts/compact-state.png', fullPage: true });
  }
});

test('Mac compact viewport fits, long tasks never overlap the composer', async ({ page }) => {
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.screenshot({ path: 'artifacts/mac-empty-state.png', fullPage: true });
  await page.getByLabel('当前要专注的任务').fill('完成 Focus On 的首页设计');
  await page.getByRole('button', { name: '添加任务', exact: true }).click();
  await page.waitForTimeout(600);
  expect(await page.evaluate(() => document.documentElement.scrollHeight <= innerHeight)).toBe(true);
  await page.screenshot({ path: 'artifacts/mac-task-state.png', fullPage: true });
  await page.getByLabel('添加下一个任务').fill('这是一项需要完整显示的较长任务'.repeat(9));
  await page.getByRole('button', { name: '添加任务', exact: true }).click();
  await page.getByRole('button', { name: '完成任务：完成 Focus On 的首页设计', exact: true }).click();
  await page.getByLabel('添加下一个任务').fill('接下来整理笔记');
  await page.getByRole('button', { name: '添加任务', exact: true }).click();
  await page.waitForTimeout(600);
  const section = await page.locator('.task-section').boundingBox();
  const composer = await page.locator('.composer-section').boundingBox();
  expect(composer!.y).toBeGreaterThan(section!.y + section!.height);
});


test('queue is four single-line rows, only overflowing queues show a bottom shadow', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  const input = page.getByPlaceholder('接下来要做什么');
  const originalComposer = await page.locator('.composer-section').boundingBox();
  const originalButton = await page.locator('.start-button').boundingBox();
  const titles = ['当前任务', '这是一项非常长的接下来要做的任务'.repeat(7), '22', '33', '44', '55'];
  for (let i = 0; i < titles.length; i++) {
    await input.fill(titles[i]); await input.press('Enter');
    if (i === 4) await expect(page.locator('.queue')).not.toHaveClass(/has-more/);
  }
  await expect(page.locator('.queue')).toHaveClass(/has-more/);
  const list = await page.locator('.queue-list').boundingBox();
  const row = await page.locator('.queue-item').first().boundingBox();
  expect(list!.height).toBe(row!.height * 4);
  const text = page.locator('.queue-title').first();
  expect(await text.evaluate(el => getComputedStyle(el).whiteSpace)).toBe('nowrap');
  expect(await text.evaluate(el => el.scrollWidth > el.clientWidth)).toBe(true);
  await expect(page.locator('.queue-select').first()).toHaveAttribute('title', titles[1]);
  expect(await page.locator('.composer-section').boundingBox()).toEqual(originalComposer);
  expect(await page.locator('.start-button').boundingBox()).toEqual(originalButton);
  await page.screenshot({ path: 'artifacts/queue-overflow.png', fullPage: true });
  await page.locator('.queue-list').evaluate(el => { el.scrollTop = el.scrollHeight; });
  await expect(page.locator('.queue')).not.toHaveClass(/has-more/);
  await page.locator('.queue-list').evaluate(el => { el.scrollTop = 0; });
  await expect(page.locator('.queue')).toHaveClass(/has-more/);
  await page.getByRole('button', { name: '删除任务：55', exact: true }).click();
  await expect(page.locator('.queue')).not.toHaveClass(/has-more/);
});

test('60 minutes traverses three focus blocks and two breaks in exactly one hour', async ({ page }) => {
  await page.clock.install();
  await page.goto('/');
  const slider = page.getByRole('slider');
  await slider.focus();
  for (let i = 0; i < 7; i++) await slider.press('PageUp');
  await page.getByRole('button', { name: '开始任务' }).click();
  await expect(page.locator('.dial-time')).toHaveText('16:40');
  await expect(page.locator('.dial-outcome')).toHaveText('后休息');
  for (let i = 0; i < 2; i++) {
    await page.clock.fastForward(1000_000);
    await expect(page.locator('.dial')).toHaveClass(/on-break/);
    await expect(page.locator('.dial-time')).toHaveText('05:00');
    await expect(page.locator('.dial-outcome')).toHaveText('后继续');
    await page.clock.fastForward(300_000);
    await expect(page.locator('.dial')).not.toHaveClass(/on-break/);
    await expect(page.locator('.dial-time')).toHaveText('16:40');
    await expect(page.locator('.dial-outcome')).toHaveText(i === 0 ? '后休息' : '后停止');
  }
  await expect(page.locator('[role="status"]').first()).toHaveText('第 3 段专注进行中');
  await page.clock.fastForward(1000_000);
  await expect(page.locator('.app-footer strong')).toHaveText('1');
  await expect(page.locator('.dial-outcome')).toHaveCount(0);
});

test('rest color threshold and smaller running countdown with outcome', async ({ page }) => {
  await page.clock.install();
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  const slider = page.getByRole('slider');
  await slider.focus();
  await slider.press('PageUp'); await slider.press('PageUp'); await slider.press('ArrowLeft');
  await expect(slider).toHaveAttribute('aria-valuenow', '34');
  await expect(page.locator('.handle-outer')).toHaveCSS('fill', 'rgb(89, 126, 111)');
  await slider.press('ArrowRight');
  await expect(page.locator('.handle-outer')).toHaveCSS('fill', 'rgb(168, 98, 52)');
  await expect(slider).toHaveAttribute('aria-valuetext', /含休息/);
  await page.screenshot({ path: 'artifacts/rest-slider.png' });
  const originalSize = await page.locator('.dial-time').evaluate(el => parseFloat(getComputedStyle(el).fontSize));
  await page.getByRole('button', { name: '开始任务' }).click();
  await expect(page.locator('.dial-outcome')).toHaveText('后休息');
  await expect(page.locator('.dial-outcome')).toHaveCSS('color', 'rgb(168, 98, 52)');
  expect(await page.locator('.dial-time').evaluate(el => parseFloat(getComputedStyle(el).fontSize))).toBeLessThan(originalSize);
  await page.screenshot({ path: 'artifacts/rest-countdown.png' });
  await page.getByRole('button', { name: '暂停任务' }).click();
  await expect(page.locator('.dial-outcome')).toHaveText('后休息');
  await page.getByRole('button', { name: '重置计时' }).click();
  await expect(page.locator('.dial-outcome')).toHaveCount(0);
  await slider.focus(); await slider.press('ArrowLeft');
  await expect(page.locator('.handle-outer')).toHaveCSS('fill', 'rgb(89, 126, 111)');
  await page.getByRole('button', { name: '开始任务' }).click();
  await expect(page.locator('.dial-outcome')).toHaveText('后停止');
  await expect(page.locator('.dial-outcome')).toHaveCSS('color', 'rgb(89, 126, 111)');
  await page.screenshot({ path: 'artifacts/stop-countdown.png' });
});
