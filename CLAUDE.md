# MoneyExchange (mono-repo)

Money-exchange / auto-forwarding product. Customers sign up / sign in with a username (or email)
and password, set a payout preference (mobile number or bank account), and money received on
their Zaad/eDahab account is auto-forwarded to their chosen destination (on-device on Android; a
backend polling job is the server-side fallback).

> **Auth note:** this used to be Google Sign-In; it's now **username/email + password**. The
> `User` is the login identity (it holds the credentials + JWT); each `User` owns one linked
> `Customer` forwarding profile, created together at sign-up (see "Identity model" below).
> Telesom OTP is scaffolded as a future first-login second factor but is **not required** today.
> The Google code path (`IGoogleTokenVerifier`, `POST /api/auth/google`) is left in place but
> **dormant** — the app no longer uses it.

Two projects live side by side in this repo:

```
MoneyExchange.Api/     ASP.NET Core backend (this is the primary README below)
moneyexchange_app/     Flutter frontend (Android + iOS)
```

---

# MoneyExchange.Api (backend)

ASP.NET Core (.NET 10) Web API.

## Stack

- ASP.NET Core 10, EF Core 10
- **Postgres via Supabase**, accessed through `Npgsql.EntityFrameworkCore.PostgreSQL` — this is
  a normal EF Core + Postgres setup, not the Supabase JS/Auth SDK. There is no Node/JS in the
  backend; don't add `@supabase/*` npm packages here.
- JWT bearer auth (`Microsoft.AspNetCore.Authentication.JwtBearer`)
- **Username/email + password auth**: `POST /api/auth/register` and `POST /api/auth/login`
  (in `UserAuthRepository`), passwords hashed with ASP.NET Core's `PasswordHasher<User>`
  (PBKDF2). The JWT's subject is the `User` id with a `subjectType=user` claim. Register creates
  the `User` **and** its linked `Customer` in one transaction. This replaced Google Sign-In — no
  hosted auth provider (e.g. Supabase Auth) is involved.
- Legacy/dormant: Google Sign-In verified against Google's public keys (`Google.Apis.Auth`),
  reachable at `POST /api/auth/google`. Kept compiling but unused by the app.

## Architecture pattern

Repository pattern + `ServiceResponse<T>` wrapper: controllers are thin, repositories hold all
business + persistence logic and return a `ServiceResponse<T>` with a logical `ServiceStatus`.
`ApiControllerBase.HandleResponse<T>` maps that status to the HTTP status code. Controllers
never talk to `AppDbContext` directly.

```
Controllers/          thin, one action per repository method
Repositories/
  Interfaces/          contract, returns ServiceResponse<T>
  Implementations/      all validation + EF Core queries live here
Models/
  Entities/             EF Core entities
  DTOs/                 request payloads
  Responses/            ServiceResponse<T> / ServiceStatus
Services/
  Otp/                  Telesom OTP (stub)
  MoneyProviders/        Zaad / eDahab polling clients (stub)
  Forwarding/            USSD/bank forwarding + the 1-minute background job
  Auth/                  JWT issuance + Google ID token verification
Migrations/            EF Core migrations (Postgres)
```

## Identity model: User (identity) + Customer (profile), 1-to-1

Two entities, linked 1-to-1 via `Customer.UserId`. **Sign-up creates both in one transaction**
(`UserAuthRepository.RegisterAsync`), so the tables are always populated and related together:

- **`User`** — the login identity + credentials: `FullName`, `Email`, `Username`, `PasswordHash`
  (PBKDF2, `[JsonIgnore]`d so it never leaves the API), `LastLoginAtUtc`. `Email`/`Username` are
  unique; `GoogleSubjectId` is nullable (only the dormant Google path sets it). **Owns the JWT** —
  subject = `User.Id`, `subjectType=user`.
- **`Customer`** — the money-forwarding profile owned by that user: `PhoneNumber` (future OTP +
  server-side receipt matching), `ForwardingMethod` + `ForwardingPhoneNumber` (mobile) or
  `BankAccountNumber` (repurposed to hold the bank PIN), `IsVerified`.

The FK cascades: deleting the `User` deletes its `Customer`. `ApiControllerBase`'s
`TryGetAuthenticatedUserId` reads the JWT subject; `/api/customers/me` (GET/PUT) and
`DELETE /api/auth/me` are scoped to the signed-in user and operate on its linked customer.
(Mobile forwarding PINs are **not** stored server-side — they live in the Android Keystore
on-device; only the bank PIN persists, in `Customer.BankAccountNumber`.)

## Domain flow

1. `POST /api/auth/register` — the Flutter app's sign-up form: full name, email, username,
   password. Creates the `User` + its linked `Customer` and returns a signed-in JWT (no OTP for
   now). `POST /api/auth/login` — the sign-in form: username-or-email + password → JWT.
2. `PUT /api/customers/me` — the signed-in customer sets their forwarding choice
   (`ForwardingMethod.MobileNumber` + `ForwardingPhoneNumber`, or `ForwardingMethod.BankAccount`
   + `BankAccountNumber` PIN). `GET /api/customers/me` reads it back. (The old anonymous
   `POST /api/customers` register endpoint still exists but the app doesn't use it.)
3. `POST /api/auth/otp/request` / `POST /api/auth/otp/verify` — Telesom OTP flow, scaffolded as a
   future first-login second factor. **Currently not required** — see "OTP is bypassed" below.
4. Every 60 seconds, `MoneyForwardingBackgroundService` polls `IMoneyProviderClient` for Zaad and
   eDahab, matches each USSD receipt to a `Customer` by phone number, and forwards it via
   `IMoneyForwardingService` to that customer's mobile number or bank account. Every attempt is
   recorded in `IncomingMoneyTransaction` (deduped by provider transaction id), visible via
   `GET /api/incomingmoneytransactions`.

## OTP is bypassed for now

The Telesom OTP API isn't available yet, so `CustomerRepository.RegisterAsync` sets
`Customer.IsVerified = true` immediately at registration instead of requiring the OTP round
trip. The auth scaffold (`AuthController`'s `otp/*` routes, `ITelesomOtpService`,
`OtpVerification` entity, JWT issuance) is fully built and still works if called — it's just not
required for a customer to receive auto-forwarded money. `AuthRepository.RegisterAsync` sets
`IsVerified = true` on sign-up for the same reason. When the real Telesom API is available:
implement `ITelesomOtpService` for real, wire OTP as a first-login second factor, and flip those
lines back to `IsVerified = false`.

## Stub integrations — swap points

Three external integrations are interfaces with logging stubs, each ready to be replaced with a
real implementation without touching any other code:

| Interface | Stub impl | Real thing |
|---|---|---|
| `ITelesomOtpService` | `TelesomOtpService` | Telesom SMS/OTP API |
| `IMoneyProviderClient` | `ZaadMoneyProviderClient`, `EDahabMoneyProviderClient` | Zaad / eDahab receipt-polling APIs |
| `IMoneyForwardingService` | `UssdMoneyForwardingService` | USSD gateway / bank transfer rail |

All three are registered in `Program.cs`. Swap the implementation registration when real
credentials/API docs are available — nothing else needs to change.

`IGoogleTokenVerifier` (`GoogleTokenVerifier`) is **not** a stub — it's a real implementation
that validates against Google's live public keys. It only needs configuration (see below), not a
future rewrite.

## Database: Supabase Postgres

Uses **EF Core Migrations**, not `EnsureCreated()`. This matters: Supabase's built-in schemas
(`auth`, `storage`, ...) already contain tables, which makes `EnsureCreated()`'s "does this
database already have a schema" check report `true` and silently skip creating the app's own
tables. `Program.cs` calls `db.Database.Migrate()` on startup instead.

**Connection string**: use the **Session pooler** string from the Supabase dashboard
(Project → Connect → ORMs, or Settings → Database → Connection pooling), not the direct
`db.<project-ref>.supabase.co` host — that host is IPv6-only and unreachable from most
networks/laptops. The pooler host looks like `aws-<n>-<region>.pooler.supabase.com`; get the
region from *this* project specifically (copying a pooler host from a different Supabase
project fails with "tenant/user not found").

Format:
```
Host=aws-<n>-<region>.pooler.supabase.com;Port=5432;Database=postgres;Username=postgres.<project-ref>;Password=<db-password>;SSL Mode=Require;Trust Server Certificate=true
```

### Local setup

Never put real credentials in `appsettings.json` — it's committed to git. Use user-secrets
instead (already wired via `UserSecretsId` in the `.csproj`):

```bash
cd MoneyExchange.Api
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Host=...;Port=5432;Database=postgres;Username=postgres.<project-ref>;Password=...;SSL Mode=Require;Trust Server Certificate=true"
dotnet user-secrets set "Jwt:Key" "$(openssl rand -base64 48)"
```

For actual hosting (not local dev), use environment variables with double-underscore nesting
instead: `ConnectionStrings__DefaultConnection`, `Jwt__Key`.

### Migrations workflow

```bash
cd MoneyExchange.Api
dotnet ef migrations add <Name>     # after changing an entity / OnModelCreating
dotnet ef database update           # apply pending migrations to the configured DefaultConnection
```

`dotnet run` also applies pending migrations automatically on startup.

## Google Sign-In setup (Google Cloud Console) — LEGACY / DORMANT

> The app authenticates with username/password now; this section applies only if you re-enable
> the dormant Google path. Not needed for normal development.

OAuth client IDs are not secret (unlike client secrets) - the real values can live directly in
`appsettings.json` under `GoogleAuth:Audiences`, no user-secrets needed for this one.

1. In [Google Cloud Console](https://console.cloud.google.com/), create an OAuth 2.0 **Web
   application** client (Credentials → Create Credentials → OAuth client ID → Web application).
   This is the one that matters for the backend, even though there's no web frontend - it's the
   `serverClientId` the Flutter app passes to `google_sign_in`, which makes the returned ID
   token's `aud` claim match what the backend validates against.
2. Also create Android and iOS OAuth client IDs (needed for the native sign-in UI/consent
   screen, package name + SHA-1 fingerprint for Android, bundle ID for iOS) - see
   `moneyexchange_app`'s setup section below.
3. Put **both** the Web and iOS client IDs in `MoneyExchange.Api/appsettings.json`'s
   `GoogleAuth:Audiences` array - confirmed empirically, not just in theory:
   ```json
   "GoogleAuth": { "Audiences": [
     "<web-client-id>.apps.googleusercontent.com",
     "<ios-client-id>.apps.googleusercontent.com"
   ] }
   ```
   **Why both**: on Android, `google_sign_in`'s Credential Manager flow issues an ID token
   audienced to the `serverClientId` (the Web client), as expected. On iOS, even with
   `serverClientId` also set, the SDK issues the ID token audienced to the **iOS** client
   (`GIDClientID`) instead - passing only the Web client ID here makes the backend reject every
   iOS sign-in with `JWT contains untrusted 'aud' claim`. The Android client ID is not needed
   here since Android never emits a token audienced to it in this flow.
4. Restart the API. `POST /api/auth/google` will now accept ID tokens from both platforms.

## Running locally

```bash
cd MoneyExchange.Api
dotnet run
```

Requires `ConnectionStrings:DefaultConnection` and `Jwt:Key` to be set via user-secrets (see
above), and `GoogleAuth:Audiences` to be set in `appsettings.json` — the app will fail to start
or reject all Google sign-ins without these, by design (no secrets baked into the repo, and no
silent fallback for a missing OAuth audience).

---

# moneyexchange_app (frontend)

Flutter app, Android + iOS. First screen is the **sign-in / sign-up form** (`sign_in_screen.dart`,
a `SegmentedButton` toggling the two modes); a signed-in user lands on the home shell. Sign-up
collects full name / email / username / password; sign-in takes username-or-email + password.

## Stack

- `flutter_riverpod` — state management (`AsyncNotifier<AppUser?>` in `auth_providers.dart` is
  the single source of truth for "who's signed in"; `register`/`login` on `AuthController`)
- `go_router` — navigation, with a `redirect` that guards `/home` behind sign-in and bounces a
  signed-in user away from `/sign-in`
- Auth is username/password against the backend (`auth_api.dart` → `/api/auth/register|login`).
  The `google_sign_in` package is still in `pubspec.yaml` but no longer used in `lib/`.
- `dio` — HTTP client, JWT attached automatically via an interceptor in `ApiClient`
- `flutter_secure_storage` — JWT + cached profile persisted in the platform keychain/keystore,
  never SharedPreferences

## Structure

```
lib/
  core/
    config/app_config.dart      API base URL + Google server client ID, via --dart-define
    theme/app_theme.dart        single source of visual identity
    network/api_client.dart     Dio + auth interceptor
    storage/session_storage.dart JWT + cached profile in secure storage
    routing/app_router.dart     go_router + auth guard
  features/
    auth/
      data/                    auth_api.dart, auth_repository.dart (register/login + session)
      domain/app_user.dart
      presentation/            auth_providers.dart, sign_in_screen.dart (the first page)
    home/presentation/home_shell.dart    signed-in frame (home / transactions / accessibility)
```

## Google Sign-In setup (verified working on both platforms) — LEGACY / DORMANT

> Superseded by username/password auth. Kept for reference in case the Google path is revived.

Google Sign-In cannot complete without real OAuth client IDs from *your* Google Cloud project -
this can't be scaffolded generically. What's below is confirmed working end-to-end (real Google
account -> backend JWT -> row in the Supabase `Users` table) on both an Android emulator and the
iOS Simulator, not just theory.

1. Complete steps 1-3 in the backend's "Google Sign-In setup" section above: a Web client (for
   `serverClientId`/backend audience) and an iOS client. **An Android-specific OAuth client
   turned out not to be necessary** - `google_sign_in` v7's Credential Manager-based flow on
   Android works with just the Web client ID passed as `serverClientId`; no
   `google-services.json` and no SHA-1 registration required for this flow. (You'd still want a
   properly configured Android client for a production release, but it wasn't needed to get
   sign-in working.)
2. **iOS** (already wired into `moneyexchange_app/ios/Runner/Info.plist` in this repo - update
   the values if you regenerate your own OAuth clients): add `GIDClientID` set to the iOS client
   ID, and a `CFBundleURLTypes` entry whose `CFBundleURLSchemes` is the reversed client ID
   (`com.googleusercontent.apps.<client-id-prefix>`).
3. Make sure the backend's `GoogleAuth:Audiences` includes **both** the Web and iOS client IDs
   (see the "Why both" note above) - a missing iOS audience surfaces as the app appearing to
   "sign in" (Google's account picker completes fine) but then bouncing straight back to the
   sign-in screen, because the backend's `/api/auth/google` call fails silently in the UI (just
   shows the generic error banner) while logging `JWT contains untrusted 'aud' claim` on the
   backend - check that log first if this happens.
4. Run with the Web client ID passed through:
   ```bash
   flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com \
               --dart-define=API_BASE_URL=http://10.0.2.2:5219   # Android emulator -> host localhost
   ```
   Use `http://localhost:5219` instead for the iOS Simulator, or your machine's LAN IP for a
   physical device.

## Running locally

Only `API_BASE_URL` is needed now (Google client ID is no longer used):

```bash
cd moneyexchange_app
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5219        # Android emulator

# USB-connected physical device (most robust — survives Wi-Fi/IP changes): tunnel the device's
# localhost to the host with adb reverse, then point the app at localhost.
adb reverse tcp:5219 tcp:5219
flutter run --dart-define=API_BASE_URL=http://localhost:5219
#   ...or over Wi-Fi (same network): use the host's LAN IP (`ipconfig getifaddr en0`) and run the
#   API on 0.0.0.0 (dotnet run --urls http://0.0.0.0:5219). Cleartext HTTP is allowed in
#   AndroidManifest.xml (usesCleartextTraffic=true).

# Build + install a release APK on the device (same adb reverse tunnel applies at runtime):
flutter build apk --release --dart-define=API_BASE_URL=http://localhost:5219
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`flutter analyze` and `flutter test` both pass with zero configuration (the widget test mocks
the secure-storage platform channel, so it doesn't need real backend config).
