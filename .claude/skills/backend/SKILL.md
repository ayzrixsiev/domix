---
name: backend
description: >
  Domix's Go API — handlers in internal/endpoints, the auth code flow, rate limiting and the
  public cache, image storage and its sweeps, product search, the basket price index, sqlc
  queries in db/queries and migrations in db/migrations. Use when writing or changing a handler,
  a query, a migration or a schema rule. Not the /admin page itself (admin-panel skill), not
  Flutter (frontend skill).
---

# Domix backend

## Auth — a 6-digit code, one provider

`POST /api/auth/request-code` delivers a code to the number, `POST /api/auth/verify` mints the JWT.
The same code backs the phone change (`/api/me/phone/request-code`, `/api/me/phone/verify`) and the
public `/delete-account` page (`/api/account-deletion/request-code`, `/api/account-deletion/confirm`);
`CodePurpose` is what stops one code being spent on the other.

- **Telegram Gateway is the only provider** — `gatewayapi.telegram.org`, one bearer token in
  `TELEGRAM_GATEWAY_TOKEN`. `internal/verify` is the only package that knows a provider exists;
  `internal/auth/code.go` mints, hashes and checks the code.
- `VERIFY_SENDER` overrides the choice; empty means telegram if the token is set, otherwise console.
  **Naming a provider without its credentials is a boot error, never a quiet fall back to console** —
  an api that boots green, answers 200 to every login and delivers nothing is discovered by the first
  real user. The console sender logs the code and is the development provider, not a stub: the whole
  flow walks on a laptop with an empty `.env`. The retired telegram-bot handshake is archived in
  `docs.md`; do not rebuild it.
- **Pending codes live in RAM, never in Postgres**, so an abandoned signup leaves no row behind. A
  mutex and a plain map rather than `sync.Map`, because every wrong guess is a read-modify-write.
  A code dies after `CodeTTL` or `MaxCodeAttempts` wrong guesses.
- `users.phone` holds one canonical spelling, `998XXXXXXXXX`, and a pending code is keyed by it. A
  request and a verification that normalise differently are a map miss the user reads as "you never
  asked for a code".
- **A JWT is never trusted for a role** — the middleware reads it from the database on every request,
  so a demotion takes effect immediately.
- Every send costs money, so three budgets are correctness rather than hardening, and all three are
  needed: **per phone** (3 quick, then one an hour), **per address**, and **`dailySendBudget` across
  every caller** — the last being the only one an attacker cannot spread around, and therefore the
  actual ceiling on the bill.

## Rate limits — the unit is an account, not an address

Uzbek carriers put thousands of subscribers behind one public address, so an address bucket throttles
a whole carrier as though it were one person. It never reproduces in testing, where a laptop has an
address to itself. Every bucket is declared together in `main.go`.

- **Signed-in traffic is keyed by account id** — `Limiter.Keyed` with `auth.UserIDFromRequest`, which
  verifies the token's signature and touches no database.
- **Public traffic has no account to key by, so the answer is to make it cheap, never to squeeze the
  limit.** `endpoints.publicCache` holds the three whole-market reads (`/api/home`, `/api/shops`,
  `/api/categories/{code}/products`) for 20s. One caller rebuilds and the rest wait on that rebuild —
  a cache without single-flight is a stampede at every expiry — and a *failed* rebuild serves the last
  good copy rather than a 500, bounded by `staleFor`.
- **Nothing a cached read answers may depend on who is asking.** This is why favourites are fetched by
  the app as its own list instead of the server stamping `is_favorite` on every product.
- **A path serving both a public GET and an authenticated write needs two buckets** — see `browse` in
  `main.go`. `POST /api/shops` seeds a hundred rows; `GET /api/shops` is the map.
- Not cached, deliberately: **search** (the caller chooses the query; bounded by `Home.SearchSlots`,
  40% of the pool, instead) and **per-shop reads** (an owner must see their own edit immediately).
- Every per-caller limit depends on `TRUST_PROXY=true` behind a proxy — see the `lessons` skill for
  why only the last `X-Forwarded-For` entry is trustworthy.

## Images

One root, `images/`, served at `/images/` and mirrored byte-for-byte as R2 object keys. `images/shops/`
holds the curated catalogue (`shops/<category>/<random>.jpg`) and owner uploads
(`shops/uploads/<2 chars>/<random>.jpg`). `Disk` and `R2` are both real implementations, picked in
`main.go` by whether the R2 keys are set; a half-filled configuration refuses to boot rather than
silently writing to the wrong one.

- **The database stores a relative path, never a url** — the host differs between a laptop, the tunnel
  and `img.domix-api.uz`.
- Every upload is decoded and **re-encoded into two JPEGs**: a 1000px master (`OutputMaxSide`) for the
  edit screen and a 400px thumb (`ThumbMaxSide`) for grids, which is ~99% of all image traffic. The
  re-encode is what strips EXIF (phones write GPS into it) and applies the rotation tag.
- **Write the files, then point the row at them, then unlink the old ones.** Any other order can leave
  a row naming a file that is gone — a broken tile in every grid, unrecoverable by retrying.
- Names are random because urls are cached for a year: reusing one leaves every phone showing the old
  photo. This holds hardest for a curated file, which *every* shop of a market draws.
- **Two write doors.** `Save` writes an owner's upload; `SaveCatalogue` writes a curated photo and
  refuses anything whose resulting path would not pass `IsCatalogue`, so a category of
  `universal/../uploads` is an error rather than a write into the other namespace. Same decode, same
  two JPEGs. `POST /api/admin/catalogue/{category}/photo` is the only caller.
- **Two deletion doors that never overlap.** `RemoveFile` accepts only `shops/uploads/` (`IsUpload`);
  `RemoveCatalogueFile` only `shops/<category>/<file>` (`IsCatalogue`). `List(ctx, prefix)` sends the
  prefix to the store, so neither sweep enumerates the other's files.
- **`shops.image_path` is the third kind of row that names a file** (migration `000008`): the storefront
  a VIP card draws, written only by `POST /api/admin/shops/{id}/photo`. It is an *upload*, so
  **`AdminUploadedImagePaths` and `ListUploadedImagesOfUser` read `shops` as well as `products`** — or
  the uploads sweep deletes a live storefront an hour after it is uploaded and the card goes blank with
  the database perfectly consistent. `TestTheUploadsSweepLeavesAStorefrontPhotoAlone` is the pin.
- The sweeps themselves, and the three rules that keep them off a live photo, are in the `admin-panel`
  skill: they are driven from that page.

## The basket price index and its history

Ranks shop competitiveness. A "template" is a curated, shared list of standard products; **the basket
is its rows with `in_basket`** (migration `000006`), and to be ranked at all an owner MUST price
**every basket row**, or the comparison is not between the same baskets. A shop's total is divided by
its market's average.

- **Membership is what keeps the catalogue extendable**: a product added to a template starts outside
  the basket, so pushing it into 500 shops costs nobody their badge; it is voted in from the panel once
  most shops have priced it. `in_basket` is mirrored onto `products` like name and unit, and
  **`basket_index_after_product_update` watches it** — a vote is an UPDATE that touches no price, and
  without that line the index would keep answering about the old basket.
- **`products.in_basket` defaults TRUE** so a seeding INSERT that forgets the flag fails towards the old
  behaviour; `product_templates.in_basket` defaults FALSE; `CreateCustomProduct` writes FALSE explicitly.
- **`shops.excluded_from_index` is an admin's own decision and wins over completeness**
  (`SetExcluded`, `POST /api/admin/shops/{id}/exclude`). `shop_basket_index` answers "is every product
  priced"; this flag holds a shop out of the comparison with every price filled in. Flipping the column
  is all the handler does — a trigger recomputes.
- `shop_basket_index` is a table kept current by **database triggers**, not a view computed on read: the
  read side is every customer opening the app, the write side is one owner retyping one price. The
  recompute is always whole-market, since the index divides by the market average. An advisory lock is
  what stops two owners pricing at once from overwriting each other.
- Yesterday's score is gone the moment it is recomputed, which is why `basket_history` takes hourly
  snapshots: **it is the only table holding data that cannot be recomputed.**

## Schema

- **`product_templates.image_path` is validated on every write** (`checkTemplatePhoto`): a non-empty
  path must pass `imagestore.IsCatalogue` and name its own category's folder, and a category whose
  names the owner writes may not carry one at all — that last rule is what keeps `templateFlags`
  granting обои owners the right to their own photograph. The sync carries the other half, keeping a
  shop's `shops/uploads/…` path instead of overwriting it.
- `products.template_key` separates the curated global products from an owner's own additions.
- `specs` is the line under the name and holds the size — **one size is one row and one card**
  (migration `000007` dropped the old size groups).
- `products.section` is the chip a row sits under in its shop's grid, validated by
  `catalog.IsValidSection`; **it is not `category`**, which is what the home screen browses across
  every shop. Both are copied from the template at seeding and by the sync.
- `products.price` is nullable because "not priced yet" and "free" are different facts.
- `favorites` is keyed `(user_id, product_id)` and cascades from both — a saved card must open onto
  something.
- Removed down to their tables and to be rebuilt from nothing, **do not restore the old designs**:
  support (migration `000003`) and the job marketplace.

## Product search

`GET /api/products/search` matches every word of the query, in any order, against
`name || ' ' || specs` lowercased with ё folded to е — on both sides, because 19 catalogue names are
spelled with ё and nobody types it. Each word becomes a regex; a word typed in Latin carries its
Cyrillic spelling as an alternative (`(kabel|кабел)`), with the rules and alias list in
`internal/catalog/translit.go`.

A pg_trgm GIN index (`idx_products_search_text`, migration `000007`) serves it over **exactly** the
expression `SearchProducts` compares — change one character of either and every search silently becomes
a sequential scan. The longest word is sent separately as the "anchor" because GIN can serve one `~` but
not `~ ALL`, and it must be at least three letters.

`GET /api/products/suggest` is the panel under that field as it is typed. **It never touches the
database**: `catalog.Suggest` matches the typed words against the curated template names held in
memory (`internal/catalog/suggest.go`, rebuilt by every `catalog.Load`), so a request costs a few
hundred substring comparisons and needs neither the cache nor a search slot - only its own wide
limiter. It reads the query with `catalog.QueryWords`, the same normalisation `searchPatterns` uses,
or the panel would offer names the search cannot find. A query with no three-letter word is an empty
list and not the 400 search answers with: that is the ordinary state of a half-typed word.

## The category drill-down

`GET /api/categories/{code}/products` shows **`categoryOffersPerLine` offers of one product, then the
next product**, not a price-sorted wall. Every shop of a market prices the same curated rows, so a plain
`ORDER BY price` answers «Смеси» with two hundred shops' glue before its second product. A line is
`template_key`; an owner's own row has no key and lines up on `lower(name || ' ' || specs)` instead.
Lines are ordered by their own cheapest offer, so the page still opens on the best price.

`ListProductsByCategory` does it with `row_number() OVER (PARTITION BY …)` in a subquery, and
**`offers_per_line` carries a `::bigint` cast or sqlc will not compile the file** — it has no type for a
parameter compared against a column a subquery invented, and fails with
`column "offer_rank" does not exist`. Search does the same with `searchOffersPerLine` (6) and an `offset`:
the app shows «Ещё» only after a full page of `searchResultsLimit` rows, so a short page is the last one and
nothing more is requested. Its order is total (`line_price`, `line`, `offer_rank`) so pages never overlap,
and `line_price` counts only available offers, so a line nobody can sell sorts last.
