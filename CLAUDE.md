# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Product vision

Domix is a marketplace connecting construction shops with customers, built around a **map-first discovery experience**: users find the nearest construction shops on a map and see each shop's average check (basket size) on the most popular construction products. This is why `shops.location` is a PostGIS `geometry(Point,4326)` column with a GIST index (see Architecture below) rather than plain lat/lng fields — nearby-shop queries are a primary, not secondary, use case.

Future direction: a job-ticket marketplace where clients post construction work requests, and construction workers/teams pick them up. Workers will have their own profile — rating, portfolio (photos of past jobs), client feedback — essentially a service-offering profile layered on top of the same user/role system already in `users.role`.

## Working with this repo (read before implementing)

The founder driving this repo is using it to learn Go, Flutter, and software/system design from scratch while building a real product meant for production deployment to paying clients — this is not a throwaway pet project, so hold code to production-grade standards (correctness, security, maintainability) even while explaining things at a beginner-friendly level.

### How to teach me as you build

Every time you implement or touch something non-trivial, structure the explanation around three things:

- **Syntax** — when you use a Go or Dart language feature I might not have seen before (goroutines, channels, `sync.Map`, Dart's `late`, `Future`/`async`/`await`, mixins, extension methods, etc.), explain in details what it does and why it's the right tool here. Don't assume I recognize it just because it's appeared in the codebase before — flag it again if it's genuinely a new concept for me, but don't re-explain things I've clearly already learned.
- **Data flow** — when a feature spans layers (e.g. a button tap → controller → repository → HTTP call → Go handler → sqlc query → Postgres → response → JSON decode → `ChangeNotifier` → widget rebuild), trace that path explicitly rather than only describing the layer you just edited. I learn the system better from seeing how data actually moves end-to-end than from looking at one file in isolation.
- **Design rationale** — state the "why" behind a decision, including the alternative you didn't pick and why (e.g. why polling instead of WebSockets for auth status, why PostGIS over plain lat/lng columns). If a decision was purely pragmatic (budget, timeline, early-stage startup constraints) rather than a deliberate architectural choice, say so plainly — don't dress up a shortcut as a principled design decision.

Keep it plain-language, but don't oversimplify to the point of hiding the real mechanism — I'd rather understand the actual thing than a dumbed-down metaphor for it.

**Patterns confirmed to work well in practice (don't drift from these):**
- When I restate something back in my own words, don't just re-explain from scratch — check my restatement point by point: quote what I said, say whether it's right or wrong, and explain why. This is how I actually confirm I understood something; a fresh independent explanation that skips validating my attempt is much less useful to me.
- Always show the real code inline (paste the actual snippet), not just a description of it — and always pair it with `file_path:line_number` together, never a bare line number with no file. I need to see the exact code we're discussing, not recall it from earlier in the conversation.
- When I ask for something "word by word" or "syntax by syntax," actually slow down to that level — define every keyword/operator/symbol even if it seems obvious, rather than summarizing the line's overall effect.
- Don't explain one piece of jargon using another undefined piece of jargon (e.g. don't say a context "gets cancelled" without immediately grounding what cancellation concretely causes downstream). Favor mechanical precision over analogy — if I propose a metaphor or mental model, tell me plainly if it's wrong rather than letting it slide, e.g. correcting "ctx is a viewer watching a timer elsewhere" to "ctx *is* the object holding the timer."

### Other working conventions

- Comment code in **lowercase**, matching the existing style throughout this codebase (see e.g. `internal/auth/session.go`, `auth_controller.dart`) — comments explain non-obvious *why*, not restate the code.
- Build step by step: implement the specific feature asked for, then stop — don't jump ahead to related features or future-roadmap items without being asked.

## Where we left off (update this section as study/work progresses — overwrite, don't append)

Studying the backend codebase file by file, in this order so far, each time going deep (syntax word-by-word, full data flow, design rationale) rather than skimming:

- **Done:** `db/db.go` (the `DBTX` interface, `Queries` struct, `New`, `WithTx` — understood why `Queries.db` can hold either the whole pool or a single `pgx.Tx`, and why `WithTx` exists even though nothing calls it yet).
- **Done:** `db/queries/shops.sql` + generated `db/shops.sql.go` (sqlc's `-- name: X :one/:many` annotations, `ST_MakePoint`/`ST_SetSRID` PostGIS calls, `CreateShopParams`/`CreateShopRow`, `QueryRow`/`Query`/`Scan`, why `StMakepoint`/`StMakepoint_2` end up untyped `interface{}`).
- **Done:** `internal/dbctx/dbctx.go` + `context.Context` mechanics generally (`context.Background()` vs `r.Context()` as parents, what `context.WithTimeout` actually returns and when its timer starts, `defer cancel()`, the distinction between `dbctx.WithTimeout` — our own wrapper, used per-request — and the separate standalone `context.WithTimeout` call inside `mustConnectDB` — not the same timer, just the same stdlib function used twice for different reasons).
- **Done:** identified and fixed the stale-`role`-in-JWT problem (`role` was baked into the JWT as a claim; since JWTs live a year and role is mutable, a stale token could keep asserting an old role). Fix: removed `role` from `TokenClaims`/`GenerateJWT` entirely; added `db.Queries.GetUserRole` (a fresh per-request DB lookup by `user_id`); `Shops.Create`'s authorization check now calls that instead of reading a JWT claim. See `internal/auth/jwt.go`, `internal/auth/middleware.go`, `internal/endpoints/shops.go`.
- **Not yet manually tested:** log in as a `shop_owner` and confirm `POST /api/shops` still succeeds after the role-lookup change (the one live-request-path behavior change from that fix).
- **Also done:** fixed a `chatToSession` orphan leak in `internal/auth/session.go`'s cleanup sweeper — a chat that links to a session but never sends a phone number left a permanent `chatToSession` entry after its paired `sessions` entry got TTL-evicted. The sweeper's single goroutine now does a second `Range` pass per tick, deleting any `chatToSession` entry whose target `sessionID` no longer exists in `sessions` (piggybacks on the session's own TTL rather than adding a second timestamp/goroutine).
- **Done:** `internal/auth/middleware.go` in full (`RequireAuth`, `contextKey`, `UserIDFromContext`, the bearer-token check — including *why* `contextKey` is a private named type rather than a bare string, to avoid `context.WithValue` key collisions across packages) and the `internal/endpoints/` package (`cors.go`'s `WithCORS`, `auth.go`, `shops.go`'s `Route`/`List`/`Create`) — the actual HTTP handler layer between an incoming request and the DB/session-manager code already covered above. Also covered `cmd/api/main.go` section 5 (route wiring/dependency injection) end-to-end, tracing a `POST /api/shops` request through `WithCORS` → `Route` → `RequireAuth` → `Create`.
- **Next up:** not yet specified — ask where to pick up (candidates: `internal/telegram/handler.go`, or the remaining unstudied `cmd/api/main.go` sections).

## Project overview

Domix is a marketplace app connecting shop owners and customers. It has two parts:

- `backend/` — Go HTTP server + Telegram bot that together implement passwordless auth (no traditional password login; users authenticate by linking a Telegram chat).
- `frontend/` — Flutter app (Android/IOS) that talks to the Go backend and drives the Telegram login handshake.

## Commands

### Backend (Go, run from `backend/`)

```
go run ./cmd/api             # start the API server + Telegram bot (loads ../.env)
go build ./...              # compile everything
go vet ./...                # static checks
```

Optional env vars for the DB pool: `DB_MAX_CONNS` (default 10), `DB_MIN_CONNS` (default 2) — see `cmd/api/main.go`'s `mustConnectDB`.

There is no test suite yet.

sqlc generates `db/*.sql.go` from `db/queries/*.sql` against the schema in `db/migrations/`:

```
sqlc generate                         # regenerate db/*.sql.go after editing queries or migrations (see backend/sqlc.yaml)
```

Local Postgres requires the PostGIS extension (used for shop `location` spatial queries/index).

Migrations are applied with the `golang-migrate` CLI (`migrate`), not auto-run by the app on startup:
```
migrate -database "$DB_URL" -path db/migrations up      # apply pending migrations
```

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
flutter run --dart-define-from-file=env.json       # env.json provides API_BASE_URL
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
3. Backend returns a `https://t.me/<bot>?start=<sessionID>` deep link (Telegram's documented deep-linking format, not the unofficial `tg://` scheme — this opens the app directly via verified Universal/App Links on mobile and degrades gracefully to a web preview if Telegram isn't installed); Flutter opens it in `AuthController.startTelegramLogin`.
4. User's `/start <sessionID>` message hits the bot webhook, processed by `internal/telegram.Handler`; `SessionManager.LinkChat` maps `chatID -> sessionID` in a second `sync.Map` (`chatToSession`).
5. Bot asks the user to share their phone number via a Telegram contact button.
6. On receiving the contact, the backend looks up `name`/`role` for that chat via `GetPendingSession`, then checks Postgres by phone (`GetUserByPhone`): existing users log in (and get upgraded from `customer` to `shop_owner` if they registered a shop with a previously-customer account); new users are created (`CreateUser`).
7. `SessionManager.CompleteSession` generates a JWT (`internal/auth/jwt.go`, HS256, 1-year expiry) and stores it on the session as `status: success`.
8. Flutter polls `/api/auth/status?session_id=...` every ~2s (`AuthService.checkStatus`, capped at 60 attempts) until it sees `status: success`, then persists the JWT/role/name/phone to `flutter_secure_storage` and updates UI state.
9. A background sweeper goroutine (`startCleanupSweeper`) evicts sessions older than 10 minutes from RAM.

Known gaps called out in `docs/docs.md` (check before assuming these are solved): no refresh/two-token strategy yet (JWT is long-lived single token); users can currently repeat the `/start` + phone-share flow multiple times.

### Backend structure

- `cmd/api/main.go` — single entrypoint (`package main`, built with `go run ./cmd/api`). This file is *orchestration only*: load env config, build the Postgres pool (`mustConnectDB`), init the Telegram bot, then wire dependencies into each endpoint/handler and register routes. It deliberately contains no handler logic itself — that's all in `internal/`. `cmd/` exists specifically so this module can grow a second binary later (e.g. a background worker for the ticket marketplace) without disturbing this one — `cmd/<name>/main.go` per binary, all of them importing the same `internal/` packages.
- `internal/endpoints/` — the Flutter-facing HTTP API, one file per resource:
  - `cors.go` — `WithCORS(methods, handler)` wraps a handler with the CORS headers + OPTIONS-preflight handling every endpoint needs, so `main.go` applies it once at registration instead of each handler repeating the same header-setting code.
  - `auth.go` — `Auth` struct (holds `SessionMgr`, `BotUsername`) with `Init`/`Status` methods — the telegram-login handshake's two endpoints.
  - `shops.go` — `Shops` struct (holds `Queries`, `JWTSecret`) with `Route`/`List`/`Create` methods and the `ShopResponse` DTO. `Route` dispatches GET→`List` (public) vs POST→`Create` (wrapped in `auth.RequireAuth`, since only GET is public).
  - Handlers are methods on small structs whose fields *are* their dependencies (e.g. `&endpoints.Shops{Queries: queries, JWTSecret: jwtSecret}`) — the standard idiomatic-Go way to do dependency injection into `net/http` handlers without a framework. When the ticket marketplace endpoints get built, this is the pattern to follow: a new file here (e.g. `tickets.go`), a new small struct, wired into `cmd/api/main.go` the same way `Shops`/`Auth` are.
- `internal/telegram/handler.go` — `Handler` struct (`Bot`, `SessionMgr`, `Queries`, `JWTSecret`) with `ProcessUpdates` (the update loop, run in its own goroutine) and unexported `handleStart`/`handleContact` for the two message types the bot cares about. This is the piece that used to be a 150-line loop inline in `main()`.
- `internal/auth/session.go` — in-memory session/handshake state machine (see Auth flow above). Read this before touching anything auth-related.
- `internal/auth/jwt.go` — JWT generation/validation (HS256, claims: `user_id`, `phone`). `role` is deliberately not a claim: it's mutable (a user can be upgraded `customer` → `shop_owner`), and a JWT lives for a year, so baking it in would let a stale token keep asserting an old role long after the DB has changed. Anything that needs the caller's current role looks it up fresh (`db.Queries.GetUserRole`) instead of trusting the token.
- `internal/auth/middleware.go` — `RequireAuth(jwtSecret, handler)` requires a valid `Authorization: Bearer <jwt>`, attaching the caller's user ID to the request context (`UserIDFromContext`). This only checks *authentication*; a handler needing a specific role (e.g. `Shops.Create` requiring `shop_owner`/`admin`) queries the user's current role from the DB itself afterward — don't assume `RequireAuth` alone is sufficient authorization for a new protected endpoint, and don't reach for a `role` JWT claim since one doesn't exist.
- `internal/dbctx/dbctx.go` — `WithTimeout(ctx)` wraps a context with a 5s deadline (`QueryTimeout`). Every DB call in `internal/endpoints` and `internal/telegram` goes through this — without it, a hung query (lock contention, a network blip) would hold a pool connection open forever instead of failing after a bounded time, which at a small `MaxConns` can starve every other request.
- `db/` — sqlc-generated data layer, deliberately kept at the top level rather than under `internal/`, and untouched by the restructuring above. `db/queries/*.sql` are the source of truth for SQL; `db/models.go` and `db/*.sql.go` are generated — edit the `.sql` and rerun `sqlc generate`, don't hand-edit the generated files (regenerating wipes any hand-added comments in them). `db/migrations/` is the schema source of truth (raw SQL, applied with the `migrate` CLI, see Commands above).
- Schema: `users` (phone is the unique identity key, `telegram_chat_id` unique+nullable, `role` constrained to `customer`/`shop_owner`/`admin`) → `shops` (one owner, `contact_phone`, nullable `image_url` — column exists but nothing currently writes to it, see below — PostGIS `geometry(Point,4326)` location with a GIST index for nearby-shop queries) → `products` (belongs to a shop). All child relations cascade-delete.
- Shop creation/listing (`db/queries/shops.sql`) reads/writes the PostGIS point via `ST_MakePoint(lng, lat)` / `ST_X`/`ST_Y` directly in SQL rather than a Go geometry type/library — sqlc's generated params for the `ST_MakePoint` args come out as untyped `interface{}` (`StMakepoint`/`StMakepoint_2` — pass plain `float64`s in, pgx encodes them fine). Remember `ST_MakePoint` takes `(longitude, latitude)`, the reverse of the usual lat/lng spoken order — easy to swap by mistake.
- `POST /api/shops` takes a plain JSON body (name/contact_phone/address/latitude/longitude), matching the auth endpoints' convention. Shop photo upload was deliberately deferred (see `shops.image_url` above) — when it returns, that's the natural point to switch this one endpoint to multipart, not before.

### Database connection pool (`cmd/api/main.go`, `mustConnectDB`/`waitForShutdown`)

The pool is explicitly configured (`pgxpool.ParseConfig` + `NewWithConfig`), not left on pgx's bare defaults — those tie `MaxConns` to `runtime.NumCPU()` of whatever machine happens to run the process, which is an accident, not a capacity decision. `DB_MAX_CONNS`/`DB_MIN_CONNS` env vars (default 10/2) let this be tuned per-deployment without a code change. `GET /health` pings the pool, for load balancers/uptime checks. `waitForShutdown` listens for SIGINT/SIGTERM and does an orderly shutdown (`http.Server.Shutdown` lets in-flight requests finish, then `dbPool.Close()`) — this is also why the Telegram update loop and HTTP server both run in their own goroutines now rather than one blocking `main()` directly: `main()` needs to stay free to wait on the shutdown signal.

### Frontend structure

Feature-first layout under `lib/features/<feature>/{data,presentation}`:
- `data/` — repositories/services doing network or storage I/O (e.g. `auth_service.dart`, `stores_repository.dart`).
- `presentation/controllers/` — `ChangeNotifier` view-models consumed via `provider`. `AuthController` and other controllers are constructed once in `main.dart` and handed to `MultiProvider` as singletons (`AuthController` additionally enforces this with a private static-instance factory constructor, since it's also referenced directly from non-widget code).
- `presentation/screens/` and `presentation/widgets/` — UI.

**Visual design tokens live in `core/constants/app_theme.dart` (`AppRadius`, `AppShadows`, `AppMotion`) plus the neutral/tint ramp in `app_colors.dart` (`hairline`, `surfaceMuted`, `textFaint`, `primarySoft`, `primaryTint`, `success`/`successSoft`).** New UI must pull radius/shadow/colour from these instead of inlining hex codes or arbitrary radii — before they existed, nine different corner radii and about nine ad-hoc greys were in use simultaneously, which is what made screens look unrelated to one another. The scale is deliberately short: radius `xs 8 / sm 14 / md 20 / lg 28`, shadows `card` (barely-there lift) / `floating` (nav bar, sheets, map overlays) / `accent(colour)` (the glow under a primary button). Brand orange is reserved for primary actions, active state and highlights; surfaces use white/`surfaceMuted` with `hairline` borders and dividers.

**`floating_bottom_nav_bar.dart` is deliberately excluded from the token pass.** It was once reworked into a translucent `BackdropFilter` glass bar and the founder explicitly asked for the original back, exactly as it was — opaque white, 76px tall, with the filled orange gradient pill for the active tab. Don't "modernise" it again without being asked.

Home-screen placeholder content lives in `features/home/data/home_placeholder_content.dart` (`HomeShopPreview`, the `HomeCategory` enum, `kPopularShops`, `kNearbyShops`) rather than inline in each widget, so swapping in real backend data is a one-file change. It replaced `List<Map<String, dynamic>>` literals read with casts like `cat['icon'] as IconData` — that shape had no compile-time safety, so a mistyped key crashed at runtime. Category *labels* are resolved per-language from `AppLocalizations` via an exhaustive `switch` on `HomeCategory`, because they were previously hardcoded Russian and stayed Russian when the app switched to Uzbek. `SectionHeader` (`features/home/presentation/widgets/section_header.dart`) is the shared "Title … See all" row the three home sections had each duplicated.

Localization is custom, not using generated ARB/gen-l10n: `core/localization/app_localizations.dart` + `language_provider.dart` (a `ChangeNotifier` holding the current `AppLanguage`, provided app-wide via `MultiProvider` in `main.dart`). Supported locales are `ru` and `uz`. `LanguageProvider.locale` drives `MaterialApp.locale`.

`AuthService` implements exponential backoff with jitter (`_executeWithRetry`) for all network calls to the Go backend — reuse this pattern rather than adding ad-hoc retry logic if extending other repositories to hit the real API.

`core/constants/api_config.dart` (`ApiConfig.serverRoot`) derives the backend's plain server root (e.g. `http://host:port`, no path) from the same `API_BASE_URL` env value `AuthService` uses (which has `/api/auth` baked in) — anything that isn't an auth call (shops, image URLs) should build its URL off `ApiConfig.serverRoot`, not duplicate/hardcode a base URL.

### Map feature (`features/map/`)

- `data/geocoding_service.dart` — free forward/reverse geocoding via OpenStreetMap's Nominatim public API (search-by-address and coordinates→address). Rate-limited to ~1 req/sec per Nominatim's usage policy; fine at current scale, revisit (self-hosted Nominatim or a paid provider) before real production traffic.
- `presentation/screens/map_screen.dart` — the bottom-nav Map tab: fetches all shops via `StoresController.loadStores()` (called once in `initState`; `IndexedStack` in `app_shell_screen.dart` keeps this screen's state alive across tab switches, so it won't re-fetch every time the tab is revisited) and plots each as a `ShopMarker`. Tapping a pin shows a bottom sheet with the shop's rating/address, a tap-to-call button, and a `ShopBanner` at the top (renders the real photo if `shop.imageUrl` is ever set, otherwise a plain orange placeholder — shops don't have photos yet, see the backend structure notes on `shops.image_url`).
- `presentation/screens/location_picker_screen.dart` — the interactive location picker used by "add store". Uses the "move the map, not the pin" pattern (pin fixed at screen center via `IgnorePointer` + `FractionalTranslation`, user drags the map underneath) rather than a draggable marker, since `flutter_map` has no built-in draggable-marker widget. Reverse-geocodes the center (debounced 700ms after the map stops moving) to resolve a human-readable address, which becomes `shops.address`. Returns a `LocationPickResult` via `Navigator.pop`.
- `presentation/widgets/shop_marker.dart` — `MapPinIcon` (the visual teardrop pin) is shared between `ShopMarker` (tappable, used on the map) and the location picker's fixed center pin, so both look consistent.
- Map tiles are the public `tile.openstreetmap.org` server (free, no key) via `flutter_map` — same "revisit before high-traffic production" caveat as Nominatim above; the OSM attribution shown via `SimpleAttributionWidget` is a license requirement (ODbL), not optional decoration.

### Adding a shop (`features/stores/`)

`data/stores_repository.dart` now talks to the real backend (`fetchStores` / `createShop`, JSON POST with the JWT as a Bearer token) — this used to be a hardcoded stub; if you see references elsewhere in memory/docs to it being a placeholder, that's stale. `presentation/screens/add_store_screen.dart` is the form (name, contact phone, and a location from `LocationPickerScreen` — no photo field for now, deliberately); on success the new `Shop` is appended directly to `StoresController`'s in-memory list (no re-fetch needed) so it shows up on the map immediately.
