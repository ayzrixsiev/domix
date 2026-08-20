# CLAUDE.md

Guidance for Claude Code in this repository. **This file holds what applies everywhere.** Three
things load on demand instead:

| where | what | loads when |
| --- | --- | --- |
| `frontend/CLAUDE.md` | Flutter commands, toolchain, emulator, per-screen guidance | working under frontend/ |
| `shipping-to-play` skill | Android build, signing, MapKit, device testing, pre-release TODO | release or Android work |
| `admin-panel` skill | /admin, /delete-account, RequireAdmin, anomalies, support inbox, template sync | working on internal/webui/ or admin.go |

---

## 1. Product

**Domix connects construction shops with customers, built around map-first discovery.** A customer
opens the map and, for each nearby shop, sees what a standard basket of popular materials costs
there versus the market — `4 850 000 сум · на 4% дешевле рынка`.

**Next direction:** a job-ticket marketplace — clients post work, workers pick it up, workers get a
rated profile — layered on `users.role`. The **Заявки** tab is its placeholder. **Do not scaffold it
until asked.**

---

## 2. Working with this repo

The founder is building this while learning Go, Flutter and system design from scratch. It is a real
product headed for production and paying customers: hold the code to production standards while
explaining it at a beginner-friendly level.

### How to explain

Whenever you touch something non-trivial, cover:

- Syntax — explain unfamiliar Go/Dart syntax and language features clearly. This includes things like
  goroutines, channels, `sync.Map`, `late`, `Future`/`async`, mixins, extension methods, pattern
  matching, etc.

  "Word by word" is a trigger for detailed syntax explanation. When the founder asks for something
  word by word, explain the syntax token by token: each relevant keyword, operator, symbol, type,
  modifier, and construct, what it means, and why it is used there. Do not skip unfamiliar syntax.

- Data flow — explain the whole path when a feature spans layers:
  tap → controller → repository → HTTP → handler → sqlc → Postgres → response → decode →
  `ChangeNotifier` → rebuild.

- Design rationale — explain why the approach was chosen and the important alternatives that were
  rejected. If a decision is pragmatic because of budget, timeline, or MVP constraints, say so;
  don't dress a shortcut up as architecture.

Plain language, never at the cost of hiding the real mechanism.

### Confirmed working style

- When the founder asks for a high-level explanation, explain the subject from the text they sent,
  before looking at or walking through the code. Assume they have not read the implementation yet.
  Explain what it is, why it exists, how it works, where it fits, and what happens when it breaks.

- When the founder restates something in their own words, check the restatement point by point —
  quote it, say whether it is right, explain why. A fresh explanation that skips validating their
  attempt is much less useful.

- Always paste the real code inline, paired with `file_path:line_number`.

- Never explain jargon with more jargon. Prefer mechanical precision to analogy. Correct a wrong
  mental model plainly.

- Comments are lowercase and explain non-obvious why, never restate the code.

- Keep the repo minimal — the founder is minimalist and loves to keep the system and flow of it in
  his head, and clutter is a real cost. Do not add a file, script, flag or abstraction that only
  pays off in a hypothetical future; the bar is "does this earn its place today". This never trades
  away performance or correctness — it is about the number of moving parts, not about doing less
  engineering. When something has stopped earning its place, say so and delete it rather than
  leaving it lying around.

- Explain at the altitude asked for. Do not turn a high-level question into a code tour. Do not give
  a word-by-word syntax lecture unless the founder asks for it.

### Documentation

Documentation goes in this file. Don't edit `docs/docs.md` unless asked.

---

## 3. Backend commands — run from `backend/`

```bash
go run ./cmd/api      # API server + Telegram bot (loads ../.env)
go build ./... && go vet ./... && go test ./...
sqlc generate         # regenerate db/*.sql.go after editing queries or migrations
migrate -database "$DB_URL" -path db/migrations up
```

- `migrate` failing with `SSL is not enabled on the server` → append `?sslmode=disable`. Only the CLI
  requires TLS; the same `DB_URL` works everywhere else.
- **After `migrate up` or `sqlc generate`, restart the server** — a running process holds the SQL it
  was compiled with (§8).
- Local Postgres needs PostGIS. Pool tuning: `DB_MAX_CONNS` (10), `DB_MIN_CONNS` (2).
- Reset users locally: `TRUNCATE TABLE users RESTART IDENTITY CASCADE;`

Required `.env` at the repo root: `DB_URL`, `TELEGRAM_BOT_TOKEN`, `WEBHOOK_URL`, `PORT`,
`JWT_SECRET`. `SUPPORT_EMAIL` is optional but must be set before submitting to Play.

Optional and silent when wrong: `TRUST_PROXY=true` makes the rate limiter read
`X-Forwarded-For`, correct **only once something in front always rewrites it** — otherwise the
limiter either buckets the whole internet together or hands attackers a fresh identity per request.

**Changing what a new shop is stocked with is done in the admin panel**, not in Go: drop the photo
into `photos/<категория>/` under the next free number, then `/admin` → Шаблоны → «Добавить товар».

### ngrok

The tunnel is a reserved static domain, `jeep-prepay-penholder.ngrok-free.dev`. Two files hold it:
`.env`'s `WEBHOOK_URL` (where Telegram **pushes** in) and `frontend/env.json`'s `API_BASE_URL` (where
the app **pulls** from). Neither can be localhost.

```bash
ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080   # the ONLY correct form
ngrok http 8080                                              # a fresh random hostname, silently
```

**Always use the `--url=` form.** A reserved domain is only used if it is asked for, so the second
line silently strands both files on a host that no longer exists — and each fails differently and
quietly: a stale `WEBHOOK_URL` means `/start` never arrives and login hangs on the polling screen; a
stale `API_BASE_URL` means every request times out and the home screen shows the showcase fallback as
though the database were empty (§7). Neither says "your tunnel moved".

A `scripts/ngrok-sync.sh` used to rewrite both files from ngrok's local API. **It was deleted and
must not come back** — it was written for the free tier's rotating hostnames, and once the domain
became reserved it did nothing but rewrite the same two lines with the same two values. The domain is
fixed, so the two files are correct permanently; typing the command right is the whole fix.

**Both files are read at startup** — restart the Go process (it registers the webhook on boot) and
`make dev` (env.json is compiled in).

### Test suites

`internal/catalog` and `internal/pricing` are pure. `db` and `internal/endpoints` need a **real local
Postgres**: they open a transaction, work, and roll back, so they never commit. They read `DB_URL`
from the environment (falling back to the repo-root `.env`) and `t.Skip` cleanly without one. Real
Postgres on purpose — what they check is what the *database* computes, and a mock would only check
what the test author believed.

---

## 4. Architecture

### Auth: Telegram-linked login, no passwords

Stateful in RAM, not the DB, until login completes.

1. Flutter POSTs `name` + `role` to `/api/auth/init`; `SessionManager` puts a `pending` session
   `sess_<base64url>` in a `sync.Map`. **No DB row exists yet**, and the id is 48 characters and **must
   stay under 64** (§8).
2. The backend returns `https://t.me/<bot>?start=<sessionID>` — the documented deep-link format, not
   the unofficial `tg://` scheme, so it opens via verified App Links and degrades to a web preview.
3. `/start <sessionID>` hits the webhook; `LinkChat` maps `chatID → sessionID` in a second `sync.Map`,
   and the bot asks for a phone number via the contact button.
4. On the contact, the backend reads that chat's `name`/`role`, looks the user up by phone, and either
   logs them in (upgrading `customer` → `shop_owner` if they registered a shop) or creates them.
   `CompleteSession` issues a JWT and marks the session `success`.
5. Flutter polls `/api/auth/status` every ~2s (capped at 60), then persists JWT, role, name and phone
   to `flutter_secure_storage`.
6. A sweeper evicts sessions older than 10 minutes and drops orphaned `chatToSession` entries, which
   would otherwise leak one per chat that never sends a number.

**Known gaps:** no refresh token and no revocation list, so the four-month expiry is the only way a
session ends. Users can repeat the flow multiple times.

### Backend layout

**`cmd/api/main.go`** is the single entrypoint and *orchestration only* — config, pool, bot, DI,
routes, no handler logic. **`internal/endpoints/`** is the Flutter-facing API, one file per resource;
handlers are methods on small structs whose fields *are* their dependencies
(`&endpoints.Shops{Queries: q, JWTSecret: s}`) — idiomatic Go DI without a framework.

| file | holds |
| --- | --- |
| `cors.go` | `WithCORS(methods, handler)` — headers + preflight, applied once at registration |
| `auth.go` | `Auth.Init`/`Status`, plus `Auth.Me` (`GET /api/me`) and `Auth.DeleteMe` via `RouteMe` |
| `shops.go` | `Shops` — `Route`/`List`/`ListMine`/`Create`/`Update`/`Delete` |
| `shop_dto.go` | `ShopResponse` and one mapper per sqlc row shape |
| `home.go` | `Home.Get`, `ProductsByCategory`, `SearchProducts` |
| `product_crud.go` | the four product endpoints |
| `product_image.go` | the two photo endpoints — multipart upload and removal (§7) |
| `support.go` | the app's half of the support inbox (§7) |
| `admin.go` | the whole privileged surface, middleware included — see the `admin-panel` skill |
| `authz.go` | `authorizeShopAccess`, `writeAPIError`, the `accessError` type |
| `request.go` | `decodeJSONBody`, `validateCoordinates` |

`shop_dto.go` exists because sqlc emits one row struct per query (six near-identical ones) full of
`pgtype` wrappers that serialize as `{"String":"","Valid":false}` rather than as null. The mappers are
longhand: generics cannot read a field off a type parameter, and reflection would trade a
compile-time guarantee for a runtime one in the layer whose job is to be the stable app contract.

`decodeJSONBody` caps the body at 64 KiB and writes its own 400. **`validateCoordinates` rejects
out-of-range values and exactly `(0, 0)`** — PostGIS stores `ST_MakePoint(999, 999)` as a valid
geometry that is simply nowhere, so an unvalidated shop is written successfully and never appears on
the map with nothing in any log; `(0,0)` is the Gulf of Guinea and means a form submitted before a
location was picked.

Also: **`internal/auth/`** (session, HS256 JWT at four months, `RequireAuth`) · **`internal/catalog/`**
(templates + the twelve product-category codes) · **`internal/pricing/`** (index → badge, §5) ·
**`internal/dbctx/`** (`WithTimeout`, a 5s deadline on every DB call, so a hung query fails bounded
instead of holding a pool connection forever) · **`internal/imagestore/`** (turns an uploaded photo
into a file the api will serve, and owns the one directory those live in — pure, so its tests need no
database) · **`internal/telegram/handler.go`** (bot loop, §8) ·
**`internal/webui/`** (the two embedded pages) · **`db/`** (sqlc-generated, deliberately top-level;
`db/queries/*.sql` and `db/migrations/` are the sources of truth — **edit the `.sql` and rerun
`sqlc generate`**, never the generated files).

### Authorization is two questions, not one

`RequireAuth` proves *who* is calling and that the account still exists — every other logged-in user
passes it. A handler needing a role looks it up **fresh from the database** every time, because
`jwt.go` deliberately carries no role claim: a token lives months and a role can change inside that
window. **Don't assume `RequireAuth` alone is sufficient, and don't reach for a `role` claim.**

**`RequireAuth` reads the database, and that is not optional.** It takes an `auth.UserStore` (an
interface it declares itself; `*db.Queries` satisfies it structurally) and calls `GetUserRole` on every
authenticated request; without it a deleted account keeps full access for its token's remaining
months. A missing row answers **401 `account_deleted`**, which the app clears its storage on; a
*failed* lookup answers **503, never 401**, so database trouble cannot sign every user out. Pinned by
`TestADeletedUserIsRefusedImmediately`.

**The app checks its own session rather than waiting to be told.** `checkExistingLogin` hydrates from
secure storage *and* reads the JWT's own `exp` claim — plain base64 JSON, so expiry is detectable
offline and the first frame is already a guest screen. `verifySession()` calls `GET /api/me` unawaited
on launch and on every `AppLifecycleState.resumed`, which is what makes an account deleted while the
phone was in a pocket land on the guest screen. **Only `SessionExpiredException` logs anyone out** — a
timeout or a 500 is not evidence about the token. `/api/me` also returns the current `role`, which is
how a `customer → shop_owner` upgrade reaches an app installed before it.

**Connection pool** (`mustConnectDB`): explicitly configured, because pgx's default ties `MaxConns` to
the `NumCPU()` of whatever machine happens to run it. `GET /health` pings the pool. `waitForShutdown`
handles SIGINT/SIGTERM in order (in-flight requests finish, then the pool closes) — which is why the
Telegram loop and HTTP server each run in their own goroutine: `main()` must stay free to wait.

---

## 5. The Basket Price Index

1. **Total the shared basket** for each shop — every template product, at that shop's prices.
2. **Average those totals across the market** — shops of the same *shop category*.
3. **`index = basket ÷ market average × 100`.** 100 is the market price, 96 is 4% cheaper.

Defined once as the `shop_basket_index` view. Grouping by shop category
is what makes it comparable: an Обои basket is 10 items and a Универсальный one 99, so ranking by raw
сум sorted shops by which template seeded them. Dividing by each market's own average cancels the unit.

### Two rules inside the view — each is a bug if reversed

- **Template rows only.** The template is the shared basket, identical in every shop of a category,
  which is the only reason two totals compare. "Identical" means the **`template_key`**, not the name
  — an Обои slot is named differently in every shop and is still the same basket line (§7).
- **The basket has to be complete.** `HAVING COUNT(price) = COUNT(*)` — one unpriced template row and
  the shop has no row in the view: no total, no index, no badge, and **no contribution to its
  category's average either.** It stays on the map; it is simply not an active shop.

The founder's rule is **price everything or you are not in the comparison**, and the real cost is far
fewer badges at launch. Two consequences, both handled: the showcase fallback covers the thin home
screen (§7), and **the rule has to be visible to the owner** — that is `ShopProductsScreen`'s progress
card and nowhere else. Don't make the rule stricter or looser without moving that card.

`basket_price` and the tier are nullable end to end (`pgtype.Int8` → `*int64` → `int?`) and are **null
together or present together** — the view has no partial state.

**The mean is deliberate.** Averages are outlier-sensitive (one shop typing an extra zero drags its
category), and that is an **accepted MVP tradeoff**: bad data is handled operationally through the
panel's anomaly report. **Do not switch to the median.** (The anomaly report *does* use a median, for
a different question — see the `admin-panel` skill.)

**The raw index is never shown to a user.** `ShopResponse` carries `basket_price`, `price_tier` and
`price_difference_percent`; **there is no `price_index` field and adding one back is a regression.**
It is for ranking (SQL) and choosing the tier (Go), and "96" is a comparison a reader must be taught
to perform. The admin panel is the one exception. A card shows `⭐ 4.8` / `4 850 000 сум` /
`🟢 на 4% дешевле рынка`.

**Every threshold lives in `internal/pricing/tier.go` and nowhere else** — that placement is the
point, not the values:

| index | tier | badge |
| --- | --- | --- |
| `< 98` | `cheaper` | 🟢 "на X% дешевле рынка" |
| `98 – 102` | `average` | 🟡 "Средняя цена по рынку" |
| `> 102` | `dearer` | 🔴 "на X% дороже рынка" |

X is `abs(100 − index)`; the view already rounded, so it is never rounded twice. The ±2 band is a
placeholder and should be expected to be wrong — it is narrow, so almost every shop lands in a
coloured bucket. **Making it dynamic is a change to that one file** (obvious version: derive it from
the standard deviation of a category's indices); keeping it server-side makes that a deploy rather
than an App Store release. There is deliberately **no minimum market size** — consequence: the only
shop in a category scores exactly 100 and reads as "market average", correct but looks like a bug.

**Flutter side:** `PriceTier` (`features/stores/data/price_tier.dart`) and `PriceTierBadge`
(`core/widgets/price_tier_badge.dart`) — a coloured dot plus the sentence, in five places. A filled
`Container` circle rather than 🟢/🟡/🔴 emoji, whose size, alignment and hue vary per platform.
**Colour is never the only channel** — the words say "дешевле" or "дороже" either way.
`PriceTierPinLabel` is the map-pin form: the same dot plus a signed `−4%`, because a pin has room for
four characters and forty are on screen. The average tier prints `≈` and no number: an unsigned "1%"
beside a yellow dot invites exactly the question the tier exists to answer.

`PriceTierBadgeSize` picks the size: `pill` (the default — the tinted capsule, on a VIP card),
`compact` (no pill, smaller, inside a row that already has a container round it) and `headline` (the
shop card's price block — no pill either, and large enough to be the thing the eye lands on). It
replaced a `compact` bool when a third size arrived; **a second bool would have allowed a fourth
combination that means nothing.** The point of it being one widget is that tier → colour → sentence is
decided in one file, so a new surface cannot invent a fourth wording.

---

## 6. Schema

`users` (phone is the unique identity key, `role` ∈ `customer`/`shop_owner`/`admin`) → `shops` (one
owner, `contact_phone`, nullable `image_url`, `category` ∈ the four catalog codes, nullable
`vip_until`, PostGIS point + GIST index) → `products`. `users` → `support_messages` →
`support_thread_reads` (§7). All child relations cascade-delete.

**`db/migrations/` starts from one baseline and that is deliberate.** Fifteen numbered migrations
were collapsed into `000001_baseline` before there was anything deployed to migrate: they were a
record of decisions, and the decisions are written down here instead. It seeds `product_templates`
too, so a fresh database is a working one. **Changing the schema from here on is a new numbered
migration on top of it** — nothing may edit the baseline once a database exists that ran it.
`000002_support_thread_reads` is the first of those; its own header explains why it exists.

`shops.image_url` exists but nothing writes it — photo upload was deferred. When it returns, that is
the point to switch `POST /api/shops` to multipart, not before.

### Invariants

- **`shops.average_paycheck` must never come back.** `INT NOT NULL DEFAULT 0` with nothing writing it,
  so every shop advertised `0 сум` for the number the product rests on — invisible only because every
  display site was guarded by `> 0`. Dropped, replaced by the derived index.
- **`shops.vip_until` is a timestamp with exactly one setter.** VIP while `vip_until > now()`. It was
  a boolean at first, so turning a placement *off* was something a person had to remember; a date
  inverts who has to act. `UpdateShop` omits the column so an owner cannot grant themselves the
  carousel. The wire carries a computed `is_vip`; sending the date would invite comparison against a
  device clock the user controls. Granting is `PUT /api/admin/shops/{id}/vip`.
- **`users.role = 'admin'` can only be set with SQL.** `/api/auth/init` maps anything that is not
  `shop_owner` to `customer`, and the Telegram handler only upgrades `customer → shop_owner`. The
  value stays in the CHECK constraint for the panel, but **nothing reachable over the network can
  assign it.**
- **Nothing about Telegram is stored on `users`.** The bot is a login mechanism, not a channel:
  completing the handshake *is* the phone verification, and the phone number is what the account is
  keyed on afterwards. A `telegram_chat_id` column existed — unique, nullable, rewritten on every
  login — and the only thing that ever read it was a badge in the admin panel. **Don't add one back
  "for when we send notifications"**: a column nothing reads is a column nothing keeps correct, and
  the day a message is actually worth sending, the chat id is in the update that asks for it.
- **`products.price` is nullable and that is load-bearing** — a seeded product has no price until its
  owner types one, which is a different fact from "free". Treating a missing price as 0 breaks the
  "укажите цену" prompt that *is* the post-creation workflow.
- **`products.template_key` is the only thing distinguishing a template row from the owner's own**
  (`NULL` = theirs). A separate `is_template` flag was rejected as a second copy of one fact. Unique
  per `(shop_id, template_key)`, so re-seeding fails loudly instead of doubling a catalogue. **The key
  must stay stable forever** — it identifies "the same product across every shop", which the index
  depends on, and it is what the editing rules key off (§7).
- **`products.image_path` holds two kinds of path, and only one of them may be deleted.** A seeded row
  points at a curated catalogue shot (`universal/001.jpg`) shared by every shop of that category; an
  owner's upload points under `uploads/`. Both are relative and both are served by the same handler,
  so the prefix is the only thing telling them apart — `imagestore.Store.Remove` refuses everything
  outside `uploads/`, which is what stops one shop replacing its photo from unlinking the file forty
  others draw. **Removing a photo from a seeded row restores the catalogue path rather than clearing
  the column**, and a seeded row the catalogue *has* a shot for refuses an upload outright (§7).
- **`products.category` holds one of twelve locale-neutral codes** (`mixes`, `blocks`, `lumber`,
  `metal`, `fasteners`, `roofing`, `insulation`, `electrical`, `plumbing`, `paints`, `finishing`,
  `tools`) — the same list the home grid renders. Free text meant "Крепёж" and "крепеж" were two
  groups and the value stayed Russian when the app went Uzbek. Unlike `shops.category` there is **no
  CHECK constraint** (that one is structural; this list is content that grows with the home grid);
  `catalog.IsValidProductCategory` guards the two statements that write it.
- **`products.article` and the Excel bulk upload are gone** — the spreadsheet existed so an
  owner wouldn't type a catalogue from nothing, and a shop no longer starts from nothing. If bulk
  import returns it must be *seeded-catalogue-aware*: match rows by `template_key` and price them.
- **`shops.rating` is the same shape of bug `average_paycheck` was** — stored, never written, so every
  shop reads 0.0, and it cannot be derived until a `reviews` table exists. The app hides the star, and
  the rule lives in **two getters and nowhere else**: `Shop.hasRating` and `HomeShopPreview.hasRating`,
  both `rating > 0` (two because the home feed carries its own lighter model; documented as mirrors).
  All three draw sites ask a getter, so a `reviews` table lights the star everywhere at once, and each
  site drops its own separator with it. Inventing a number was rejected: absence says "no reviews"
  without claiming anything. It is **not** the VIP carousel's sort key — that membership is sold, so
  `ListVipShops` orders by `vip_until DESC`.

### PostGIS

Location is read and written with `ST_MakePoint(lng, lat)` / `ST_X` / `ST_Y` directly in SQL. sqlc
generates the args as untyped `interface{}` (`StMakepoint`/`StMakepoint_2`) — pass plain `float64`s.
**`ST_MakePoint` takes (longitude, latitude)**, the reverse of the spoken order.

### sqlc traps, all three hit here

1. **Nullability.** `UpdateShop` originally fetched its trailing number with a scalar subquery in
   `RETURNING`; sqlc typed it non-nullable `int64`, which would have failed at scan time the first
   time anyone edited a shop with an incomplete basket — the common case. A data-modifying CTE plus an
   explicit `LEFT JOIN` makes the generator read it correctly.
2. **Type inference through functions.** `COALESCE(vip_until > now(), false)` generated as
   `interface{}`; an explicit `::boolean` cast fixes it.
3. **Window functions.** sqlc **cannot compile a window function filtered from an outer `WHERE`** — it
   does not carry an alias out of a derived table or CTE. Hence the best-offers tabs are four queries
   in a Go loop rather than one `ROW_NUMBER() OVER (PARTITION BY …)`.

The first two follow from the query's own shape rather than a config override that could drift;
`db/home_queries_test.go` pins them. Aggregates in `admin.sql` are cast explicitly (`COUNT(*)::bigint`)
and dates come back as `text`, for the same two reasons.

---

## 7. Cross-stack features

Screen-level guidance lives in `frontend/CLAUDE.md`. What follows spans both halves.

### Product catalogue: category templates

**A shop is not created empty.** The add-store form makes the owner pick one of four categories —
Универсальный (100), Сантехника (58), Древесные материалы (10), Обои (10 slots) — and `Shops.Create`
copies that list into the new shop **in the same transaction as the shop row** (which is why `Shops`
holds a `*pgxpool.Pool`: a half-seeded shop would be unrecoverable, since seeding happens only at
creation). Every shop of a category starts with identical rows differing only in price.

**Templates live in the `product_templates` table**, edited from the admin panel. They were a
Go literal on the reasoning that nothing joins against them at runtime; both halves flipped — the
founder edits catalogues often enough that a rebuild per edit *is* the cost, and the panel exists.

**The performance argument did not flip, and it shapes the design.** Nothing queries that table per
request: it is read once at startup into `internal/catalog`'s in-memory copy and re-read when an admin
saves, so `Template()` is a map lookup inside the shop-creation transaction and `IsOwnerNamedSlot()`
is a map lookup on every product in every response. **`Load()` replaces the whole map at once**, so a
reader sees old or new, never half an edit; **`Template()` returns a copy**, or one accidental write
would corrupt the template for every shop created afterwards; **an empty table is fatal at startup**,
because a shop with an empty catalogue is indistinguishable from one whose owner has not started.

**`/products.md` is no longer the source and says so at the top** — it is a snapshot kept because the
photo numbers and keys read more easily there.

**Every test harness that seeds a shop must call `loadTemplates` first** — tests do not run `main.go`,
and without it every shop gets an empty catalogue, failing as a wrong count three assertions later
rather than as missing setup. `templates_test.go` checks column widths, category codes and photo
existence against the *stored* rows and skips without a database; what it tests in memory is the store
itself (that `Load` replaces rather than merges, `Template` hands out copies, the slot key set is
rederived every load).

**Category is fixed at creation** — `UpdateShop` omits the column, since changing it would leave the
shop stocked from the wrong list. `templateSize` in `frontend/lib/features/stores/data/shop_category.dart`
is a hand-maintained copy of the template sizes, shown as a hint before the shop exists — **nothing
catches it when a template grows.**

### Product photos

**`/photos/<shop category>/NNN.jpg`, served by the API, path stored per product row.** The chain:
`catalog.Item.Image` (`"001.jpg"`) → `ImagePath(category)` (`"universal/001.jpg"`) →
`products.image_path` at seeding → `productImage()` → `"/static/products/universal/001.jpg"` →
`Product.fromJson` prepends `ApiConfig.serverRoot`.

- **The DB stores a relative path, never a full URL** — the host differs between ngrok, staging and
  production, so a stored absolute URL would be wrong in two of three.
- **Served off disk** by `staticFiles()`, root from `PRODUCT_IMAGES_DIR` (default `../photos`).
  `http.Dir` is what makes it safe — it refuses paths climbing out of the root.
  **`Cache-Control: immutable, max-age=1y` is load-bearing**: without it a 100-tile grid re-downloads
  ~4 MB on every scroll back.
- **The originals are ~312 KB each (30 MB total) and must not be served raw.** `/photos` holds copies
  resized to 1000px at quality 85 — 4 MB for all 100. Regenerate with
  `magick <src> -background white -alpha remove -alpha off -resize '1000x1000>' -strip -quality 85 <dst>`.
- **`_BannerPhoto` uses `BoxFit.contain`** — catalogue shots of one object on white, and cropping to
  fill a 118px band cuts the head off a hammer. `cacheWidth: 540` keeps the grid inside its memory
  budget; without it Flutter holds each decoded photo as a full-size bitmap, ~4 MB apiece.
- **The placeholder is painted underneath the photo, not instead of it**, so it doubles as the loading
  and error state and the tile never flashes white mid-scroll.
- `templates_test.go` asserts every item **in a photographed category** has a unique photo that exists
  on disk. Those categories are a list inside the test (`universal`, `plumbing`) because wood has no
  photos and an обои slot names no product to photograph; **adding a category to that list is the last
  step of shooting its catalogue.**

The Универсальный list is **100 real products the founder photographed**, replacing an invented
50-item one. The real shop sells мелочёвка, so `blocks`, `lumber`, `metal`, `roofing` and `plumbing`
have **zero** rows and `tools` has 37. **Anything assuming a particular product category is present in
the universal template is wrong.**

**Test numbers derived from a template's size must be computed, not written down** — an old pricing
floor was pinned as "15 of 50" in three places and every one broke when the list grew, so
`db/home_queries_test.go` says `catalog.UniversalSize`, `full - 1`, `int64(full) * unitPrice`. The
*indices* stay literals on purpose: `n` cancels out of `basket ÷ market average`, so an index that
moved when a product was added would mean the view was measuring the wrong thing.

Known cost of the twelve-code list: a Сантехника shop's 50 rows are almost all `plumbing`, where free
text distinguished Трубы / Фитинги / Запорная арматура, and `tools` absorbs discs, drills, hand tools,
gloves and tape alike. A thirteenth `consumables` code was considered and **not** added, because
twelve tiles is what the home grid's two-page pager is built around.

### Owner-uploaded product photos

**An owner may photograph what we have not photographed, and nothing we have.** In practice that is
their own products always, the ten обои slots, and the ten древесные материалы rows — and *not* the
универсальный and сантехника catalogues, which are the founder's own shots.

**The rule is asked of the template, never of the shop's category**: `templateFlags` answers
`photoEditable` as `catalog.TemplateImage(key) == ""`, and `POST /api/products/{id}/image` returns
**403 `template_photo`** when it is false — before the rate limiter and before a byte of the body is
read. A hand-kept list of "the unphotographed categories" would be a second copy of a fact the
template already holds, the same argument that keeps the обои slot keys derived (`IsOwnerNamedSlot`).
It also means **shooting a catalogue is the whole change**: those rows lock themselves, with nothing
to remember afterwards.

**`DELETE …/image` is deliberately *not* gated by the same rule.** Removal can only move a row
*towards* the catalogue, so refusing it protects nothing — and it would strand the owner who
photographed a wood row the month before the wood catalogue was shot, holding the one picture the
rule says should not be there with no way to put the shared one back.

The opposite rule held until 2026-08-20 — every row, template ones included — on the reasoning that
what makes two baskets comparable is the `template_key`, the name and the unit, none of which the
upload endpoint can touch (`SetProductImage` has no column for them), so a photograph is not part of
the comparison; and that a shop stocking a different brand of the same seeded item describes itself
more honestly with its own picture. What that missed is what the shared catalogue *is*: **one file on
disk that every shop of the category draws**, while the index insists the two rows are the same
product. An owner swapping it puts two different objects on two tiles of one product, and it is the
customer comparing the shops who is misled. The answer offered was moderation; moderating a hundred
rows in every shop by hand is not an answer.

`POST /api/products/{id}/image` is multipart with one field, `image`. Deliberately **not** a field on
`PUT /api/products/{id}`: the photo arrives as bytes while the rest of that form is json, and it is
saved the moment it is picked rather than when the owner presses «Сохранить».

**`internal/imagestore` decodes and re-encodes every upload, and each of the four steps is
load-bearing:**

- **It decodes**, because Content-Type and the filename are both written by the client. The only
  honest answer to "is this a photo" is to parse it.
- **It applies the EXIF orientation and then drops the tag.** A phone stores the sensor's raster plus
  a number saying which way up it goes; Go's decoder ignores that number and re-encoding discards it,
  so a portrait photo would be stored on its side (§8).
- **It re-encodes**, which is what strips the metadata — and a phone photo's EXIF routinely carries
  the GPS coordinates it was taken at. Serving that untouched off a public url would publish a shop
  owner's home address for any photo not taken in the shop, with nothing in the ui hinting at it.
- **It flattens alpha onto white and fits inside 1000px**, the same bound the curated catalogue is
  resized to, so an owner's tile is not four times the download of the one beside it.

Bounds: 6 MiB on the wire (`http.MaxBytesReader`, set *before* parsing — `ParseMultipartForm`'s own
argument only decides what it keeps in RAM before spilling to disk), and the source's dimensions are
checked from the header via `image.DecodeConfig` before a single pixel is allocated, because a small
compressed file can describe a 60-megapixel image. Uploads are additionally rate-limited **per
account** (1/s, burst 20) — the general limiter is per-IP, and staff on one office wifi share an
address while one phone changes address between cells.

**A stored file's name is random, and that is a caching decision.** Everything under
`/static/products/` is served `immutable, max-age=1y`, so reusing a name for a replacement photo would
leave every phone that had seen the old one showing it for a year — reported as "my new photo did not
save" by someone whose photo saved perfectly. A new name is a new url; the old file is unlinked after
the row stops pointing at it. Write, then point the row, then unlink: the opposite order has a window
where the row names a file that is gone, which is a broken tile everywhere the product appears.

`ProductResponse` carries **two booleans about the photo**, and they answer different questions.
`own_image` is whether the picture on the row is this shop's own upload or the shared catalogue's —
needed because "удалить фото" means two different things: on an upload the photo goes, on a seeded
row the catalogue shot comes back, and on a row *already* showing the catalogue shot it would do
nothing at all, so without it the button is dead on most of a fresh shop's catalogue.
`photo_editable` is whether the owner may put one there at all, and it is **sent rather than derived
in the app** for the reason `name_editable` is: what it really asks is what the template holds, which
only the server knows, and a Flutter build that worked it out from the shop's category would go
wrong the day a catalogue is photographed. It defaults to `true` when absent — which is exactly what
a backend from before the rule did.

**Directory listings are off** (`noListing` in `main.go`) — harmless while the root held only
catalogue photos, and an index of every photo in the market once uploads live under it.

Known and accepted: deleting a *shop* cascades its products away and leaves their uploaded files on
disk. One shop is a few megabytes, the paths are gone from the database, and a sweep is a cron job
whenever it is worth writing.

### Обои: a template of slots, not products

**Обои is the one category where a shared list of products is impossible.** Two wallpaper shops across
the road stock almost nothing in common, so ten named rolls would be ten rolls nine of which the shop
does not carry — every owner would leave them unpriced, which under §5 means no обои shop ever enters
the index.

So the template is **ten slots**: a slot fixes the two things that make wallpaper comparable — class
and country — and the owner writes in the product. The split, asserted in `templates_test.go` off the
key prefixes: 3 премиум (RU/CN/UZ) + 4 стандарт (2 UZ, 2 RU) + 3 эконом (1 UZ, 2 CN). **The index
still works, which is the whole reason the design is slots**: `wallpaper.premium_ru` here is compared
against `wallpaper.premium_ru` there. Different rolls, fair question.

A slot is a template row **in every respect but one**: seeded at creation, counted in the basket,
undeletable, category and unit locked. Only the name is the owner's.

- `catalog.ownerNamedCategories` (`= []Category{CategoryWallpaper}`) is the single declaration and
  `IsOwnerNamedSlot(key)` derives the key set from the template itself. **Do not hand-write a list of
  slot keys** — a second copy of "which rows are slots" that can disagree with the template.
- `UpdateProductSlot` is `UpdateProductPricing` plus `name`. **The unit stays out of the `SET` list and
  matters *more* here**: the ten rows are already ten different products per shop, so "за рулон" is
  the last thing holding the comparison together.
- `ProductResponse` carries **two** booleans, `is_template` and `name_editable`, because the edit form
  asks two independent questions and a slot answers them differently; `templateFlags(pgtype.Text)`
  derives both in one place and `Products.Update` is a three-way `switch` — slot / template / own.
- **Known limitation, deliberate:** rolls come 0.53 m and 1.06 m wide, so per-roll pricing reads a
  wide-roll shop as expensive. Per m² would be correct and is not how the trade sells.

### Product endpoints

| method | path | who |
| --- | --- | --- |
| GET | `/api/shops/{id}/products` | public — a customer browsing the map has no account |
| POST | `/api/shops/{id}/products` | owner; capped at 20 of their own (`template_key IS NULL`) |
| PUT | `/api/products/{id}` | owner; branches on `template_key` |
| DELETE | `/api/products/{id}` | owner; **refuses template rows** |
| POST | `/api/products/{id}/image` | owner; multipart, field `image` — **refuses a template row the catalogue has a photo for** |
| DELETE | `/api/products/{id}/image` | owner; restores the catalogue photo on a seeded row |

Seeded rows are deliberately **outside** the 20-product budget — counting them is what made a fresh
shop show "30 из 20". The cap is checked in Go because "at most 20 rows matching a predicate" isn't a
CHECK.

`PUT` is the most-used: it fills in the prices a seeded catalogue is missing. A template row goes
through `UpdateProductPricing`, which has no `SET` for name/category/unit **at all** — the rule is
enforced by the statement's shape, since a renamed template row silently stops being the same product
as its counterpart down the road. The app sends those fields back unchanged and they are ignored, not
rejected. `DELETE` refuses template rows so a shop can't look cheap by deleting the expensive half of
the basket.

`authorizeShopAccess(ctx, q, userID, shopID)` is the "is this caller a shop_owner **and** the owner of
*this* shop" check, needed in six places; `nil` means allowed.
**`Products.authorizeProductAccess` reads the product first and authorizes against the `shop_id` on
that row, never one the client sent** — otherwise a caller could pair their own shop's id with someone
else's product id.

### Home endpoint and search

**`GET /api/home` returns the VIP carousel and the tabbed best offers together** — one round trip, one
spinner, one error state instead of three that can disagree. It runs five queries sequentially;
goroutines would take five connections out of a pool of ten to serve one request.

#### Both home sections are a fixed number of *slots*, and the empty ones are content

**Nothing on the home screen is invented any more.** A `home_showcase_content.dart` used to supply
plausible shops whenever the database had none, so the app would demo; it is deleted, along with its
flag and its `if` in `HomeController`. What a customer sees is the database — or an empty slot saying
so in field names.

- **The VIP carousel is exactly 5 places, drawn whether or not they are sold** (`vipShopsLimit = 5`,
  mirrored by `VipShopsCarousel.slotCount`). That number is *inventory*, not a page size: VIP placement
  is a product with five units, and an unsold slot is the advertisement for it — it tells a shop owner
  scrolling the home screen that a place is still available. Raising it is a pricing decision.
- **Лучшие предложения is four tabs of 15 places** (`bestOffersLimit = 15` /
  `BestOffersList.slotCount = 15`). Here an open place means the *ranking* has room: an owner halfway
  through pricing sees how many places in their category are unclaimed. **The strip is
  `ShopCategory.values`, all four, always — never the categories the response happened to contain.**
  The server still omits a category with no ranking, and that list is now only what goes *inside* a
  tab.
  The opposite rule held until 2026-08-20 (one segment per group, no strip below two of them) on the
  reasoning that an option filtering to fifteen empty rows is a dead end. Three things outweighed it:
  the four categories are this section's **axis**, so the strip is its table of contents rather than a
  filter over what exists; an empty tab says "no shop of this kind has finished pricing", which is the
  same message the open places under it carry; and a strip built from the response **changes shape
  between two refreshes** as shops qualify, which is a control moving under the reader's finger. With
  a constant four segments, `_selected` can no longer point past the end of the list either — that
  clamp is gone.
- **All three sections are always on screen.** There is no "omit it when it has nothing" rule left
  anywhere on the home feed, and no «Пока нет магазинов» block either — a screenful of designed-empty
  cards followed by a notice explaining that it is empty says the same thing twice. A failed *load*
  still gets its own block, because that is the one thing the open places cannot explain.
- **The app never truncates what it was sent.** `vipSlotRing` / `rankedSlots`
  (`features/home/data/home_content.dart`) size themselves to `max(slotCount, shops.length)`, so a
  server that grew a section costs an old build an extra card rather than hiding a paid placement.
- **An empty slot invents nothing** — no name, no street, no amount, no percentage. It draws the real
  card's layout with the field names in place of the values. The one exception is a fixed `5` beside
  the star (`kSlotRating`), which describes the field rather than any business.
- **It is drawn at full strength, not faded.** A recessed treatment was tried and rejected: an unsold
  slot is a product being advertised, and faded frames around one real card made the strip look broken
  rather than available. Surface, shadow and banner are shared *literally* with the sold card; the
  text is the only difference. See `frontend/CLAUDE.md` §5.

**`ListVipShops` LEFT JOINs `shop_basket_index`, and reversing that is a refund.** It inner-joined
until a placement that had been granted *and paid for* did not appear until its owner had priced every
template row — silently, while the same shop sat on the map (`ListShops` has always left-joined). The
card renders name, address and no comparison, which is what `basket_price`/`price_tier` being nullable
end to end is for (§5). Pinned by `TestAPaidPlacementAppearsBeforeItsCatalogueIsPriced`.
`ListBestOffersInCategory` still INNER JOINs, deliberately: that one *is* the price ranking, and a shop
with no basket has no place in an ordering by price.

**Who gets the centre of the carousel is a commercial decision.** The carousel opens parked on the
middle slot and `vipSlotRing` fills centre-first, then alternating right and left — so with one
placement sold, that shop is the card on screen rather than two swipes past empty ones. `ListVipShops`
orders `vip_until DESC, id ASC`, which gives the centre to the longest placement still ahead of it: it
rewards the bigger purchase, a renewal moves a shop back to the middle, and it is **stable**, so the
founder can tell an owner what they bought. Rotating per request was rejected on that last point.

**`ORDER BY bi.price_index ASC` and ordering by `basket_price` are the same ordering inside one shop
category** — the index divides by that category's average, one constant for every row the `WHERE` lets
through, and dividing a list by a constant cannot reorder it. The index is used because the view
already carries it. Pinned by `TestBestOffersRankByPriceWhicheverNumberYouUse`, which exists because
the two look like independent choices and somebody will eventually "fix" it.

**Search is `ILIKE '%q%'`, a sequential scan of `products`, knowingly.** A leading wildcard cannot use
a btree index; it is sub-millisecond at launch scale and is what makes "мешок" find "Цемент в мешках",
where a prefix-only search would be indexable and would fail the query people actually type. The fix
when the table grows is a `pg_trgm` GIN index on `lower(name)` — a migration, not a rewrite.

- **`%` and `_` are escaped before they reach the pattern** (`escapeLikePattern`). Not injection — the
  query is a bound parameter — but to LIKE they are instructions, so an unescaped search for "50%"
  returns the entire catalogue, which looks like a broken search rather than a bug and would survive
  review.
- **The floor is two characters, counted in runes.** `len()` counts bytes and every Cyrillic letter is
  two, so a byte floor of 2 would accept a single letter — matching a large share of the catalogue and
  costing a full scan to return noise.

### Support messages (Сообщения)

**One conversation per user, with the founder on the other end**, in the tab that used to be a
placeholder. `support_messages` is one table and there is deliberately no `support_threads`:
a thread *is* one user's messages, so a thread row would hold no fact this table doesn't already have,
plus a `last_message_at` that could drift. `from_support` is a boolean, not a sender id — support is a
*role*, and the user must see one consistent «Поддержка» whoever answered.

| method | path | who |
| --- | --- | --- |
| GET, POST | `/api/support/messages` | the caller's own thread, and writing to it |
| GET | `/api/admin/support/threads` | the panel's inbox |
| GET, POST | `/api/admin/support/threads/{id}` | one conversation and the reply. `{id}` is a **user** id |

- **Neither app endpoint takes an id, and that is the whole authorization model.** The thread is
  whoever `RequireAuth` says is calling, so no parameter could name somebody else's messages. Pinned
  by `TestAThreadIsPrivateToTheUserItBelongsTo`.
- **`from_support` is set by the handler on both sides and never read from a request body** — false in
  the app's endpoint, true in the admin's. A client that could set it could post a message appearing
  to come from Domix, inside its own thread where nobody would see it to notice.

#### "Waiting for an answer" and "seen" are two questions, and the inbox answers both

`unanswered` — messages from the user newer than the last support reply — **is unchanged, still
derived in SQL, and still the queue.** Reading a thread does not settle it, because a conversation
opened and not replied to is still work, and the alternative loses it the moment the founder is
interrupted between reading and typing.

`unread` is the second question and the reason `support_thread_reads` exists (migration `000002`).

- **It stores a watermark, not a flag.** `last_read_id` is the newest message id at the moment a thread
  was opened; unread is `COUNT(*) WHERE id > last_read_id AND NOT from_support`. Message ids only go
  up, so unread stays *derived* — a message arriving a second later is unread by arithmetic, not
  because something remembered to set a bit. **A boolean here would be the stale flag the original
  design was right to refuse.**
- **Keyed per admin**, because "seen" is a fact about a person. One admin exists today (§6), so the
  composite key costs nothing now and is the difference between a correct model and one that clears a
  colleague's queue later. Pinned by `TestOneAdminReadingAThreadDoesNotClearItForAnother`.
- **`GET /api/admin/support/threads/{id}` writes**, and that is considered rather than sloppy: in this
  panel, opening a conversation *is* that request. A separate `POST …/read` would be a second round
  trip that can fail on its own, leaving a thread read on screen and unread in the database. It is safe
  on a GET because the write is idempotent — running it on every poll lands the same value. **The inbox
  *listing* deliberately does not do it**: that one is polled on a timer.
- **Replying marks it read too.** Answering is a stronger claim than having read, and without it the
  badge stays lit on a conversation the founder has just answered — the same complaint one step later.
- **The sidebar badge counts `unread` and disappears entirely at zero.** It briefly fell back to
  `awaiting` when nothing was unread, so a founder who read five questions and answered none still saw
  five — but that is a badge which only clears when a reply is *sent*, which is the behaviour it
  existed to fix. Plenty of messages are read and need no answer, and a badge that sits there until
  you type something is one you stop believing. **Reading is the action; the badge follows the
  action.** The queue is not lost, it is just not in the sidebar: the inbox's «Ждёт ответа» column
  carries `unanswered` per thread, and the nav button's tooltip states both numbers.
- **Opening a thread refreshes the badge immediately** — the panel fetches stats and the inbox outright
  on the first successful open rather than waiting for the next 45-second poll. A badge that clears
  five seconds after you did something still reads as stuck.
- **What the founder gives up:** one table of per-admin state that the derived design did without, and
  a `GET` with a side effect. What they get is a badge that means "something new arrived".
- **Two limits, both in Go** (`support.go`): 2000 runes per message, 10 messages per account per
  minute. The general limiter is per-IP at 20 req/s, the right ceiling for an api and no protection
  for an inbox a person reads by hand. **The length is counted in runes** — a byte limit would cut a
  Russian message at half the limit.
- **Messages cascade off `users`**, so `DELETE /api/me` takes the conversation with the account, and
  **`SupportController.handleSessionEnded` clears the in-memory copy *and stops the poll*** — a thread
  left behind after a logout is somebody's phone number and their problem, shown to whoever signs in on
  that phone next, and a poll left armed would fetch it for them.

#### How a reply reaches a phone: an adaptive poll, on both sides

**There are still no push notifications.** The visibility trigger alone (re-fetch when the tab becomes
visible, 45s staleness) meant a reply never arrived while somebody was *sitting on* the conversation —
reported, correctly, as "answers only show up if I restart the app". Both halves now poll, and both
were chosen over the alternatives for a stated reason.

**The app** (`SupportController.setWatching` / `_pollOnce`): 10s, doubling to a 60s ceiling on every
poll that finds nothing, reset to 10s by an arriving message or by the user sending. Three things keep
it from being a tight loop: it runs **only** while the tab is the visible one *and* the app is in the
foreground (`MessagesScreen` reconciles both plus the session); it **notifies only when the thread
changed**, so an unchanged poll costs no rebuild; and the timer is one-shot re-armed after each poll
finishes, so a slow server stretches the interval instead of stacking requests on it. A failed poll is
**not** an error state — the conversation on screen is still the last known good one. Rejected: push
(the real answer, out of scope, needs Firebase and a chat id §6 no longer keeps); websockets/SSE (a
second protocol to keep alive across a mobile radio, so the client ends up owning a reconnect loop
*and* a poll for the gap); long polling (a new endpoint, a rate-limiter carve-out, and sleep-mid-
request handling, to save a handful of requests a day).

**The panel** (`liveTick` in `admin.html`): a 5s tick that refreshes the dashboard counts every 45s
everywhere, the inbox every 12s while its section is open, and an open conversation every 8s — all
suspended while `document.hidden`. **SSE is the shape that fits a browser page and is the one this
panel cannot use: `EventSource` sends no headers**, and every call here authenticates with a bearer
token from `localStorage`. Making it work means an admin token in a query string — server logs, browser
history — or minting a short-lived ticket first. The poll costs one request per interval from exactly
one browser.

Both sides deliberately reuse endpoints that already exist. **Neither adds one.**

### Account deletion (two paths, one delete)

**Google Play requires it**, both in-app (`DELETE /api/me`) and as a public web page for people who
have already uninstalled (`/delete-account`, the `admin-panel` skill). Both end in the same single
`DeleteUser` statement.

- **It is a hard delete.** A soft `deleted_at` keeps the analytics tidy and also means the user asked
  you to erase their phone number and you kept it. There is nothing worth keeping: a name, a phone
  number, a role.
- **One statement, because the schema cascades** — shops go, each takes its products, and a deleted
  owner's pins leave the map in the same transaction. Hence **no "delete your shops first" check**:
  Play treats a deletion path with obstacles as no deletion path at all.
- **`DeleteUser` is `:exec`, not `:execrows`, and deleting twice is a success** — the caller is asking
  for a state, not an event.
- **The token outlives the account by exactly one request** — no revocation list, so what stops it is
  `RequireAuth`'s existence check answering 401. Pinned by
  `TestTheTokenStopsWorkingTheRequestAfterDeletion`.
- **Server first, phone second** (`AuthController.deleteAccount`). Wiping storage first throws away the
  token the request needs; wiping it after a *failed* request signs the user out of an account that
  still exists. A failure leaves everything as it was.
- **`isDeletingAccount` is a separate flag from `isLoading`** — that one draws the "open Telegram and
  share your number" overlay, the wrong thing to show someone who asked to be deleted.
- The row lives in **its own card below the menu**. `DestructiveConfirmDialog` (`core/widgets/`) is
  shared with shop deletion: cancel first and visually heavier, confirm red on the right, body naming
  what disappears. **Don't hand-roll a second one.**

**The web page deletes; it does not describe where to ask.** `/delete-account` runs the app's own
Telegram handshake pointed at delete: `POST /api/account-deletion/init` takes a typed number and hands
back a `t.me` deep link, the bot asks for a contact, `telegram.handleDeletion` deletes the row, and the
page polls `GET /api/account-deletion/status` until it stops saying `pending`. It replaced an email
address and a thirty-day promise — a promise a person keeps by hand, on a mailbox nobody watches on a
Sunday, which made it the part of the product most likely to be quietly broken.

- **One session manager, two purposes.** `SessionData.Purpose` is what the bot branches on when a
  contact arrives — it also picks the wording of the prompt, since asking for a number "for
  registration" one tap before destroying everything the user owns is a lie. `internal/auth` mints
  both ids through `newSessionID`, sweeps both, and spells the deletion one `del_` (47 chars, and
  `TestSessionIDFitsATelegramDeepLink` now checks both against Telegram's 64, §8).
- **Two questions must both be yes, and they are different questions.** The contact has to belong to
  whoever sent it (`Contact.UserID == From.ID`, §8) — that is the proof of ownership, and it is the
  same guard login relies on. And it has to be the *same* number typed on the page, or that field
  would be decorative: someone typing a stranger's number would watch their own account disappear
  while believing they had deleted somebody else's.
- **`/init` never touches the database**, so the page cannot be used to ask whether a phone number
  belongs to a Domix user — every number in the country, one request at a time, from any browser.
  That answer is given inside Telegram, once ownership is proven. `endpoints.AccountDeletion` has no
  `Queries` field at all, which is what keeps it true rather than remembered.
- **The status endpoint checks `Purpose`, and that is not tidiness.** A completed *login* session also
  reads `success`, and this page renders `success` as "your account has been deleted". Pinned by
  `TestALoginSessionIsInvisibleToTheDeletionPage`.
- **Numbers are compared on digits** (`auth.NormalizePhone`), because a browser and Telegram format
  them differently — but the account is **looked up on the raw string Telegram sent**, exactly as
  registration wrote it into `users.phone`. Two ideas of what a phone number is would be one too many.
  `TestATypedNumberMatchesTheOneTelegramReports` pins the pair.
- **A "no account for this number" is said in Telegram and nowhere else**, for the same reason `/init`
  stays quiet: by then the person has proved the number is theirs, so it tells them nothing they could
  not already find out.

---

## 8. Traps and hard-won lessons

### Telegram — three load-bearing guards in `handleUpdate`/`handleContact`. Do not remove any.

1. **`Contact.UserID == From.ID`.** The phone number *is* the identity, and "share contact" is not the
   only way a `Contact` reaches the webhook — Telegram lets you forward any address-book entry and the
   update looks almost identical. Without it, anyone holding a victim's number could log in as them.
2. **`recover()` plus a nil-check on `Message.From`.** Go has no per-goroutine crash isolation, so an
   unrecovered panic here takes the HTTP server with it — and `From` is genuinely nil for channel posts
   and anonymous group admins, which every branch below dereferences.
3. **Row-not-found is `errors.Is(err, pgx.ErrNoRows)`, never a substring match.** Comparing
   `err.Error()` to `"no rows in result set"` breaks silently if pgx rewords it, and reads any *other*
   error containing "no rows" as "this user doesn't exist", sending the flow into `CreateUser`.

### The ngrok request log is the instrument for network-shaped bugs

`curl -s "localhost:4040/api/requests/http?limit=300"` gives every method, path and status, and
**which requests are *absent* usually localises the fault.** For login: *no status polls at all* means
the app threw before it started polling; *polls but no webhook* means Telegram never delivered.

### A session id has to fit inside a Telegram deep link — 64 characters

`start=` accepts **1–64 characters from [A-Za-z0-9_-]**, and going over does not error — Telegram
**drops the parameter**, opens the bot chat, and sends no `/start`. Every symptom points away from the
cause: the link opens, the bot appears, the user presses START by hand, the backend logs `pressed
/start directly without a Flutter link`, and the app polls a session nothing will complete.

A hardening pass took ids from 4 random bytes to 32 — correct — but hex doubles that to 64 characters
and the `sess_` prefix made 69. The fix is **base64url, not fewer bytes**: `RawURLEncoding` spells 32
bytes in 43 characters and its alphabet is exactly what Telegram permits (`Raw`, because `=` is not).
`TestSessionIDFitsATelegramDeepLink` checks length *and* alphabet.

> Opening a browser before Telegram is **normal, not a symptom** — a `t.me` link is an ordinary https
> URL, so Android hands it to the default handler and Telegram claims it as an App Link.

### Android 11 package visibility breaks `url_launcher` silently

From API 30 an app cannot resolve an intent against a package it has not declared an interest in, and
`canLaunchUrl` works *by* resolving the intent — so with no `<queries>` block for `VIEW`+`https` it
returns **false for every https URL**, with Telegram installed and a browser present.
`startTelegramLogin` gated the deep link on it and threw "Telegram application is not installed".
Nothing in logcat mentions package visibility; it reproduces on neither desktop nor emulator. Two
fixes: the manifest declares `VIEW`+`https` **and** `DIAL`+`tel` (the shop card's call button is the
same trap one screen over), and the gate is gone — `launchUrl`'s own return value is the real signal.

### `shrinkWrap: true` is a network decision, not a layout convenience

It measures its height by laying out **every** child, so a 100-product catalogue mounted 100 tiles and
fired 100 `Image.network` requests ahead of everything else on the tunnel. **The symptom was not slow
images: saving a price failed** — the `PUT` queued behind the backlog, missed its 10s timeout, blamed
the user's connection, then fixed itself after ~30s once the images cached. The tell was **no `PUT
/api/products/…` in ngrok's log at all**, so the request died on the phone.

The fix is `ProductSliverGrid` inside a `CustomScrollView`. Two reporting bugs came out of it:
`TimeoutException` now has its own `timeout` code, and `ProductsController._mutate` **logs** the real
exception rather than storing it in a `message` field nothing renders.

**The second copy of this bug is gone too.** `shrinkWrap` survived in the map's shop sheet, which shows
only *priced* products — harmless while catalogues were empty, the same bug the day a shop priced all
100 — and the note here said to fix it before that mattered. It went with the sheet: `ShopCardScreen`
is a `CustomScrollView`, so the catalogue is a sliver there as well. **There is no `shrinkWrap: true`
left on a product grid; keep it that way.**

### A phone photo is not stored the way it is shown

A camera writes the sensor's raster and an EXIF tag saying which of eight ways up it goes; every
viewer is expected to honour the tag. **Go's `image/jpeg` does not** — it hands back the raw raster —
and re-encoding drops the tag with the rest of the metadata. So a photo taken in portrait, which is
most of them, would be stored on its side, and nothing anywhere would say why.

`internal/imagestore/exif.go` reads that one number out of the APP1 segment and `orient()` applies it.
The rotation runs **after** the downscale, deliberately: the target is a square bound, so it is the
same box either way up, and rotating a one-megapixel result costs a hundredth of what rotating a
twelve-megapixel source does. `TestAPhotoIsTurnedTheRightWayUpBeforeItIsStored` builds a real APP1
block rather than trusting a fixture.

The app also passes `maxWidth`/`imageQuality` to `image_picker` on every pick, which makes the plugin
re-encode on the device — that bakes the rotation in *and* converts an iPhone HEIC into something the
server can decode. Both halves are wanted: the client one saves a slow upload, the server one is the
guarantee.

### Schema/binary mismatch

A `mustMatchSchemaVersion` startup guard existed and was **deliberately removed** — catching a stale
binary belongs in CI/CD, so **don't re-add one**; recognise the shape instead. A migration dropped
`products.article` while an hour-old server still selected it: every `GET /api/shops/{id}/products`
returned 500 while `/health` answered 200 throughout (it only pings the pool). **When an endpoint fails
for no reason the code explains, check the age of the server process first:**
`ps -eo pid,lstart,cmd | grep cmd/api` against the mtime of `db/*.sql.go`.

### `Provider.of<T>(context)` defaults to `listen: true`, and provider *asserts* outside a build

Not a performance nit — a crash. `add_store_screen.dart` had
`AppLocalizations get _strings => Provider.of<LanguageProvider>(context).strings;`, so every tap
handler touching `_strings` threw before doing anything: the category tile looked like a dead button
while the location tile (which never reads `_strings`) worked. **Any `_strings`-style getter read from
a callback must pass `listen: false`.**

### A `RefreshIndicator` child that isn't a scrollable is broken twice over, silently

It builds a `Stack` whose child gets *loose* constraints and `AlignmentDirectional.topStart`, so any
shrink-wrapping child renders in the **top-left corner** — and since the indicator only drives a
scrollable, pull-to-refresh does nothing either. The fix: `LayoutBuilder` → `SingleChildScrollView`
(with `AlwaysScrollableScrollPhysics`, or content that fits exactly has nothing to overscroll) →
`ConstrainedBox(minHeight: viewport)` → `Center`. **Any full-page empty, error or loading state under a
`RefreshIndicator` must go through that shape.** The old spinner looked fine by accident: `Center`
expands to fill a bounded box, escaping the alignment trap without ever being scrollable.

### `IndexedStack` builds every tab and paints one

A screen behind a tab has no "I am visible" signal and `initState` runs once for the life of the app.
The map fetched from that one `initState`, so a failed load left «Не удалось загрузить магазины» on
screen permanently — and **restarting the app did not clear it**, because a restart put a fresh failing
fetch in the same place. Two fixes, both needed: the shell passes `isActive: index == mapIndex` so
`didUpdateWidget` catches the false→true edge, and `refreshStoresIfStale()` decides whether that edge
costs a request. The Сообщения tab uses the same pair — it is how a support reply reaches the phone (§7).

> **`build()` running is not a visibility signal under `IndexedStack`, and neither is
> `didChangeDependencies`.** Pass a bool down, or use `VisibilityDetector` — do not infer it.

### `notifyListeners()` from `didUpdateWidget` or `initState` is "setState() called during build"

Both run inside the build phase. The repository call is async, but `loadStores()` sets
`_isLoading = true; notifyListeners();` *before* its first `await`, so the notify is synchronous.
`addPostFrameCallback` is the fix, and why `_syncShops()` is a method rather than one line per call site.

### A second `pumpWidget` with the same tree shape reuses the `State` — so `initState` does not re-run

Calling a `_pumpHome`-style helper twice inside one `testWidgets` to compare two backend responses
looks obvious and does not work. Flutter diffs the new tree against the old one, and a structurally
identical tree updates in place: `_HomeScreenState` is reused, its `initState` does not run again, and
the fresh `HomeController` handed in by the provider is never asked to load. The screen sits on its
`!hasLoaded` spinner — an *infinite* animation — so the symptom is **`pumpAndSettle timed out`**, which
points at animations rather than at the controller nothing called.

Two comparisons of two responses are two tests. (A different `Key` on the screen would also force a
fresh `State`, but two tests read better and name what each one is checking.)

### A widget whose copy is hardcoded while its API pretends otherwise

`ProfileScreen._showErrorDialog(String message)` took a message, logged it, then rendered the *login*
strings — so a failed account deletion told the user to check their Telegram installation. **The
analyzer cannot see it**: `message` *was* used, in the `debugPrint`. It now takes `title`/`body` from
the caller with `detail` as the log-only string. **When a widget's copy is fixed but its constructor
implies otherwise, the second caller is what discovers it.**

---

## 9. Design system

**Visual tokens live in `frontend/lib/core/constants/app_theme.dart` (`AppRadius`, `AppShadows`,
`AppMotion`) plus the ramp in `app_colors.dart`** (`hairline`, `surfaceMuted`, `trackGrey`,
`textFaint`, `textMuted`, `primarySoft`, `primaryTint`, `success`/`successSoft`, `danger`/`dangerSoft`,
`warning`/`warningSoft`). New UI pulls radius, shadow and colour from these rather than inlining hex —
before they existed, nine corner radii and about nine ad-hoc greys were in use at once, which is what
made screens look unrelated. The scale is deliberately short: radius `xs 8 / sm 14 / md 20 / lg 28`;
shadows `card` (barely-there lift) / `raised` (content cards that must separate from the page) /
`floating` (nav bar, sheets, map overlays) / `accent(colour)` (the glow under a primary button).

- **Brand orange is reserved for primary actions, active state and highlights.** Surfaces are
  white/`surfaceMuted` with `hairline` borders. Two exceptions: "Цена не указана" (§7) and a user's own
  chat bubble.
- **`background` is `0xFFEFF1F5`, deliberately a real step below white.** White cards on a near-white
  page had nothing separating them but a shadow, and a shadow soft enough to look premium is too soft
  to do that alone. **If the app ever looks too grey, this one value is the dial.**
- **`trackGrey` (`0xFFE4E7EC`) is the one token deliberately below `background`** — the groove a white
  pill slides in, and the illusion only works if the track is recessed. It is therefore the token for
  **anything that must read as grey while sitting directly on the page**; `cardGrey` is for a grey block
  on a *white* surface and is invisible anywhere else.
- **`textMuted` (`0xFF646B76`) is a token for *glyphs*, not for prose.** One icon at `textDark` is a
  detail; twelve of them in a grid is the darkest thing on the screen, which is what Популярные
  категории looked like. `textGrey` is the obvious softer choice and sits at ~2.5:1 on `trackGrey`,
  under the 3:1 WCAG asks of a non-text mark; this one is ~4.3:1 on the same fill. A token rather than
  `textDark.withValues(alpha: 0.62)`, which composites to almost the same colour and silently changes
  the moment the fill behind it does.
- `warning`/`warningSoft` exist for the price badge's middle state — deliberately not `starYellow`,
  which reads as a highlight and is spoken for by ratings.
- **There is no longer an exception to the brand-only palette.** `ShopCategoryBanner` — the shop
  card's cover — used to be four deep desaturated gradients, one per shop category, on the reasoning
  that four orange covers would say nothing about *which* shop was opened. It is **white and brand
  orange** since 2026-08-20, one composition for all four: a near-white ground, a faint orange grid,
  a wide orange ribbon across the lower half, and a white disc carrying the category's Lucide glyph
  — the map pin's head with its colours swapped. **The cost is real and was accepted**: colour no
  longer names the category, so the glyph in the disc is the only channel left, exactly as on the
  pin. What it buys is that the top of the most important screen in the product is no longer the one
  surface that does not look like Domix. `frontend/CLAUDE.md` §7 has the rest.
- **Brand orange is not an accessible text colour on light surfaces** — `#FF6F00` is ~2.6:1 against
  `primarySoft` and 2.8:1 against white, where WCAG AA wants 4.5:1. Brand-level, not per-widget:
  white-on-orange buttons have the same ratio. Accepted for brand moments; don't reach for it where a
  number or sentence has to be read carefully.
- **All icons are Lucide** (`flutter_lucide`), one family, monochrome `textDark`. A `hugeicons` pass
  was reverted and removed: it builds an SVG string at runtime through `flutter_svg`, pulling in three
  packages and hinting less crisply than a glyph font.
- **Press feedback is `PressableScale`, not an ink ripple**, on the category and add-store picker
  tiles. A ripple spreads *inside* the shape, so on a large bordered tile it is a faint grey wash in a
  box that never moves — precisely why those controls were reported as feeling dead. `_FormTileSurface`
  pairs it with an `AnimatedContainer` and observes the press through a `Listener` rather than a second
  `GestureDetector`, since two recognisers on one subtree is how a tap starts getting eaten.
- **Every "nothing here" screen is `EmptyStateView`** — Заявки, Уведомления, my-shops, category browse,
  and the support chat's empty and guest states. **Two nested layers, the inner one white-plus-shadow
  rather than a second tint**: two tints this pale are indistinguishable on an off-white page, so
  separation must come from value, not hue. It encodes two conventions — a screen behind a nav tab uses
  **that tab's own glyph**, and the `badge` ("Скоро") separates an *unbuilt* screen from a merely empty
  one — and `iconColor`/`iconBackground` let a load failure be danger-coloured without a different
  layout. **Don't hand-roll another.**

### Do not change without being asked

- **`SectionHeader` passes no action on any section.** The VIP carousel loops endlessly, the categories
  grid pages through all twelve, and Лучшие предложения is a top-N — the link would lead nowhere in
  every case. `actionLabel`/`onAction` stay on the widget for a section that one day has more to show.
  **Don't re-add one with an empty `onAction: () {}`** — that is what all three used to do.
- **`DevicePreview` is development-only and has been removed and restored twice. Leave it.** See
  `frontend/CLAUDE.md` for why the emulator is not the replacement it looks like.
