import { test, expect } from '@playwright/test';

test('native pet receives the theme on startup, switching and reload', async ({ page }) => {
  await page.addInitScript(() => {
    window.__FOCUS_NATIVE__ = true;
    window.webkit = { messageHandlers: { focusOn: { postMessage: (message: unknown) => {
      const command = message as { command: string; theme?: string };
      if (command.command === 'theme') sessionStorage.setItem('pet-theme', command.theme!);
    } } } };
  });
  await page.goto('/');
  const petTheme = () => page.evaluate(() => sessionStorage.getItem('pet-theme'));
  await expect.poll(petTheme).toBe('light');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByText('深色', { exact: true }).click();
  await expect.poll(petTheme).toBe('dark');
  await page.evaluate(() => sessionStorage.removeItem('pet-theme'));
  await page.reload();
  await expect.poll(petTheme).toBe('dark');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await page.getByText('浅色', { exact: true }).click();
  await expect.poll(petTheme).toBe('light');
});

test('light and dark are explicit persistent choices independent of the system', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'dark', reducedMotion: 'reduce' });
  await page.goto('/');
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(247, 247, 243)');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await expect(page.getByRole('radio')).toHaveCount(2);
  await expect(page.getByRole('radio', { name: '浅色', exact: true })).toBeChecked();
  await page.getByText('深色', { exact: true }).click();
  await expect(page.getByRole('radio', { name: '深色', exact: true })).toBeChecked();
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(35, 34, 33)');
  await expect(page.locator('.start-button')).toHaveCSS('background-color', 'rgb(214, 233, 47)');
  await page.screenshot({ path: 'artifacts/theme-dark-choice.png' });
  await page.emulateMedia({ colorScheme: 'light' });
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark');
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(35, 34, 33)');
  await page.getByRole('button', { name: '设置', exact: true }).click();
  await expect(page.getByRole('radio', { name: '深色', exact: true })).toBeChecked();
  // Native radio keyboard behavior remains available without a separate third mode.
  await page.getByRole('radio', { name: '深色', exact: true }).press('ArrowLeft');
  await expect(page.getByRole('radio', { name: '浅色', exact: true })).toBeChecked();
  await expect(page.locator('.app-shell')).toHaveCSS('background-color', 'rgb(247, 247, 243)');
  await page.screenshot({ path: 'artifacts/theme-light-choice.png' });
  await page.emulateMedia({ colorScheme: 'dark' });
  await page.reload();
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'light');
  await expect(page.locator('.start-button')).toHaveCSS('background-color', 'rgb(89, 126, 111)');
});
