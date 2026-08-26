# CLAUDE.md

**Project Domix**: Map-first construction shop marketplace. (Go backend, Flutter frontend).

## 1. Execution Rules
- Explain concepts before code; validate assumptions point-by-point.
- Explain syntax word-by-word ONLY if explicitly asked.
- Explain data flow end-to-end (tap → controller → DB → UI).
- Comments are lowercase, explaining *why* and *what*.
- I am a minimalist, keep the repo minimal, but never in exchange of performance and professional architecture. Delete dead code.

## 2. Context Triggers (Read Before Coding)
DO NOT guess architectural rules. Depending on your current task, you MUST load the specific domain context before writing code:

* **If you are working on the Go backend, PostgreSQL schema, or authentication:** Trigger the `backend` skill.
* **If you are building Flutter UI components, layouts, or applying colors:** Trigger the `frontend` skill.
* **If you are working inside the `/admin` web pages or support inbox:** Trigger the `admin-panel` skill.
* **If you are handling Android APK builds, Google Play, or Yandex MapKit:** Trigger the `deployment` skill.
* **If you are debugging network failures, deep links, or state management bugs:** Read `docs/hard-won-lessons.md`.
* **If you are writing general Flutter app logic:** Read `frontend/CLAUDE.md`.

## 3. Core Commands (Run from `backend/`)
- API: `go run ./cmd/api` (loads `../.env`)
- Build: `go build ./... && go vet ./... && go test ./...`
- DB: `sqlc generate` (ALWAYS restart server after running)
- Migrate: `migrate -database "$DB_URL" -path db/migrations up`
- Ngrok: `ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080` (ALWAYS use --url form)