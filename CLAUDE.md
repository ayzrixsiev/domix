# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product vision

Domix is a marketplace connecting construction shops with customers, built around a **map-first discovery experience**: users find the nearest construction shops on a map and see each shop's average check (basket size) on the most popular construction products. This is why `shops.location` is a PostGIS `geometry(Point,4326)` column with a GIST index (see Architecture below) rather than plain lat/lng fields — nearby-shop queries are a primary, not secondary, use case.

Future direction: a job-ticket marketplace where clients post construction work requests, and construction workers/teams pick them up. Workers will have their own profile — rating, portfolio (photos of past jobs), client feedback — essentially a service-offering profile layered on top of the same user/role system already in `users.role`.

**Current build focus**: the map feature and all main-page/bottom-nav-bar buttons, *except* the messages section. Do not start on the ticket/worker marketplace features until explicitly asked — build incrementally, one requested feature at a time.

## Working with this repo (read before implementing)

The founder driving this repo is using it to learn Go, Flutter, and software/system design from scratch while building a real product meant for production deployment to paying clients — this is not a throwaway pet project, so hold code to production-grade standards (correctness, security, maintainability) even while explaining things at a beginner-friendly level.

When implementing a feature:
- Explain what you did and why in simple, plain-language terms — assume Go/Flutter/system-design syntax and concepts are still being learned.
- Comment code in **lowercase**, matching the existing style throughout this codebase (see e.g. `internal/auth/session.go`, `auth_controller.dart`) — comments explain non-obvious *why*, not restate the code.
- Build step by step: implement the specific feature asked for, then stop — don't jump ahead to related features or future-roadmap items without being asked.

## Project overview

Domix is a marketplace app connecting shop owners and customers. It has two parts:

- `backend/` — Go HTTP server + Telegram bot that together implement passwordless auth (no traditional password login; users authenticate by linking a Telegram chat).
- `frontend/` — Flutter app (Android/Linux) that talks to the Go backend and drives the Telegram login handshake.

## Commands

### Backend (Go, run from `backend/`)

```
go run ./cmd/api          # start the API server + Telegram bot (loads ../.env)
go build ./...             # compile everything
go vet ./...                # static checks
```

There is no test suite yet.

sqlc generates `db/*.sql.go` from `db/queries/*.sql` against the schema in `db/migrations/`:

```
sqlc generate                         # regenerate db/*.sql.go after editing queries or migrations (see backend/sqlc.yaml)
```

Local Postgres requires the PostGIS extension (used for shop `location` spatial queries/index).

Local dev loop (from `docs/docs.md`):
```
TRUNCATE TABLE users RESTART IDENTITY CASCADE;   -- reset local users table
ngrok http 8080                                   -- expose backend so Telegram webhook can reach it
```
The webhook URL (`WEBHOOK_URL` in `.env`) must point at the ngrok tunnel + `/webhook`.

Required `.env` (in repo root, loaded via `../.env` relative to `backend/cmd/api`): `DB_URL`, `TELEGRAM_BOT_TOKEN`, `WEBHOOK_URL`, `PORT`, `JWT_SECRET`.

### Frontend (Flutter, run from `frontend/`)

```
flutter pub get
flutter run --dart-define-from-file=env.json     # env.json provides API_BASE_URL
flutter analyze                                    # lints (flutter_lints via analysis_options.yaml)
flutter test                                       # test suite (none written yet)
```

`env.json` (gitignored-equivalent, not committed) supplies `API_BASE_URL`, consumed via `String.fromEnvironment` in `AuthService` — defaults to `http://localhost:8080/api/auth` if not passed.

`DevicePreview` currently wraps the whole app in `main.dart` for responsive testing during development (`docs/docs.md` flags this as tech debt to remove before release — don't be surprised it's still there).

## Architecture

### Auth flow: Telegram-linked login (no passwords)

This is the core, non-obvious piece of the system — it spans both backend and frontend and is stateful in RAM, not the DB, until login completes.

1. Flutter collects `name` + `role` (customer/shop_owner) and POSTs to `backend` `/api/auth/init`.
2. Backend (`internal/auth/session.go` `SessionManager`) creates an in-memory session (`sess_<hex>`) with status `pending`, stored in a `sync.Map` (`sessions`). No DB row exists yet.
3. Backend returns a `tg://resolve?...&start=<sessionID>` deep link; Flutter opens Telegram with it.
4. User's `/start <sessionID>` message hits the bot webhook (`cmd/api/main.go`); `SessionManager.LinkChat` maps `chatID -> sessionID` in a second `sync.Map` (`chatToSession`).
5. Bot asks the user to share their phone number via a Telegram contact button.
6. On receiving the contact, the backend looks up `name`/`role` for that chat via `GetPendingSession`, then checks Postgres by phone (`GetUserByPhone`): existing users log in (and get upgraded from `customer` to `shop_owner` if they registered a shop with a previously-customer account); new users are created (`CreateUser`).
7. `SessionManager.CompleteSession` generates a JWT (`internal/auth/jwt.go`, HS256, 1-year expiry) and stores it on the session as `status: success`.
8. Flutter polls `/api/auth/status?session_id=...` every ~2s (`AuthService.checkStatus`, capped at 60 attempts) until it sees `status: success`, then persists the JWT/role/name/phone to `flutter_secure_storage` and updates UI state.
9. A background sweeper goroutine (`startCleanupSweeper`) evicts sessions older than 10 minutes from RAM.

Known gaps called out in `docs/docs.md` (check before assuming these are solved): no refresh/two-token strategy yet (JWT is long-lived single token); users can currently repeat the `/start` + phone-share flow multiple times.

### Backend structure

- `cmd/api/main.go` — single entrypoint; wires env config, Postgres pool (`pgxpool`), Telegram bot, and registers both the Flutter-facing HTTP handlers (`/api/auth/init`, `/api/auth/status`) and the Telegram webhook (`/webhook`) on one `net/http` server. The Telegram update loop and the HTTP listener run concurrently (HTTP in a goroutine, Telegram consumed on the main goroutine).
- `internal/auth/session.go` — in-memory session/handshake state machine described above. This is the piece to read before touching anything auth-related.
- `internal/auth/jwt.go` — JWT generation/validation (HS256, claims: `user_id`, `phone`, `role`).
- `db/` — sqlc-generated data layer. `db/queries/users.sql` is the source of truth for SQL; `db/models.go` and `db/users.sql.go` are generated — edit the `.sql` and rerun `sqlc generate`, don't hand-edit the generated files. `db/migrations/` is the schema source of truth (raw SQL, no migration framework tooling checked in yet).
- Schema: `users` (phone is the unique identity key, `telegram_chat_id` unique+nullable, `role` constrained to `customer`/`shop_owner`/`admin`) → `shops` (one owner, PostGIS `geometry(Point,4326)` location with a GIST index for nearby-shop queries) → `products` (belongs to a shop). All child relations cascade-delete.

### Frontend structure

Feature-first layout under `lib/features/<feature>/{data,presentation}`:
- `data/` — repositories/services doing network or storage I/O (e.g. `auth_service.dart`, `stores_repository.dart`).
- `presentation/controllers/` — `ChangeNotifier` view-models consumed via `provider`. `AuthController` and other controllers are constructed once in `main.dart` and handed to `MultiProvider` as singletons (`AuthController` additionally enforces this with a private static-instance factory constructor, since it's also referenced directly from non-widget code).
- `presentation/screens/` and `presentation/widgets/` — UI.

Some repositories (e.g. `stores_repository.dart`) are still placeholder/stub implementations returning hardcoded data — check before assuming a feature is wired to the real backend.

Localization is custom, not using generated ARB/gen-l10n: `core/localization/app_localizations.dart` + `language_provider.dart` (a `ChangeNotifier` holding the current `AppLanguage`, provided app-wide via `MultiProvider` in `main.dart`). Supported locales are `ru` and `uz`. `LanguageProvider.locale` drives `MaterialApp.locale`.

`AuthService` implements exponential backoff with jitter (`_executeWithRetry`) for all network calls to the Go backend — reuse this pattern rather than adding ad-hoc retry logic if extending other repositories to hit the real API.
