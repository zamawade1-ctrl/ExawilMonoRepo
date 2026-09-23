import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      // Ship a new service worker as soon as one is built, and take over open
      // tabs automatically — admins always run the latest console without a
      // manual "clear cache".
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: [
        'logo.svg',
        'logo-white.svg',
        'apple-touch-icon.png',
        'favicon-512.png',
      ],
      manifest: {
        name: 'e-Xawil Admin',
        short_name: 'Xawil Admin',
        description:
          'MoneyExchange admin console — manage users, plans and activation codes.',
        id: '/',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        display_override: ['standalone', 'minimal-ui'],
        orientation: 'any',
        theme_color: '#2fa84f',
        background_color: '#f4f8f6',
        lang: 'en',
        dir: 'ltr',
        categories: ['business', 'finance', 'productivity'],
        icons: [
          { src: 'pwa-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512.png', sizes: '512x512', type: 'image/png' },
          {
            src: 'pwa-maskable-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'maskable',
          },
          {
            src: 'pwa-maskable-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // Precache the built app shell so the console opens instantly (and
        // offline) once installed. SPA fallback routes every navigation to
        // index.html; the API's /api/* calls are deliberately never cached —
        // they must always hit the network for fresh, auth-scoped data.
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//],
        cleanupOutdatedCaches: true,
        clientsClaim: true,
      },
      devOptions: {
        // Keep the SW off during `vite dev` so HMR isn't shadowed by caching.
        enabled: false,
      },
    }),
  ],
  server: {
    port: 5173,
    // Optional dev proxy: set VITE_PROXY_TARGET (e.g. the live API) and the browser
    // calls same-origin /api/* while Vite forwards them server-side — so the remote
    // backend's CORS allowlist doesn't need to include localhost. Pair it with an
    // empty VITE_API_BASE_URL so the client issues relative /api/* requests.
    proxy: process.env.VITE_PROXY_TARGET
      ? {
          '/api': {
            target: process.env.VITE_PROXY_TARGET,
            changeOrigin: true,
            secure: true,
          },
        }
      : undefined,
  },
});
