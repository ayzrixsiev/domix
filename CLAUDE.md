# CLAUDE.md

**Project Domix**: Map-first construction marketplace for Uzbekistan. (Go backend, Flutter frontend).

## 1. Execution Rules
- Explain concepts before code; validate assumptions point-by-point.
- Explain syntax word-by-word ONLY if explicitly asked.
- Explain data flow end-to-end (tap → controller → DB → UI).
- Comments are lowercase, explaining *why* and *what*.
- I am a minimalist, keep the repo minimal, but never in exchange of performance and professional architecture. Delete dead code.

## 2. Roadmap — three phases
Build the current phase only. Do not scaffold a later one.

1. **Shops and products** (current) — shop creation, template catalogue, prices, map, search.
2. **Exchange** — a client assembles a basket of products, shops answer it with their own price and their advantages (delivery, better availability). Competing offers on a basket, not a checkout.
3. **Masters and clients** — job tickets for workers.

## 3. Auth — a 6-digit code delivered by Telegram Gateway
One flow, no bot. `POST /api/auth/request-code` → the code is delivered to the number → `POST /api/auth/verify` mints the JWT. The same code backs the phone change (`/api/me/phone/*`) and the `/delete-account` page. Pending codes live in RAM (`internal/auth/code.go`), never in Postgres: an abandoned signup must leave no row behind.

**The only provider is Telegram Gateway** (`gatewayapi.telegram.org`, one bearer token in `TELEGRAM_GATEWAY_TOKEN`). Eskiz and the old bot handshake are gone; `docs.md` keeps the handshake written down as the restore point. With no token the console sender prints codes into the log — right on a laptop, never in production.

Every send costs money, so three limits are correctness rather than hardening, and all three are needed:
- **per phone** — 3 quick sends, then one an hour. Stops one number being made to cost money.
- **per address** — stops one machine walking through numbers.
- **`dailySendBudget`, every caller together** — the only one an attacker cannot spread around, and the actual ceiling on the bill.

A wrong code is capped at `MaxCodeAttempts` and the code dies after `CodeTTL`.

## 4. Rate limits — bucket by account, not by address
Uzbek mobile operators put **thousands of subscribers behind one public address**, so an address bucket throttles a whole carrier as though it were one person — and it never shows up in testing, where a laptop and an office wifi each have an address to themselves.

- Anything a signed-in caller does is keyed by account id (`Limiter.Keyed` + `auth.UserIDFromRequest`).
- Public endpoints stay keyed by address and are deliberately loose: they are floors against a flood, not fine control. **A path that serves a public GET and an authenticated write needs both buckets** — see `browse` in `main.go`.
- **Never tighten a public per-address limit to protect something. Make the thing cheap instead.** The browsing reads (`/api/home`, `/api/shops`, `/api/categories/{code}/products`) are the same bytes for everybody, so `endpoints.publicCache` holds them for 20s: a crowd costs one set of queries, not one per person, one caller rebuilds while the rest wait, and a failed rebuild serves the last good copy instead of a 500. Search is not cached (the caller chooses the query) and is bounded by `Home.SearchSlots`; per-shop reads are not cached, because an owner must see their own edit immediately.
- **Nothing a public read answers may depend on who is asking** — that is what would take it out of the cache. Favourites are the worked example: the app fetches its own set once and paints the hearts, rather than the server stamping `is_favorite` on every product.
- Every per-caller limit needs `TRUST_PROXY=true` behind a proxy (`ratelimit.ClientIP`, `deploy/nginx.conf`).

## 5. Comments — short, or not there
**One or two lines, lowercase, saying *why*.** Never a paragraph, never a history of what the code used to be, never a restatement of what the line does. `internal/endpoints/shops.go` and `shop_dto.go` are the reference.

A longer comment earns its place only when the code would be got wrong without it: a rule that breaks production **silently**, or a decision the next reader would helpfully undo. Those are marked `**bold**` so they are findable. Work still to come is marked `ROADMAP:`.

Same rule in Dart and in SQL. If a comment needs three paragraphs, the design is the thing to fix.

**The architecture stays a modular monolith over REST/JSON.** No gRPC, no message broker, no Redis, no separate search engine while this is one binary talking to one Postgres: each of those buys cross-service throughput we do not have, and costs a deploy target we would have to run. Keep the domain packages clean instead — that is what makes any of them cheap to adopt on the day there is a second process.

## 6. Images
One root, `images/`, served at `/images/` and mirrored byte-for-byte as R2 object keys. `images/shops/` holds the curated catalogue (`shops/universal/001.jpg`) and owner uploads (`shops/uploads/<2 chars>/<random>.jpg`); `products.image_path` stores that **relative path and never a url**, because the host differs between a laptop, the tunnel and img.domix-api.uz.

- Every upload is decoded and re-encoded into **two JPEGs** — a 1000px master and a 400px thumb. The re-encode is what strips EXIF (a phone writes GPS into it) and applies the rotation tag; the thumb is ~99% of all image traffic.
- **Write the files, then point the row at them, then unlink the old ones.** Any other order can leave a row naming a file that is gone.
- Names are random because urls are cached for a year: a replacement must be a new url.
- **Two deletion doors that never overlap**: `RemoveFile` takes only `shops/uploads/` (`IsUpload`), `RemoveCatalogueFile` only `shops/<category>/<file>` (`IsCatalogue`). A curated file is drawn by every shop of a category, so the catalogue sweep treats it as used while *any* template or shop row names it.
- The VIP carousel and category tiles are **app assets** (`frontend/assets/decorations/`), not server files: they are the first thing on the home screen and have to be there before the network is.

## 7. The price comparison, sizes, maps
- **The basket is the template rows with `in_basket`, not every template row.** A shop is compared only once every basket row has a price, so a product added to a template starts *outside* the basket (`product_templates.in_basket` defaults FALSE) and is voted in from the panel once «Оценили» is nearly full. **`products.in_basket` defaults TRUE on purpose**: an INSERT that forgot to copy the flag must fail towards the old behaviour, not towards a shop silently missing from the comparison.
- **One size, one card.** Each size is its own row with its own price, and the size is written in `specs` — the line under the name («Квадратная · 24 Вт · 6500 К»). The index, the search and favourites all work per row; never fold sizes into one card or one row. Search reads `name || ' ' || specs` (migration `000007`), so «диск 125» finds the 125 mm disc.
- **`section` is not `category`.** A section is a chip over one shop's own grid (universal only so far, `catalog/sections.go` ↔ `ProductSection`); a category is what the home screen browses across every shop.
- **Address search: Photon while typing, Nominatim for a pin and for a submitted search.** Nominatim's policy forbids as-you-type; the public Photon instance allows it but promises no speed. Yandex's free MapKit is **1000 DAU** (yandex.ru terms, not yandex.com), forbids storing what its API returns, and wants its terms linked from «О приложении» (`AboutScreen`).
- ROADMAP: **the admin panel becomes reachable only through an SSH tunnel once the server exists.** nginx answers `deny all` on `/admin` and `/api/admin/`, and the panel is opened as `ssh -L 8081:127.0.0.1:8080 <server>` → `http://localhost:8081/admin`. That makes a stolen admin token useless from the internet — today it is a permanent compromise, since an admin can mint admins. No code change is needed: the panel uses relative paths.

## 8. Context Triggers (Read Before Coding)
DO NOT guess architectural rules. Depending on your current task, you MUST load the specific domain context before writing code:

* **If you are working on the Go backend, PostgreSQL schema, or authentication:** Trigger the `backend` skill.
* **If you are building Flutter UI, layouts, the map, or applying colors:** Trigger the `frontend` skill.
* **If you are working inside the `/admin` web pages:** Trigger the `admin-panel` skill.
* **If you are handling Android APK builds, Google Play, or Yandex MapKit:** Trigger the `deployment` skill.
* **If you are debugging network failures, native platform quirks, or state management bugs:** Trigger the `lessons` skill.

## 9. Core Commands (Run from `backend/`)
- API: `go run ./cmd/api` (loads `../.env`)
- Build: `go build ./... && go vet ./... && go test ./...`
- DB: `sqlc generate` (ALWAYS restart server after running)
- Migrate: `migrate -database "$DB_URL?sslmode=disable" -path db/migrations up` (the local Postgres has no TLS)
- Ngrok: `ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080` (ALWAYS use --url form)

Removed down to their tables and to be rebuilt from nothing — do not restore the old ones: **support** (migration `000003`) and the **job marketplace** (the Заявки tab is a placeholder; phase 1 is shops and customers only).
