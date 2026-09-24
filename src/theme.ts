import { nativeCommand } from './native';

export type Theme = 'light' | 'dark';
const THEME_STORAGE = 'focus-on.theme';

export function loadTheme(): Theme {
  try { return localStorage.getItem(THEME_STORAGE) === 'dark' ? 'dark' : 'light'; }
  catch { return 'light'; }
}

export function applyTheme(theme: Theme) {
  document.documentElement.dataset.theme = theme;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#232221' : '#f7f7f3');
  nativeCommand('theme', { theme });
}

export function saveTheme(theme: Theme) {
  applyTheme(theme);
  try { localStorage.setItem(THEME_STORAGE, theme); } catch { /* Keep the choice for this visit. */ }
}
