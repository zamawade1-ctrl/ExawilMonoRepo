import { create } from 'zustand';

type Theme = 'light' | 'dark';
const KEY = 'xawil.admin.theme';

// Match the app surface behind the OS/browser chrome so an installed PWA's
// status bar blends into the page instead of flashing a mismatched colour.
const THEME_COLOR: Record<Theme, string> = { light: '#ffffff', dark: '#171b1f' };

function apply(theme: Theme) {
  document.documentElement.setAttribute('data-theme', theme);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute('content', THEME_COLOR[theme]);
}

interface ThemeState {
  theme: Theme;
  toggle: () => void;
  init: () => void;
}

/** Light/dark theme, persisted in localStorage and mirrored to the <html> data-theme attribute. */
export const useThemeStore = create<ThemeState>((set, get) => ({
  theme: 'light',
  init: () => {
    const stored = localStorage.getItem(KEY) as Theme | null;
    const theme: Theme =
      stored ??
      (window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    apply(theme);
    set({ theme });
  },
  toggle: () => {
    const theme: Theme = get().theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem(KEY, theme);
    apply(theme);
    set({ theme });
  },
}));
