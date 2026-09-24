---
name: backend
description: >
  Core architectural rules, schema constraints, PostgreSQL behavior, authentication flows,
  rate limiting, image storage and data mechanics for the Domix Go backend. Use when working on
  internal/endpoints, db/queries, authentication, or any Go server logic.
---

# Domix Backend Architecture & Rules

### Authentication
A passwordless 6-digit code delivered by **Telegram Gateway**. `internal/verify` is the only place that knows a provider exists; `internal/auth/code.go` mints, hashes and checks the code. Pending codes live in RAM — a mutex and a plain map, because every wrong guess is a read-modify-write that `sync.Map` cannot do atomically — so an abandoned signup leaves no row behind. The same code backs the phone change and the `/delete-account` page, and `CodePurpose` is what stops one being spent on the other.

`users.phone` holds one canonical spelling only: `998XXXXXXXXX`. A JWT is never trusted for a role — the middleware reads it from the database on every request, so a demotion takes effect immediately.

Every send costs money, so three budgets are correctness rather than hardening, and all three are needed: **per phone** (3 quick, then one an hour), **per address**, and **`dailySendBudget` across every caller** — the last being the only one an attacker cannot spread around, and therefore the actual ceiling on the bill.

### Rate limits — the unit is an account, not an address
Uzbek carriers put thousands of subscribers behind one public address, so an address bucket throttles a whole carrier as though it were one person. It never reproduces in testing, where a laptop has an address to itself.

- **Signed-in traffic is keyed by account id** — `Limiter.Keyed` with `auth.UserIDFromRequest`, which verifies the token's signature and touches no database.
- **Public traffic has no account to key by, so the answer is to make it cheap, never to squeeze the limit.** `endpoints.publicCache` holds the three whole-market reads (`/api/home`, `/api/shops`, `/api/categories/{code}/products`) for 20s. One caller rebuilds and the rest wait on that rebuild — a cache without single-flight is a stampede at every expiry — and a *failed* rebuild serves the last good copy rather than a 500, bounded by `staleFor`.
- **Nothing a cached read answers may depend on who is asking.** This is why favourites are fetched by the app as its own list instead of the server stamping `is_favorite` on every product.
- **A path serving both a public GET and an authenticated write needs two buckets** — see `browse` in `main.go`. `POST /api/shops` seeds a hundred rows; `GET /api/shops` is the map.
- Not cached, deliberately: **search** (the caller chooses the query; bounded by `Home.SearchSlots` at 40% of the pool instead) and **per-shop reads** (an owner must see their own edit immediately).
- Every per-caller limit depends on `TRUST_PROXY=true` behind a proxy — `ratelimit.ClientIP`, `deploy/nginx.conf`.

### Images
One root, `images/`, served at `/images/` and mirrored byte-for-byte as R2 object keys. `images/shops/` holds the curated catalogue (`shops/universal/001.jpg`) and owner uploads (`shops/uploads/<2 chars>/<random>.jpg`). `Disk` and `R2` are both real implementations, picked in `main.go` by whether the R2 keys are set; a half-filled configuration refuses to boot rather than silently writing to the wrong one.

- **The database stores a relative path, never a url** — the host differs between a laptop, the tunnel and `img.domix-api.uz`.
- Every upload is decoded and **re-encoded into two JPEGs**: a 1000px master for the edit screen and a 400px thumb for grids, which is ~99% of all image traffic. The re-encode is what strips EXIF (phones write GPS into it) and applies the rotation tag.
- **Write the files, then point the row at them, then unlink the old ones.** Any other order can leave a row naming a file that is gone — a broken tile in every grid, unrecoverable by retrying.
- Names are random because urls are cached for a year: reusing one leaves every phone showing the old photo.
- **`imagestore.IsUpload` is the line that protects the catalogue** — one curated file is shared by every shop of a category, so deletion refuses anything outside `shops/uploads/`.
- Files whose row went with a deleted shop are swept from the admin panel. Three rules keep it from eating a live photo: files are listed **before** the database, nothing younger than an hour is touched, and a referenced master claims its thumbnail. The sweep is bounded by a **wall-clock budget**, not a count — each R2 delete is a round trip and nginx cuts a request off at 60s.

### The Basket Price Index & History
Ranks shop competitiveness. A "template" is a curated, shared list of standard products; to be ranked at all an owner MUST price **every** item in it, or the comparison is not between the same baskets. A shop's total is divided by its market's average.

`shop_basket_index` is a table kept current by **database triggers**, not a view computed on read: the read side is every customer opening the app, the write side is an owner retyping a price. The recompute is always whole-market — the index divides by the market average, so one new price moves every competitor's score. An advisory lock is what stops two owners pricing at once from overwriting each other. Yesterday's score is gone the moment it is recomputed, which is why `basket_history` takes hourly snapshots: it is the only table holding data that cannot be recomputed.

### Schema
`products.template_key` separates the curated global products from an owner's own additions. `products.price` is nullable because "not priced yet" and "free" are different facts. `favorites` is keyed `(user_id, product_id)` and cascades from both — a saved card must open onto something.

Removed down to their tables and to be rebuilt from nothing, **do not restore the old designs**: support (migration `000003`) and the job marketplace.

### Product search
`GET /api/products/search` matches every word of the query, in any order, against the name lowercased with ё folded to е — on both sides, because 19 catalogue names are spelled with ё and nobody types it. Each word becomes a regex; a word typed in Latin carries its Cyrillic spelling as an alternative (`(kabel|кабел)`), with the rules and alias list in `internal/catalog/translit.go`.

A pg_trgm GIN index (migration `000002`) serves it over **exactly** the expression `SearchProducts` compares — change one character of either and every search silently becomes a sequential scan. The longest word is sent separately as the "anchor" because GIN can serve one `~` but not `~ ALL`, and it must be at least three letters.
