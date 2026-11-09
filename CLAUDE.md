# CLAUDE.md

Domix: a map-first construction-materials marketplace for Uzbekistan. Go backend (`backend/`), Flutter app (`frontend/`), one Postgres. Modular monolith over REST/JSON.

## Load context before coding
Do not guess domain rules. Load the matching skill first:
- Go backend, Postgres schema, auth, rate limits, images, price comparison → `backend`
- Flutter UI, layouts, the map, address search, colors → `frontend`
- `/admin` web pages, VIP photos, the «Накладные» section → `admin-panel`
- APK builds, Google Play, Yandex MapKit, server and nginx → `deployment`
- network failures, native platform quirks, state bugs → `lessons`

## Standard of work
- The best production-grade solution always wins: the one a strong product company would ship. Minimalism means nothing unneeded. It never means a weaker design, a shortcut or a workaround.
- Add only what the current task needs: no speculative features, abstractions, config or flags. Write tests where they guard real behaviour (money, auth, invariants, tricky logic), not to raise a count.
- Delete dead code completely: no commented-out code, no shims for removed behaviour, no "removed X" notes.
- Non-trivial change: read the relevant code, state the plan and any assumption you are unsure of, then build. Ask when a requirement is ambiguous instead of guessing.
- One feature at a time. Done means it builds, vets and passes tests (commands below).
- Follow existing patterns. Reference files: `internal/endpoints/shops.go`, `shop_dto.go`.

## Comments
Comments are for the next reader, usually Claude. Write one only when the code would otherwise be got wrong.
- One or two lines, lowercase, English, saying *why*. Never what the line does, never history, never a numbered walkthrough.
- No comment for an obvious choice. Explain a choice only when the alternative looks just as reasonable.
- Longer only for a rule that breaks production silently or a decision the next reader would undo. Mark those `**bold**` so they are greppable. Future work is marked `ROADMAP:`.
- Same rules in Go, Dart and SQL. A comment that needs a paragraph means the design needs fixing.

Bad, restates the code: `// 2. postgres connection pool set up and handed to queries`
Good: `// signed-in callers by account, others by address: one carrier IP fronts thousands of users`

## Architecture
One binary, one Postgres. No gRPC, message broker, Redis or separate search engine: each buys cross-service throughput we do not have and adds a deploy target to run. Keep domain packages clean so any of them is cheap to adopt once there is a second process.

## Production
**The domain and the server are bought and live.** `domix-app.uz` (registered at Turn Cloud, DNS in
Cloudflare) resolves to **95.182.119.72**, an Ubuntu 24.04 VPS at Airnet in Uzbekistan — 2 cores,
3.8 GB RAM. `ssh ubuntu@95.182.119.72`, password login, the password is **not in this repo**: ask the
founder. One box runs everything: nginx on 80/443, the Go api on 127.0.0.1:8080, Postgres, and the
product photos on its own disk. Cloudflare R2 holds the nightly backup and serves nothing.
**It is deployed and serving.** `https://domix-app.uz/health` answers `ok`, the api runs as the
`domix` user under `domix-api.service`, Postgres 18.6 with PostGIS holds the 283-row catalogue, and
`domix-backup.timer` mirrors both to R2 every night at 03:30. A real phone has signed in through Telegram against
production, so the whole chain is proven; the Play listing is what is left. The `deployment` skill has the server
table, the `.env` table, how the box was actually built, the admin-panel tunnel and the open list;
read it before touching the server, nginx, certbot, the backups or a release build. Passwords are in
this project's memory directory, never in this repo.

## Roadmap
Build the current phase only; never scaffold a later one.
1. **Shops and products** (current): shop creation, template catalogue, prices, map, search.
2. **Exchange**: a client posts a basket, shops answer with their own price and advantages. Competing offers, not a checkout.
3. **Masters and clients**: job tickets for workers.

Removed down to their tables, to be rebuilt from scratch. Do not restore the old code: **support** and the **job marketplace**.

**Корзина** (the tab that was Заявки) is live: a customer sends a list to Domix and staff read it in the panel. It is not phase 2: no shop sees a list and nothing is offered back.

## Invariants that fail silently
Detail and reasoning live in the `backend` skill.
- Sign-in sessions (`internal/auth/session.go`) and pending codes live in RAM, never in Postgres.
- A shared contact signs in only when `contact.user_id == from.id`; anything else is a forwarded card.
- Signed-in requests are rate-limited by account id, never by address.
- A cached public read must never depend on who is asking.
- `products.image_path` is a relative path, never a url. Write files, then point the row, then unlink the old ones.
- One size is one product row and one card. Never fold sizes.
- `products.in_basket` defaults TRUE on purpose; `product_templates.in_basket` defaults FALSE.
- "Basket" means the price index. A customer's list is a `waybill`, whatever the tab says.
- A waybill's photo lives in its Postgres row, never in `imagestore`, which is public and abroad.
- Waybills are customers-only on the server. Hiding the tab from owners is not the rule.
- Yandex address lookups go through `internal/geo` only, which counts each call in `geo_calls` before making it. The keys never ship to the app.

## Commands
Backend, from `backend/`:
- Run: `go run ./cmd/api` (loads `../.env`)
- Check: `go build ./... && go vet ./... && go test ./...`
- Codegen: `sqlc generate`, then restart the server
- Migrate: `migrate -database "$DB_URL?sslmode=disable" -path db/migrations up` (local Postgres has no TLS)
- Tunnel: `ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080` (always the `--url` form)

Frontend, from `frontend/`: `dart format .`, `flutter analyze`, `flutter test`
