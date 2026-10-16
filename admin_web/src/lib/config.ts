/**
 * Runtime configuration, resolved from Vite env vars at build time.
 * Set VITE_API_BASE_URL in `.env` (local) or the Vercel project settings (prod).
 */
export const API_BASE_URL: string = (
  import.meta.env.VITE_API_BASE_URL ?? 'https://exawilmonorepo.onrender.com'
).replace(/\/+$/, '');
