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

## 3. Auth — SMS code via Eskiz, not Telegram
The Telegram handshake is being replaced by a one-time SMS code. `internal/telegram`, the webhook wiring and the bot dependency go with it — including the `/delete-account` flow, which shares the same handshake.

Eskiz API — `https://notify.eskiz.uz/api` ([docs](https://documenter.getpostman.com/view/663428/RzfmES4z?version=latest)):
- `POST /auth/login` (form: `email`, `password`) → `data.token`; `PATCH /auth/refresh` renews it. The token is long-lived — cache it in the process and re-auth on 401, never log in per SMS.
- `POST /message/sms/send` (form: `mobile_phone`, `message`, `from=4546`) sends the code.
- **The text must be a template Eskiz has already moderated** (`POST /user/template`). Anything else is rejected, and while the account is in test status only the three fixed test strings send at all — so the code template is submitted for moderation *before* the flow is wired.
- Every send costs money (`budget.md`: ~150 000 SMS for the year). A per-phone send limit, an attempt cap on the code and a short TTL are correctness here, not hardening.

**The architecture stays a modular monolith over REST/JSON.** No gRPC, no message broker, no Redis, no separate search engine while this is one binary talking to one Postgres: each of those buys cross-service throughput we do not have, and costs a deploy target we would have to run. Keep the domain packages clean instead — that is what makes any of them cheap to adopt on the day there is a second process.

## 4. Context Triggers (Read Before Coding)
DO NOT guess architectural rules. Depending on your current task, you MUST load the specific domain context before writing code:

* **If you are working on the Go backend, PostgreSQL schema, or authentication:** Trigger the `backend` skill.
* **If you are building Flutter UI, layouts, the map, or applying colors:** Trigger the `frontend` skill.
* **If you are working inside the `/admin` web pages or support inbox:** Trigger the `admin-panel` skill.
* **If you are handling Android APK builds, Google Play, or Yandex MapKit:** Trigger the `deployment` skill.
* **If you are debugging network failures, native platform quirks, or state management bugs:** Trigger the `lessons` skill.

## 5. Core Commands (Run from `backend/`)
- API: `go run ./cmd/api` (loads `../.env`)
- Build: `go build ./... && go vet ./... && go test ./...`
- DB: `sqlc generate` (ALWAYS restart server after running)
- Migrate: `migrate -database "$DB_URL" -path db/migrations up`
- Ngrok: `ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080` (ALWAYS use --url form)
