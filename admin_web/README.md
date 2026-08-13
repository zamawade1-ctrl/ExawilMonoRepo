# admin_web (Xawil Admin console)

The **admin-only** web console for MoneyExchange/Xawil — the browser counterpart to the mobile
app's admin surface (`moneyexchange_app/lib/features/admin`). Signed-in **Admin** accounts manage
customers and their plans: view every account with its live plan snapshot, generate phone-bound
activation codes, expire plans, and reset devices/passwords.

Part of the mono-repo:

```
MoneyExchange.Api/     ASP.NET Core backend (the API this console calls)
moneyexchange_app/     Flutter app (customers + mobile admin surface)
admin_web/             ← this: React admin web console
```

## Stack

- **React 19 + TypeScript**, built with **Vite**
- **zustand** — auth state (`src/store/auth.ts`), the single source of truth for "who's signed in"
- **zod** — validates both the sign-in / generate-code forms and every API response
  (`src/lib/schemas.ts`), so a backend contract drift surfaces at the edge, not deep in a component
- **react-router-dom** — routing with an Admin-only route guard (`src/components/ProtectedRoute.tsx`)
- Plain `fetch` in one client (`src/lib/api.ts`) that attaches the JWT, unwraps the
  `ServiceResponse<T>` envelope, and signs out on 401
- No UI framework — the theme (`src/theme/theme.css`) mirrors the Flutter `AppTheme`: white
  surfaces, a single **Leon-green** (`#2FA84F`) accent

## Security model

- **The token is the boundary.** Every `/api/admin/*` endpoint is `[Authorize(Roles = "Admin")]` on
  the backend, so a non-admin (or tampered) client only ever gets `403`s. The client's Admin checks
  (login gate + route guard) are UX, not the security boundary.
- **Token storage:** the JWT lives in **`sessionStorage`** (`src/lib/session.ts`), scoped to the tab
  and wiped when it closes — no long-lived token on a shared machine, no cross-tab persistence. An
  expired token is dropped on load. Hardening headers (no-referrer, `X-Frame-Options: DENY`,
  `noindex`) are set in `vercel.json` and `index.html`. If the backend later issues an httpOnly
  refresh cookie, `session.ts` is the only file that changes.
- The console never stores or handles customer PINs — those live on-device (Android Keystore) per
  the product design.

## Pages

| Route        | Page                | What it does                                                         |
| ------------ | ------------------- | ------------------------------------------------------------------- |
| `/sign-in`   | `SignInPage`        | Two-panel split: full-green brand panel + white form. Admin-gated.  |
| `/dashboard` | `DashboardPage`     | Totals (active/pro/trial/expired/devices), plan distribution, recent sign-ups; right rail with Quick actions + an "Expiring soon" (≤7d) watchlist |
| `/users`     | `UsersPage`         | Sortable, paginated datatable with search (name/phone/**device label**) + plan filter; right-hand master-detail panel with per-user actions (generate code, expire, reset password/device) |
| `/codes`     | `GenerateCodePage`  | Mint a phone-bound activation code (days/hours/minutes precision)    |

## Running locally

The backend must be running and reachable, with the admin web origin allowed by its CORS policy
(`http://localhost:5173` is allowed by default — see `MoneyExchange.Api/Program.cs`).

```bash
# 1. Start the API (from repo root)
cd MoneyExchange.Api && dotnet run          # serves http://localhost:5219

# 2. Start the admin console
cd admin_web
cp .env.example .env                        # sets VITE_API_BASE_URL=http://localhost:5219
npm install
npm run dev                                 # http://localhost:5173
```

Sign in with the bootstrapped admin account (configured in the API via `Admin:Phone` /
`Admin:Password` user-secrets — see the backend README).

### Scripts

```bash
npm run dev         # Vite dev server
npm run build       # type-check (tsc -b) + production build to dist/
npm run preview     # preview the production build
npm run lint        # eslint
```

## Deploying to Vercel

The repo is a mono-repo, so point Vercel at this subdirectory:

1. **New Project** → import the repo → set **Root Directory** to `admin_web`.
2. Framework preset **Vite** is auto-detected (`vercel.json` also pins it, the SPA rewrite, and the
   security headers).
3. Add an **Environment Variable**: `VITE_API_BASE_URL` = your hosted API URL (e.g.
   `https://api.xawil.app`). The default `.env` value is for local dev only.
4. On the **backend**, add the deployed origin (e.g. `https://admin.xawil.app` or the
   `*.vercel.app` URL) to `Cors:AllowedOrigins` (config or `Cors__AllowedOrigins__0` env var) so the
   browser is allowed to call it.

When you buy the `.app` domain, add it as a Vercel custom domain and add it to the backend's
`Cors:AllowedOrigins` alongside (or instead of) the `*.vercel.app` origin.
