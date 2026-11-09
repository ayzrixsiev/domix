---
name: backend
description: >
  Domix's Go API — handlers in internal/endpoints, the telegram bot sign-in, rate limiting and the
  public cache, image storage and its sweeps, product search, the basket price index, customers' waybills and their PDF, sqlc
  queries in db/queries and migrations in db/migrations. Use when writing or changing a handler,
  a query, a migration or a schema rule. Not the /admin page itself (admin-panel skill), not
  Flutter (frontend skill).
---

# Domix backend

## Auth — the telegram bot handshake

Every sign-in (the app, the `/admin` panel) and the public `/delete-account` page go through
`@domix_manager_bot`: the caller starts a session, opens `https://t.me/domix_manager_bot?start=<id>`,
taps the bot's one request-contact button, and polls until the session holds the outcome. Telegram
hands over a number it verified itself, so nothing is sent and nothing is paid for. `docs.md` walks it
step by step.

| route | who calls it | what it does |
| --- | --- | --- |
| `POST /api/auth/init` `{name, role, lang}` | app, panel | a login session → `{session, link, expires_in}` |
| `POST /api/auth/status` `{session}` | app, panel, every 2 s | `pending`, then `success` with `{token, user}` once, or `expired` / `not_uzbek` / `failed` |
| `POST /api/account-deletion/start` `{lang}` | `/delete-account` | a deletion session |
| `POST /api/account-deletion/status` `{session}` | `/delete-account` | `deleted` / `no_account` / `not_uzbek` / `failed` / `expired` |
| `POST /api/telegram/webhook` | telegram only | `/start <id>` links the chat; a `contact` finishes the session |

- `auth.SessionManager` (`internal/auth/session.go`) is two `sync.Map`s, session id → `SessionData`
  and chat id → session id, plus a sweeper goroutine that recovers its own panics. `internal/telegram`
  is the bot's transport (updates in, `sendMessage` out, no library); `endpoints.TelegramAuth` is the
  flow. **Sessions live in RAM**, like pending codes: an abandoned signup leaves no row, and a restart
  drops anyone mid-login, which is accepted.
- **The session id is the only secret**: whoever holds it collects the token. 32 random bytes in
  base64url, because t.me drops a `start=` longer than 64 or outside `[A-Za-z0-9_-]` without a word.
  The polls are POSTs so it never lands in an access log, and it is never logged.
- **`contact.user_id` must equal `message.from.id`**, or anybody with your number in their address
  book forwards your card and signs in as you (`TestAForwardedContactIsRefused`). A refused card leaves
  the session pending for the user's own number.
- **Exactly one contact finishes a session** (`Claim`: `LoadAndDelete` on the chat link, then
  `CompareAndSwap` out of pending), and **a finished session is handed out once** (`Collect` deletes
  it). A pending session lives `SessionTTL` (10 min); a finished one waits 2 min from the finish to be
  collected, so a login finished in its last second still reaches the next poll.
- **A purpose on every session is what stops a deletion confirmation being spent as a login**: the
  webhook branches on it, and `Collect` answers an id asked for under the other purpose exactly like an
  unknown one (`TestADeletionCannotBeUsedAsALogin`). It is `CodePurpose`'s job, redone.
- **`upsertUser` is why there is one button for registering and signing in**: the number is found or
  created; a role only goes up (`customer → shop_owner`); a typed name replaces the stored one and an
  empty one, as the panel sends, renames nothing.
- **The webhook's lock is `TELEGRAM_WEBHOOK_SECRET`**, compared in constant time against
  `X-Telegram-Bot-Api-Secret-Token`. It answers 200 to every update it can decode, handled or not, since
  anything else is redelivered ahead of every update behind it; a panic in one update is recovered and
  the update dropped. Telegram's own `sendMessage` call strips the url from a transport error, because
  **the url carries the bot token**.
- Both `TELEGRAM_BOT_TOKEN` and `TELEGRAM_WEBHOOK_SECRET` are required at boot: without them nobody can
  sign in anywhere. Registering the webhook with telegram (`setWebhook`) is a deploy step, not boot
  code - see the `deployment` skill.
- `users.phone` holds one canonical spelling, `998XXXXXXXXX` (`auth.CanonicalPhone`); telegram writes
  numbers with a `+` and sometimes without, and a foreign number ends the session as `not_uzbek`.
- **A JWT is never trusted for a role** — the middleware reads it from the database on every request,
  so a demotion takes effect immediately.
- **A token is revocable through `users.token_version`.** It rides in the token as `ver`, and
  `RequireAuth`'s one read per request (`GetTokenVersion`) refuses a token behind the row with the same
  `unauthorized` 401 an expired one gets — that code is what lands the app on the login screen.
  `POST /api/me/logout` bumps it. **There is one version per account, so a logout signs out every
  device**, which is the point when the token was copied. The app clears its storage whatever logout
  answers; an offline phone still signs out.
- **The number cannot be changed.** It is the one telegram proved; a different number is a different
  account. The phone-change endpoints and `UpdateUserPhone` were removed.

### The code flow — kept, routed, called by nobody

`POST /api/auth/request-code` + `/api/auth/verify`, and `/api/account-deletion/request-code` +
`/confirm`, over `auth.CodeManager` and `internal/verify` (Telegram Gateway). **No screen calls them,
and they stay: a founder decision against CLAUDE.md's delete-dead-code rule.** Gateway wants a $100
minimum balance; the day it is paid, these are how the project switches back. The comments on
`PhoneAuth` and `AccountDeletion` say so — do not tidy them away. What they rely on, for that day:

- `VERIFY_SENDER` overrides the sender; empty means telegram if `TELEGRAM_GATEWAY_TOKEN` is set,
  otherwise console. **Naming a provider without its credentials is a boot error, never a quiet fall
  back to console.** The console sender logs the code.
- **Pending codes live in RAM, never in Postgres**, behind a mutex and a plain map rather than
  `sync.Map`, because every wrong guess is a read-modify-write. A code dies after `CodeTTL` or
  `MaxCodeAttempts` wrong guesses; `CodePurpose` keeps a login code off the deletion endpoint.
- Three send budgets — **per phone**, **per address**, and **`dailySendBudget` across every caller** —
  because every send costs money. The daily one lives in RAM and anyone can drain it; accepted while
  nothing uses the flow. **ROADMAP: the counter moves to Postgres** before it carries real traffic again.
- `PLAY_REVIEW_PHONE` / `PLAY_REVIEW_CODE` arm a fixed code for one number on this flow. **The app no
  longer has a code screen, so a reviewer cannot reach it**; the founder has deferred the question, so
  it stays as it is.

## Rate limits — the unit is an account, not an address

Uzbek carriers put thousands of subscribers behind one public address, so an address bucket throttles
a whole carrier as though it were one person. It never reproduces in testing, where a laptop has an
address to itself. Every bucket is declared together in `main.go`.

- **Signed-in traffic is keyed by account id** — `Limiter.Keyed` with `auth.UserIDFromRequest`, which
  verifies the token's signature and touches no database.
- **Public traffic has no account to key by, so the answer is to make it cheap, never to squeeze the
  limit.** `endpoints.publicCache` holds the three whole-market reads (`/api/home`, `/api/shops`,
  `/api/categories/{code}/products`) for 60s. One caller rebuilds and the rest wait on that rebuild —
  a cache without single-flight is a stampede at every expiry — and a *failed* rebuild serves the last
  good copy rather than a 500, bounded by `staleFor`. **A failure is single-flight too**: the callers
  queued behind a failed rebuild take its result instead of each trying again, or a database that hangs
  holds the twentieth of them a hundred seconds and the stale copy reaches nobody in time. `geo`'s cache
  has the same rule, where each retry would also spend budget.
- **Nothing a cached read answers may depend on who is asking.** This is why favourites are fetched by
  the app as its own list instead of the server stamping `is_favorite` on every product.
- **A path serving both a public GET and an authenticated write needs two buckets** — see `browse` in
  `main.go`. `POST /api/shops` seeds a hundred rows; `GET /api/shops` is the map.
- Not cached, deliberately: **search** (the caller chooses the query; bounded by `Home.SearchSlots`,
  40% of the pool, instead) and **per-shop reads** (an owner must see their own edit immediately).
- **The sign-in buckets.** `/api/auth/init` and `/api/account-deletion/start` share `handshakeLimiter`
  (2/s, burst 60, by address): public, and each call holds RAM for ten minutes, but the real ceiling on
  a flood is the session manager's `maxLiveSessions`, not the address. The two polls share
  `pollLimiter` (20/s, burst 200): everybody signing in from one carrier address polls every two
  seconds, and a poll reads one `sync.Map` entry. **The webhook's bucket is one key, spent inside the
  handler after the secret check** — telegram is the only honest caller, and a bucket in front of the
  check would let anybody without the secret starve real updates. Its 429 is what telegram backs off on.
- Every per-caller limit depends on `TRUST_PROXY=true` behind a proxy — see the `lessons` skill for
  why only the last `X-Forwarded-For` entry is trustworthy. **The api refuses to boot unless the line
  says `true` or `false`**: unset behind nginx is every caller in the country in 127.0.0.1's bucket —
  every sign-in in the app sharing one address's bucket — and nothing would say so.
- **Every refusal is the same 429** (`ratelimit.Refuse`: `rate_limited`, plus a `Retry-After` of one
  token at the bucket's sustained rate), except the two the app words itself, `too_many_uploads` and
  `too_many_waybills`, which carry the same header. The app never reads the header and never retries a
  429 on its own; it is there so a client that does is told the truth.

### The address-search buckets, and why they are shaped this way

Two limiters guard `internal/geo`, and they answer two different questions.

**Per caller (`geoLimiter`, 2/s, burst 60): is one client misbehaving?** The number comes from what
entering an address actually costs. The field is debounced at 450 ms with a three-letter floor, so one
address is roughly five to eight calls, and a person who mistypes and retries spends that three or four
times over. **The first version was 0.25/s with a burst of 20 and it refused real typing in testing** —
one address entry emptied it and the next lookup was four seconds away. A bucket a human can feel is a
bucket set wrong: this one exists to stop a client stuck in a loop, nothing else.

**Globally (`geoPace`, 300/hour, burst 600): can one account drain what everybody shares?** The per-caller
bucket is keyed by account, and an account is free, so without this one signed-up caller is allowed tens
of thousands of lookups a day against a budget of 1000 for the entire app — address search dead for every
real user before lunch. **The global number is deliberately far above real traffic** (the whole app spends
tens of calls a day at 54 shops) so no honest user ever meets it; it only bounds how *fast* the day's
budget can go, not how much of it. At the pace, a full day's 990 takes about an hour and twenty minutes to
drain instead of minutes; both products together, about four and a half hours.

**The pace is spent inside `geo` on a Yandex call, never on a request.** `Service.spend` takes a token
before the daily count, so a cached answer never touches it. Spent per request in front of the handler,
one client looping at 50/s would empty it in twelve seconds — its own bucket refusing nearly all of
those requests, which would still have cost a shared token — and from then on every honest user would
be refused lookups the cache could have answered. A refused call is `geo.ErrBusy`, which the endpoint
answers with `ratelimit.Refuse`: byte for byte the 429 the caller's own bucket gives, which is all the
app knows how to read (`TestARefusedYandexCallAnswersLikeTheCallersOwnBucket`). A stale copy, where
there is one, answers instead.

**The trade-offs taken, so the next person does not quietly undo them:**

- **One global bucket covers both products, though their daily caps are separate.** Simpler, and the exact
  ceiling is still `DailyQuota` per product. Split it the day one product's traffic starves the other.
- **The global bucket is in RAM, so a restart refills it.** The daily cap is in Postgres and survives;
  this one does not need to. It is kept for two hours idle, its refill from empty: a shorter memory would
  hand it back full early.
- **After a paid plan is bought, the pace has to move with it.** 300/hour is under the free 1000 a day and
  would become the ceiling on a 25 000-a-day key.
- **Signed-out callers share a bucket by address, and an Uzbek carrier is one address.** Accepted because
  the global ceiling is the real constraint here, not the per-caller one. It would matter if the per-caller
  bucket were ever tightened.
- **ROADMAP: a per-account daily share** (say 50 of the 1000) would bound a determined attacker, who can
  still sign up repeatedly today. Needs a counter per account in `geo_calls`; not worth it before there is
  traffic worth attacking.

## Images

One root, `images/`, served at `/images/` — by this api on a laptop and by nginx in production, off the
server's own disk. `images/shops/` holds the curated catalogue (`shops/<category>/<random>.jpg`) and
owner uploads (`shops/uploads/<2 chars>/<random>.jpg`). `Disk` is the only implementation of `Storage`;
the bucket-backed one was deleted with the decision to keep photos in Uzbekistan. **R2 holds the nightly
backup of this directory and serves nothing** (`deployment` skill), and the mirror's object keys are
byte-identical to these paths, which is what lets a restored dump and a restored directory line up.

- **The database stores a relative path, never a url** — the host differs between a laptop, the tunnel
  and `domix-app.uz`, so a production dump restored onto a laptop still points at files that exist.
- Every upload is decoded and **re-encoded into two JPEGs**: a 1000px master (`OutputMaxSide`) for the
  edit screen and a 400px thumb (`ThumbMaxSide`) for grids, which is ~99% of all image traffic. The
  re-encode is what strips EXIF (phones write GPS into it) and applies the rotation tag.
- **Decodes run one per core** (`decodeSlots`). `maxSourcePixels` caps a single decode at 60 MP, which
  is 240 MB for an RGBA png that compresses to a few hundred kilobytes; nothing else capped how many ran
  at once, and one account's burst of twenty uploads would be gigabytes on a 4 GB server. A slot is taken
  after the header checks, so a refused file never queues.
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
- **`shops.image_path` is the third kind of row that names a file**: the storefront
  a VIP card draws, written only by `POST /api/admin/shops/{id}/photo`. It is an *upload*, so
  **`AdminUploadedImagePaths` and `ListUploadedImagesOfUser` read `shops` as well as `products`** — or
  the uploads sweep deletes a live storefront an hour after it is uploaded and the card goes blank with
  the database perfectly consistent. `TestTheUploadsSweepLeavesAStorefrontPhotoAlone` is the pin.
- The sweeps themselves, and the three rules that keep them off a live photo, are in the `admin-panel`
  skill: they are driven from that page.

## Waybills — the list a customer sends

The Корзина tab, `internal/endpoints/waybills.go`. **Named waybill because "basket"
already means the price index below.** A row is an immutable document, printed for staff as a накладная;
**its id is the number**, restarted at 1001 so no first customer holds «№ 1».

- **Customers only, and the server is the rule.** `Waybills.RequireCustomer` reads the role from the database
  on every request and refuses owners and admins with `customers_only`; `customerRoute` in `main.go` is the
  one chain. The app hiding the tab is a courtesy. `TestOnlyACustomerCanUseTheCart` is the pin.
- **The photo is a `bytea` in the row, not a file in `imagestore`, and that is a privacy decision.** The image
  store is a directory served to anybody who has the url, and whose nightly backup goes to a bucket abroad
  unencrypted, because `docs-privacy.md` promises it holds only shop windows; a handwritten list can carry a
  name or an address. In the row it is inside the encrypted dump instead — in the country, with no url at
  all, impossible to orphan, needing no sweep, and going with the account by cascade. **Do not add a `photo_url`**, and do not
  `SELECT photo` on a list. Read it through `GET /api/waybills/{id}/photo`, which filters by account.
- **`NormalizeDocument` keeps 2000px where a product keeps 1000**: somebody reads handwriting off this. One
  file and no thumbnail, since no grid draws one. The re-encode still strips the GPS a phone writes.
- **`items` is jsonb, not a child table**: rows have no life of their own and are always read whole.
  `waybills_rows_or_photo` holds a row to exactly one of rows or a photo, and the panel and the PDF rely on it.
- **`request_id` makes a retry safe.** The app draws one per submission and a new one after any edit; a repeat
  answers with the stored row through the no-op `ON CONFLICT` in `CreateWaybill`. Reusing an id across an edit
  would silently keep the old list.
- `cleanWaybillText` strips control characters because **postgres refuses `\u0000` inside jsonb**: one pasted
  NUL would be a 500 on every retry. Limits mirror the app: 100 rows, 150 characters a name, 30 an amount.
- **`Waybills.Sends` is the per-account budget** (ten, then one per ten minutes), spent before the body is read.
  A photo is half a megabyte of database, so this is what bounds its growth.

**`internal/waybill` draws the PDF** and knows nothing about http or the database. Drawn on request rather than
stored, so a reprint cannot disagree with the row. Liberation Serif is embedded (Times metrics, covers Uzbek
Cyrillic and Latin). `printable` drops runes the font lacks, because the PDF writer prints them as a wrong
glyph or nothing. **Кому is Domix and От кого is the customer**, the founder's call. Цена and Сумма stay
empty on purpose. A long list continues onto numbered sheets, and signatures go on the last. The date is
fixed to UTC+5, whatever zone the server runs in.

## The basket price index and its history

Ranks shop competitiveness. A "template" is a curated, shared list of standard products; **the basket
is its rows with `in_basket`**, and to be ranked at all an owner MUST price
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

- **One migration, `000001_initial`, and it is pg_dump output.** Eleven migrations were collapsed into
  it before the first deploy, while the only database that existed was a developer's. **Never edit it:**
  a schema change is a new migration beside it. Collapsing again would only be right if production were
  rebuilt from zero, and that stops being true the day a real owner types a price.
- **`product_templates.image_path` is validated on every write** (`checkTemplatePhoto`): a non-empty
  path must pass `imagestore.IsCatalogue` and name its own category's folder, and a category whose
  names the owner writes may not carry one at all — that last rule is what keeps `templateFlags`
  granting обои owners the right to their own photograph. The sync carries the other half, keeping a
  shop's `shops/uploads/…` path instead of overwriting it.
- `products.template_key` separates the curated global products from an owner's own additions.
- `specs` is the line under the name and holds the size — **one size is one row and one card**
 .
- `products.section` is the chip a row sits under in its shop's grid, validated by
  `catalog.IsValidSection`; **it is not `category`**, which is what the home screen browses across
  every shop. Both are copied from the template at seeding and by the sync.
- `products.price` is nullable because "not priced yet" and "free" are different facts.
- `favorites` is keyed `(user_id, product_id)` and cascades from both — a saved card must open onto
  something.
- Removed down to their tables and to be rebuilt from nothing, **do not restore the old designs**:
  support and the job marketplace.

## Address search

`internal/geo`, behind `/api/geo/search`, `/suggest`, `/place` and `/reverse`: Yandex's free HTTP Geocoder
and Geosuggest, with keys that never leave the server. **Each product allows 1000 calls a day for the whole
app**, counted separately, so every rule here exists to spend fewer.

**The Yandex account carries three free budgets, not two.** Geocoder and Geosuggest, 1000 calls a day
each, are the two this package spends and `geo_calls` counts. The third is **MapKit SDK, 1000 unique users
a day** (DAU, licence 6.2.3), spent by the app and counted by nobody on our side. **Opening the map more
often costs nothing; another person opening the app does**, since the shell builds the map tab at launch
and starts MapKit with it — so in practice it is every Android user of the day. It is the one hit first:
the geo budgets bite at a few thousand users, this one at a thousand. Going over has no technical cut-off
in the terms; it gives Yandex the right to block the key without notice (6.7), and the free-use page warns
that regular overruns are blocked for good. The `deployment` skill has the numbers.

- **`DailyQuota` counts every call in `geo_calls` before it is made**, against
  `geo.DailyCap` (990) over the **last 24 hours**, not a calendar day: Yandex does not say whose midnight it
  counts from. **Ten below the real 1000 and no lower**: the margin exists so the app's own
  «Поиск адресов сейчас недоступен» fires before Yandex starts refusing, not as a safety buffer against
  the bill. Going over means moving to a paid plan, which is a decision taken in the cabinet, not a
  disaster to avoid. Postgres rather than RAM because every deploy is a restart. A database that cannot count is
  a refusal too. The cap is exact because one process holds a mutex around the read-then-write.
- **The cache key is `NormalizeQuery` plus the language, and the normalized text is what Yandex is sent**,
  so a cached answer is the answer for its key. Nothing found is cached; a failure never is. An entry
  exists only for an answer Yandex gave, so the budget bounds the map. **The privacy policy promises an
  answer is held at most a week** — `cacheTTL` plus `cacheStaleFor`.
- A suggestion carries no coordinates: the app hands its `uri` back to `/place`, a geocoder call.
- **`/reverse` answers Yandex's short name** («проспект Амира Темура, 39»), falling back to the full line
  where there is none, and that is what a shop stores: the full line opens on «Узбекистан, Ташкент», which
  is all an ellipsis leaves. Never cut a prefix off in the app; outside Tashkent it would not match.
  Shops saved before this keep their long address until re-saved.
- **Reverse asks for the nearest house first**: without `kind=house` a pin on a shop beside a park answers
  with the park. Only when no house is within 100 m does a second call take any object.
- Typed lookups are bounded to Tashkent and its oblast **by Yandex** (`rspn`, `strict_bounds`,
  `countries`): the terms (5.1.2) forbid dropping or reordering results ourselves. **Tashkent-only is a
  confirmed product decision for launch**, so the hard box is right. Two things follow from it and will
  both need undoing the day the app opens a second city: Samarkand, Fergana and Namangan return nothing
  at all, and the box would become a soft bias (`ll` + `spn` toward the current view, plus
  `countries=uz`), with the rounded view area added to the cache key.
- **Suggestions ask for `types=geo` only, so organisations never appear.** This is why "Central Asian
  University" and "CAEX" come back empty while a street name works. `types=geo,biz` is the fix, and it
  is held back only because nothing has yet confirmed the Geocoder can turn an organisation's `uri`
  into a point — test that by hand before changing it.
- **A `*url.Error` prints the url, and the url carries the key** — `cleanURLError` is what keeps a timeout
  from writing it into the log.
- Answers: an empty list or a 404 `address_not_found` is "no such address"; 502 `geocoder_unavailable` and
  503 `geocoder_budget_spent` are "could not ask". The app says different sentences for them.

## Product search

`GET /api/products/search` matches every word of the query, in any order, against
`name || ' ' || specs` lowercased with ё folded to е — on both sides, because 19 catalogue names are
spelled with ё and nobody types it. Each word becomes a regex; a word typed in Latin carries its
Cyrillic spelling as an alternative (`(kabel|кабел)`), with the rules and alias list in
`internal/catalog/translit.go`.

A pg_trgm GIN index (`idx_products_search_text`) serves it over **exactly** the
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
