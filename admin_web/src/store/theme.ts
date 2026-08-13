import { create } from 'zustand';

type Theme = 'light' | 'dark';
const KEY = 'xawil.admin.theme';

function apply(theme: Theme) {
  document.documentElement.setAttribute('data-theme', theme);
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
