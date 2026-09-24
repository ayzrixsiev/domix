---
name: admin-panel
description: >
  Domix's two web pages, served by the Go API itself — the `/admin` panel (statistics,
  anomaly report, user/shop/product management, VIP placements, template
  editing and sync) and the `/delete-account` page Google Play requires. Use when working in
  `backend/internal/webui/`, `backend/internal/endpoints/admin.go`,
  `backend/db/queries/admin.sql`, the `RequireAdmin` middleware, the template sync endpoint,
  or anything about admin roles, the anomaly report, or the panel's
  HTML/CSS/JS.
---

# The web pages: account deletion and the admin panel

Two HTML pages served by the Go API for unrelated reasons: one is a Play requirement, the other
is the admin panel.

**They are `go:embed`-ed into the binary** (`internal/webui/`), where product photos are read off
disk. Photos are *content* — hundreds of megabytes, changing without the code, living outside
`backend/` where embed cannot reach. These pages are *program* — small, changing only when the API
they call changes — so embedding means deploying is copying one file and a page can never 404
because a directory was not copied. The cost is that editing HTML needs a rebuild.

**Neither page goes through `WithCORS`** — that wrapper sets `Content-Type: application/json`, so a
page routed through it downloads instead of rendering.

---

## `/delete-account`

**A Google Play requirement, not a feature.** An app that creates accounts must publish a page
describing deletion that works *without installing the app*; the in-app path does not satisfy it,
because the point is that someone who has already uninstalled can still find out how to be forgotten.

**The page performs the deletion; it does not describe where to ask for one.** It is the app's own
code flow pointed at delete: type the number, type the code that arrives in Telegram, the account is
gone — rather than an email address and a thirty-day promise a person has to keep by hand.

**The answer to `request-code` is identical whether or not the number has an account**, and a code is
only paid for when one does — otherwise a public page is a way to ask from a browser whether any
number in the country is registered with Domix. The pending entry is minted either way, so the
cooldown cannot be used to tell the two apart either.

- **One centred card, and deliberately almost nothing on it**: the field, the button, and what
  disappears. Everything else that was there — the in-app instructions, the email path, the English
  column — described a process that does not exist.
- **Two languages in one file** (ru/uz), picked by CSS off `<html lang>`, and it **renders correctly
  with javascript disabled** — the audience is a Play reviewer following a URL, and a blank page is a
  rejection. Confirming needs JS, so `<noscript>` points at the support address. Every dynamic string
  is written into the DOM in **both** languages for the same reason the static copy is: switching
  language after an answer has landed must not blank it out.
- **Three steps in one card**, swapped by the `hidden` attribute: the number, the code, the answer.
  `[hidden]{display:none !important}` is load-bearing — `hidden` is styled by the *browser's*
  stylesheet, which any author rule outranks, so `.btn{display:flex}` silently un-hides every button
  carrying it.
- **The lede disappears once the form does**, and «Начать заново» is hidden on `success` alone — after
  a successful deletion there is no account left to start again with.
- **A wrong code is fixed in place, not on a result screen**: the code step prints the refusal under
  the field and stays. Only a completed deletion and an outright failure reach step three.
- **Every refusal the api can answer with has a sentence in both languages** (`errors` in the page's
  JS, keyed by the server's stable `code`), and an unrecognised one falls through to `default`.
- **Confirm sends the number the server echoed back**, never the digits as typed: the pending codes
  are keyed by the canonical spelling, and anything else is a lookup miss read as "wrong code".
- The support address is `{{SUPPORT_EMAIL}}`, substituted once at startup rather than baked into the
  markup — it is the value most likely to be wrong on a deployment. Unset it falls back to
  `support@domix.uz` **and logs a warning at boot**. It is now only the way to reach a person when the
  flow itself fails, which is the one thing a self-service page cannot cover.
- `/delete-account/` and `/account-deletion` are 301s onto it, because the URL goes into the Play
  Console and into support replies and those copies cannot be corrected later.
- The retention line says what is true: nothing personal is kept, and server logs may hold the
  deleted account's **numeric id** — exactly what `DeleteMe` and `handleDeletion` log. **If logging
  ever records more, that sentence moves with it**, or the page becomes a false statement in a policy
  document.

---

## `/admin`

Served publicly as HTML — everything privileged is behind the API, and hiding the page would only be
obscurity.

**Authentication is the app's own code flow, reused.** The page POSTs `/api/auth/request-code`, takes
the six digits back through `/api/auth/verify`, then calls `GET /api/me` to check the role. It
registers an unknown number as `customer`, because the api maps anything that is not `shop_owner` to
that and nothing typed on this page can grant anything. **No new
credential exists** — no admin password, nothing to leak — and `admin` still cannot be requested over
the network. The role is granted with SQL:

```sql
UPDATE users SET role = 'admin' WHERE phone = '998...';       -- grant
UPDATE users SET role = 'shop_owner' WHERE phone = '998...';  -- revoke
```

**`RequireAdmin` is the whole security model, and it is one comparison.** It composes *inside*
`auth.RequireAuth` — that one proves who the caller is and puts their id on the context, this one asks
the database what role that id holds **now**. Reading the role from the token was never an option:
`jwt.go` carries no role claim, because a token lives four months and a demoted admin would otherwise
keep administering until it expired. `TestARevokedAdminLosesAccessOnTheNextRequest` pins it.

The routes are built through one `adminRoute` helper in `main.go` rather than typed per route — not
tidiness: a route registered without `RequireAdmin` still compiles, still returns JSON, and hands the
whole user list to any logged-in customer. `TestOnlyAnAdminReachesTheAdminAPI` checks a customer *and*
a shop owner are refused, because both hold perfectly valid tokens.

**The panel grants the role too, as of 2026-08-22 — the SQL above is now a fallback rather than the
only way.** `PUT /api/admin/users/{id}` accepts `role: "admin"`, and an administrator can edit and
delete another one. See «Full power over users» below for what was reversed and what it costs.

**The raw price index is shown here and nowhere else.** Root §5 is emphatic that `price_index` must
not reach the app; an administrator is the reader who has been taught to read it. **This is not a
licence to add it to `ShopResponse`.**

---

## What the panel does

| tab | holds |
| --- | --- |
| **Главная** | three KPIs beside the «Категории магазинов» ring, then «Регистрации за 30 дней» beside the «Заполнение каталогов» gauge, then «Кто дешевле» beside «Средний чек». Three rows, and nothing below the fold |
| **Аномалии** | prices that disagree with the market for the same basket line |
| **Пользователи** | edit name and role, delete |
| **Магазины** | edit the four editable fields, grant/revoke VIP, open the catalogue, delete |
| **Шаблоны** | the «Файлы без товара» strip, then what each template holds, how far shops have drifted, and one button to push it to all of them. The three paragraphs explaining what an edit reaches are behind the «i» in its toolbar (`templateHelp`), not printed above the tables |

### The page header — `.topbar`

**One row across the top of the work area on every section**: the section's name on the left, the
page's single search field, and `#refresh` and sign-out on the right. Added 2026-08-22, and it is
worth knowing what it is *not*, because a version of it was deleted before.

**What was deleted was a title plus a sentence** — the open section's name and its `sub` string,
printed one line under the sidebar entry already lit orange, the same fact twice at the top of every
screen for about 80px. **That does not come back**: there is no sub-line here, the `sub` strings stay
on each nav button's `title`, and `aria-current` remains what answers "where am I". What earns the
row its height is the two controls it carries. They lived in the sidebar's foot, the corner of the
screen nobody looks at, and «Обновить» is a button whose whole value is being reachable at the moment
the numbers look stale. `.side-foot` is gone.

**The search moved up here and there is exactly one of it.** A header field that mirrored whichever
list was open stood above a second, identical one inside the section. The sections do not carry
their own, so the field under the title is the only search on the page. `SEARCH` maps a section to
its `state.q` key and its render function, `setView` shows or hides the field and restores the value
from state, and Главная and Шаблоны hide it outright because they have no list to filter. **A search
spanning every section is still a different feature** and would need results of its own.

`.topbar .search:not([hidden]) + .top-acts{margin-left:0}` is load-bearing: a hidden element is still
a sibling, so a bare `+` would pull the two buttons back to the title's shoulder on Главная.

### Four rules inside it

**The anomaly report's baseline is the MEDIAN, and that is not a contradiction of root §5.** The index
is the arithmetic mean and stays that way; §5 says outliers are handled operationally, by an admin
reviewing suspicious prices — **this is that review.** The two use different statistics because they
answer different questions: the index asks "what does this market cost", where every real price should
count; the report asks "is this one price wrong", where the whole point is to be unmoved by the outlier
being hunted. **Changing the index to the median because of this line would be the bug §5 warns about.**
Comparison is per (shop category, `template_key`) and a line needs at least three priced shops before
its median means anything; both numbers are query parameters, because the right ones are unknown until
there is real data.

**The report reads as a phone call, not as a fact** (2026-08-22). Three things changed together after
the founder read it and could not tell whose price was in which column:

- **The columns are named for their owners** — «Цена магазина» and «Обычная цена», both right-aligned
  so the two numbers the row exists to compare line up on their last digit, with the median's sample
  size («по 7 магазинам») under it rather than in a column of its own. Each header carries the long
  explanation on its `title`.
- **One sentence stands above the table** (`.lede`, `#anom-sum`), plus what is in the report right
  now, counted from the rows on screen so it agrees with the table while a search is open. The full
  five paragraphs — including *why* the baseline is a median and the index is a mean — are behind the
  «i» in the toolbar (`anomalyHelp`), the way the templates section keeps its rules. This is the one
  section with a standing sentence; everywhere else the column heading is the whole story.
- **The number to ring is in the row.** `AdminPriceAnomalies` joins `users` and carries
  `contact_phone`, `owner_name` and `owner_phone`; the panel renders the shop's line as a `tel:` link
  and prints the owner's number only when it differs, since two identical lines would say the shop has
  two numbers. A report that makes the founder open Магазины and search for the shop is one that gets
  read and not acted on.

**An admin editing a product goes through the same three-way rule the owner does**, not a bypass —
`UpdateProductPricing` has no `SET` for name at all, so a template row cannot be renamed from here
either. The rule is data integrity rather than permissions: a renamed template row stops being the same
product as its counterpart down the road. What an admin actually needs is the price, editable on every
row. **Shop category is not editable from here or anywhere** — the panel reuses `UpdateShop`, which
keeps that true by construction.

### Full power over users — and what it cost

**`admin` is assignable over the API.** The old
rule refused three things: granting the role, editing an administrator's row, and deleting one. The
argument was good and is worth keeping written down, because it is the thing that was traded away:
the property worth having is not "an attacker cannot reach it" but **"there is no code path at all"**,
which survives a stolen token, an XSS bug in the panel and a mistake in the middleware wiring.

The founder asked for the power over his own product, which is his call. **The cost, stated plainly:
an admin token is now enough to mint another administrator, so a stolen one is a permanent compromise
rather than one that ends when the token expires.**

- **Nothing unauthenticated may still assign it, and that is the half that must not move.**
  the login maps anything that is not `shop_owner` to `customer`, and only ever
  upgrades `customer → shop_owner`. That was the original hole and it stays closed.
  `TestSignupStillCannotAskForAdmin` is the check that notices if `assignableRoles` ever grows a
  fourth entry.
- **The one refusal left is arithmetic rather than policy**: the last administrator cannot be demoted
  or deleted. Zero administrators is the only state no screen can undo — signing into this panel
  requires one — so from there the way back is SQL on production. `anotherAdminRemains` in `admin.go`
  is the whole of it, and it answers **409, not 403**, because the panel signs itself out on a 403
  (that is what a revoked admin looks like) and this is a request that was understood and allowed and
  is simply impossible right now.
- **The count and the write are two statements, not a transaction.** Two administrators demoting each
  other in the same second could both pass; at one machine and one person that is not a race worth a
  lock, and the honest fix if it ever matters is a constraint in the database.
- Panel-side: both row buttons are enabled on an administrator's row (not disabled with a
  tooltip), the role select carries a third option with a note saying what it grants, and the confirm
  dialog names the role when the account being deleted holds it. The `last_admin` refusal arrives as a
  toast rather than a disabled button, because whether it applies depends on how many admins exist,
  which a row does not know.
- Pinned by `TestAnAdminCanGrantAndRevokeTheRole`, `TestTheLastAdministratorCannotBeRemoved`,
  `TestAnAdminCanBeDeletedOnceAnotherExists` and
  `TestAnAdminCannotDeleteThemselvesWhenTheyAreTheOnlyOne`.

### VIP placements

`PUT /api/admin/shops/{id}/vip` takes **days, not a date** — the realistic input is "sold them a
month", and an absolute date makes extending a live placement ambiguous about from when. `days: 0`
revokes through the same statement, since a grant and a revoke are one fact with different values.
Capped at 730 days so a slipped keypress cannot sell a placement into the next century. SQL fallback:

```sql
UPDATE shops SET vip_until = '2026-09-03T00:00:00Z' WHERE id = 1;  -- grant
UPDATE shops SET vip_until = NULL WHERE id = 1;                    -- revoke
```

### The panel refreshes itself — `liveTick`

`«Обновить»` is a button nobody presses at the moment it would matter, so one `setInterval` (5s tick)
drives everything: the dashboard counts every 45s **everywhere**, whatever a modal registered every 8s
**while its section is open**, and an open conversation every 8s. `liveNow()` forces a round when a
section is opened or the tab comes back into view.

- **Nothing runs while `document.hidden`.** A panel left open on a second monitor costs nothing; a
  `visibilitychange` listener catches up the moment it is looked at again.
- **`live.busy` skips a round rather than queueing it**, so a slow database stretches the interval
  instead of stacking identical requests on it.
- **A re-render restores the `.scroll` container's `scrollTop`**, or a table would jump to the
  top every twelve seconds while it was being read. The chat modal does the same, but only follows the
  bottom when the reader is already near it.
- **The modal hands its `pull()` to `live.thread` and takes it back through `shell({onClose})`**, which
  is why that hook exists on the shared shell: ×, Escape and the scrim all route through `shut`, and a
  caller wiring three listeners of its own would eventually wire two. A modal that kept polling after
  it closed would be an invisible request every eight seconds for the rest of the session.
- **`drawn` is not the same question as "is the list empty".** Without it, a conversation with no
  messages matches "nothing changed" on the very first pull and never leaves «Загрузка переписки…».

**SSE was the obvious fit and cannot be used here: `EventSource` sends no headers**, and every request
on this page authenticates with a bearer token from `localStorage`. It would mean an admin token in a
query string — server logs, browser history — or a short-lived ticket endpoint. Root §7 has the rest.

---

## What the dashboard reports, and why those things

An admin panel that counts rows tells you how much of the product exists. These tell you what to *do*.
**The layout was rebuilt on 2026-08-22** around a reference dashboard the founder chose, and trimmed
twice in the same day. It is **three rows and nothing below the fold**: three counts with a ring
beside them, one analytic band, and the leaders. Everything that was a table permanently on the front
page either moved behind a number or left.

### Row 1 — three counts and the shape of the market

- **«Магазины» is the count and nothing else.** Not «16 в сравнении цен» underneath:
  the gauge one row down is about that ratio, and a tile that also states it makes the reader compare
  two renderings of the same thing.
- **«Пользователи»**, with `покупатели N · владельцы M` underneath — the split says how much of the
  number is demand and how much is supply. Named «Пользователи», matching the sidebar: a tile calling
  the same set something else is a second name for one thing. The `.k-sub` line sits under the whole
  `.k-bot` row rather than beside the delta, which is
  what stops it truncating to «32 влад…».
- **«VIP-места» is a fraction, `2 / 5`, because VIP is inventory.** The denominator is
  `shops.vip_slots`, sent by the server from `home.go`'s `vipShopsLimit` — the carousel draws that
  many places whether or not they are sold (root §7), and a panel with its own copy would keep
  saying «из 5» the day it grows to six. **Do not hardcode it here.**
- **«Категории магазинов»** — the reference's «Top Categories», and the same question: what is this
  market made of. The ring plus its list is one object, which is why `buildDonut` carries no legend of
  its own. It is `b3 r2`, standing beside the KPI row *and* the chart under it — the only piece of
  real structure in the layout. `в сравнении` per category rides on each row's `title`.

### Row 2 — the two things that move day to day, and they are one row

Both cards carry `tall`, which is `align-self:stretch` plus a flex column: `align-items:start` is
right for the rest of the grid and wrong for these two, because they are one row of one subject and a
card ending 160px short of its neighbour reads as one that failed to load. The gauge's arc and
sentence sit in a `.grow` that takes the slack, so the two boxes stay pinned to the bottom edge
rather than leaving fill under them.

- **«Регистрации за 30 дней»** (`b6`) — `generate_series` in `AdminSignupsByDay` is what produces the
  empty days; `GROUP BY created_at::date` returns only days that have rows, and the gap is the
  information. The axis draws `min(top, 4)` gridlines, because quarters of 1 rounded for the label
  printed «1 1 1 0 0» up the side of an empty install.
- **«Заполнение каталогов»** (`b3`) — the completion gauge, **and it is a return of something deleted
  on 2026-08-21** for drawing `ranked / total` a third time. It is now the only place that draws it.
  **Two states, never more**: a catalogue is finished and the shop is in the comparison, or it is not,
  because 1% and 99% publish the same nothing. `AdminCatalogueFunnel` still returns `empty` and
  `started` separately; the panel sums them.
  - **No caption under the title.** «Магазин попадает в сравнение, только когда заполнен целиком» is
    the rule the whole card is about, and printing it on every load is explaining the same thing to
    the same person forever.
  - **One sentence, and it does not change subject with the answer.** Not congratulating a
    finished market and report the shortfall the rest of the time; it is `16 из 37 магазинов в
    сравнении цен` at every value. **No plural agreement anywhere in it** — «21 магазин», «22
    магазина» and «25 магазинов» are three endings, so the count sits after a preposition where
    russian does not decline it.
  - **The two boxes are one tinted block split by a hairline**, not two bordered cards: they are one
    measurement cut in two. `grid-template-columns:repeat(2,minmax(0,1fr))` written the long way is
    load-bearing — a `1fr` track is `minmax(auto,1fr)`, and `auto` is the child's min-content width,
    which a nowrap label pushes past its share and visibly outside the card's own edge.
  - **«Не заполнены» is a button** and the only way into the list of who has not finished. **It is
    disabled at zero**, and that is worth knowing before it is reported as broken: on a market where
    every catalogue is finished — which is the state a founder's own test database is usually in —
    the number reads `0`, the underline disappears and it does not open. There is nothing to list.
    It keeps its colour rather than fading, because it is still half a measurement.
  - The «Каталог за неделю пополняли» footer went with `AdminPricingActivity`, which nothing reads
    any more.

### Row 3 — «Кто дешевле» and «Средний чек»

**The only two panels here that report what the product *says* rather than how much of it exists.**
Everything else counts rows; these are the screen a customer sees.

#### «Кто дешевле» (`b8`, `buildRace`)

Up to five shops of one market, cheapest first, from `AdminMarketRankings` (`adminRankingDepth = 5`).
It replaced a card that printed only the winner, which could not answer the question the founder
actually has — **is anybody competing?** Three shops at 4.61, 4.63 and 4.65 million are fighting;
4.6, 5.4 and 6.2 is one shop with nothing pressing on it, and a single leader row makes those two
markets look identical.

- **`CROSS JOIN LATERAL`, not `ROW_NUMBER()`** — sqlc cannot compile a window function filtered from
  an outer `WHERE` (root §6), and "for each category, the first N of this ordered list" is what
  lateral is for. **The rank is not on the wire**: it is the row's position in the result, and a
  stored rank could disagree with the order it came in.
- **The bar measures the distance from that market's average, not the basket.** Drawn from zero, five
  baskets between 4.6 and 5.6 million are five bars within 20% of each other's length — a picture
  saying "these all cost about the same", which is the opposite of the finding — and starting the
  axis at a flattering floor is the usual lie. So the axis *is* the average: cheaper grows left,
  dearer grows right, length is `|индекс − 100|` against the widest gap on screen with a floor of 4
  points, and the centre tick repeated down every row is what makes five bars read as one line.
  Dearer bars are pale, not red: somebody has to be the expensive one, and the chip carries the sign.
- **One market at a time, chosen by tabs on their own row.** Four rankings side by side would be four
  charts on four different scales — an Обои basket is ten lines and a Универсальный one is a hundred —
  and the eye compares whatever is adjacent whether or not the comparison means anything (root §5).
  The tabs are below the header because four category names is ~560px of pills, which wraps inside a
  `b8` header and takes the title with it. `state.raceCat` survives the 45-second poll and falls back
  to the busiest market when the one it names empties.
- A row opens that shop's catalogue.

#### «Средний чек» (`b4`, `buildTrend`)

One row per market: what a basket costs there now (`AdminCategoryBaskets`) and a sparkline of the last
thirty days beside it (`AdminBasketHistory`). Two halves of one subject — the figure says what the
category is worth, the line says whether that is moving, and neither carries the other.

- **Not four lines on one chart.** Four oranges crossing each other is a picture nobody reads, and the
  four numbers are not on the same scale anyway.
- **Dearer is red here and cheaper is green, which is inverted from everywhere else on this panel.**
  The thing being measured is what a customer pays, so a market getting more expensive is the bad
  direction — the same convention the price badge uses.
- The sparkline has no axes, labels or tooltip: at 78×26 the only thing it can say is which way the
  line went, which is what it is being asked. A flat series draws down the middle rather than dividing
  by zero.
- **Fewer than two days of history prints «с сегодня» instead of a line**, because the table starts
  empty on any database that has not been running — see below. It is not a failure state and does not
  get an error colour.

#### The history is written down, because it cannot be recomputed

`shop_basket_index` is recomputed from `products.price` on every write that can move it (migration
`000006`): it always answers about *now*, and yesterday's basket is gone the moment an owner retypes
a number. `basket_history` (migration `000003`) is one row
per `(day, category)`, upserted by **`startBasketHistory`, the third goroutine in `main.go`**.

- **Hourly, not nightly.** A daily ticker fires at whatever moment the process happened to start, so
  a server restarted around then skips whole days and a laptop that is only on in the afternoon
  records nothing. The statement is an idempotent upsert keyed by `(day, category)`, so twenty-four
  runs write what the last of them would have written alone — and today's point stays current to
  within the hour instead of being yesterday's until midnight.
- **The whole aggregate runs in the database** (`RecordBasketHistory`) — one statement over a view,
  nothing travelling through Go — which is what makes it cheap enough to put on a timer.
- A failure is logged and the loop continues; it does not join the shutdown path, because there is no
  state to flush and losing an in-flight upsert costs an hour of a number rewritten every hour.
- **A day with no row is a day the server was not running**, and the sparkline joins across the gap
  rather than inventing a point. `AdminBasketHistory` deliberately has no `generate_series`, unlike
  `AdminSignupsByDay`, where the empty days *are* the information.
- Pinned by `TestTodaysBasketIsRecordedAndComesBackOnTheDashboard` (which runs the job's statement
  twice and asserts one row) and `TestTheMarketRankingIsPerCategoryAndCheapestFirst`.

### Behind a number instead of on the page

- **«Не заполнили каталог»** (`openUnfinished`) — the «Кому позвонить» card, turned into a window. It
  was `b8` on the front page, eight rows of a table permanently answering a question the founder asks
  about once a week, hanging off a number («Не заполнены») that was already on screen two cards up.
  Behind that number it costs nothing until it is wanted and can carry **every** unfinished shop
  instead of the top eight: shop and category, the date it was created, how many rows are still
  unpriced out of how many, and a `tel:` link. A row opens that shop's catalogue.
  It reads `state.stats.attention`, which the dashboard request already carries — capped at
  `adminAttentionLimit` (100), a ceiling rather than a page. **No second endpoint.**
- **«Файлы без товара»** moved to Шаблоны, below.

### Removed, and not to be re-added

«Цены по рынкам» (per-category coverage, median basket and spread) — the founder's call, and the
queries behind it went with it rather than being left dead: **`AdminPricingActivity` is deleted**,
along with `funnel.stalled` and `activity.*` on the wire. `AdminBasketByCategory` went the same way
and came back a day later as `AdminCategoryBaskets` for «Средний чек» — the same aggregate for a
reader that exists this time, which is the whole test a query has to pass here. Before this: the product-category bar chart (a picture of the catalogue, not a fact about the
business), the anomaly teaser (a worse version of a screen one click away), the identity block in the
top bar, and the page title's sentence.

**The editing rule stands: every panel answers a question no other panel answers.** `ranked / total`
was once drawn four times over — a KPI, a gauge, two boxes under it, and a funnel's terminal bar — and
four renderings of one ratio read as four findings. One card draws it now, and the KPI beside it
stopped repeating it.

**`.dash` is `align-items:start`, not the grid default** — an unfinished card's empty `--card` fill
reads as a broken panel where the same space left as page reads as the page. The two exceptions are
deliberate and both are rows of one subject: `.kpi{align-self:stretch}` and `.card.tall`.

---

## The orphan sweep — «Файлы без товара»

`GET /api/admin/storage/orphans` counts and measures; `DELETE` does it. Both are `RouteOrphans` at the
bottom of `admin.go`, and both re-derive the list from scratch.

**Why there is anything to sweep:** deleting a shop is one statement and the schema cascades, so its
products go and their uploaded photos stay — they are not in Postgres and nothing in that transaction
could reach them. Replacing and removing a photo both unlink correctly; a deleted shop and a crash
between "write the file" and "point the row at it" are what feed this.

**Three rules, and every one of them deletes a live photo if it is reversed:**

1. **List the files first, read the database second.** In that order a row committed between the two
   reads is *seen*, so its file is protected. Reversed, a row written after the query whose file was
   already on disk looks unreferenced — and the sweep deletes a photo a product is pointing at.
2. **Nothing younger than an hour.** The real window between "the file exists" and "the row exists" is
   one upload request, bounded by `dbctx`'s 5-second deadline. An hour is several orders of magnitude of
   headroom and costs nothing, since these files have been dead since a shop was deleted. The card says
   how many were held back, or "12 files, 0 deleted" reads as a broken button.
3. **A referenced master claims its `_thumb`.** Only the master's path is stored (root §7), so a sweep
   matching paths literally would find every thumbnail unreferenced and **blank every grid in the market
   on its first run**, with the database perfectly consistent throughout.

Plus the property that is not a rule: **nothing outside `uploads/` is listed or deletable**.
`imagestore.Storage.List` walks only that prefix and `RemoveFile` refuses anything else, so the curated
catalogue — one file per row shared by every shop of a category — is not reachable from here even by a
bug in this file. `TestASweepCannotReachTheCuratedCatalogue` pins it;
`TestASweepKeepsThumbnailsAndAnythingWrittenRecently` pins rules 2 and 3.

Panel-side, four things:

- **It lives under Шаблоны, above the template tables** (`drawStorage`, `#tpl-storage`), moved off the
  dashboard on 2026-08-22. It is maintenance rather than a fact about the business, and it was the
  only card on the front page that could not tell the founder anything until he pressed something.
  **It is one strip and no card around it** — a `card()` would put a title and a caption above it and
  repeat in two lines what the strip says in two — with the glyph carrying which of three states it is
  in (`.stor.idle` / `.stor.ok` / `.stor.hit`). Deliberately small, because every pixel it takes is
  one the section's real content loses. The proportion bar it had for half a day went with the move.
- **It does not load itself.** Every other panel rides on a timer, and this one would mean walking the
  whole store and reading every image path every 45 seconds — on R2, a paged listing over the network.
  «Проверить» is a button and the result sits in `state.storage`.
- **The result is rendered from state, never written into the DOM by the click handler.** `state.storage`
  survives until the page is reloaded, and `drawStorage()` repaints from it — which is what lets
  opening Шаблоны again show the last scan rather than an empty strip.
- **After a sweep the card re-scans rather than rendering the DELETE's own answer.** That response's
  `files` is how many were removed, not how many are left — and after a capped sweep (`orphanSweepLimit`,
  2000, so one press cannot be an hour of network round trips) there genuinely are more.

The confirm dialog names what is *not* touched as well as what is, because the fear it has to answer is
"will this delete a live photo". **The DELETE takes no list of paths** — a client-supplied list would be
a request naming files to delete, behind one middleware check, operating on a scan minutes old.

## The template sync

**`POST /api/admin/templates/{category}/sync` is the button that replaces "delete the shop and make it
again"** — seeding happens once, at creation, so a template edited afterwards reaches nobody. Three
statements in one transaction:

```
insert  rows the template has and the shop does not, unpriced
update  names/units/categories/photos for rows both have — prices untouched
delete  rows the shop has and the template no longer does
```

- **The transaction is not decoration.** A shop with the new rows inserted but the stale ones not yet
  deleted holds two versions of its own basket, and `shop_basket_index` would count both — publishing a
  total for goods it does not sell, under a badge claiming that is what it costs.
- **`price` and `availability` are absent from the update's `SET` list, and that is why it is safe to
  run.** They are the owner's work; a sync that reset them would destroy hundreds of hand-typed numbers
  silently, because the rows would still be there.
  `TestSyncRestoresMissingRowsAndKeepsEveryPrice` is the test that matters.
- **Names are not synced for обои** — a slot's name is the owner's real wallpaper, so syncing would
  replace every обои catalogue with ten copies of «Обои премиум (Россия)». The flag comes from
  `catalog.IsOwnerNamedCategory`, derived from the same declaration `IsOwnerNamedSlot` uses, so a
  second slot-based category is covered automatically.
- **Two consequences the confirm dialog says out loud:** adding a product to a template drops **every
  shop of that category out of the price comparison** until its owner prices the new row, and deleting
  one takes whatever price the owner had typed.
- The template travels as **one jsonb array** expanded with `jsonb_to_recordset`, not five parallel
  `text[]`s that could get out of step. Multi-argument `unnest` is valid postgres and was verified
  against the real database, but sqlc's parser does not know the 5-argument signature.

## Editing the templates themselves

They moved out of Go into `product_templates`. The two-step shape is the design:
**editing a template decides what the *next* shop is created with** — add, rename, change a unit,
delete, none of it touches an existing shop — and **«Применить ко всем» is the second, louder step**.
Merging them would make a typo in a name an event that touches thousands of rows.

**`template_key` cannot be edited, and the statement enforces it**: `AdminUpdateTemplateItem` has no
`SET` for that column. Changing a key would not rename anything — it would orphan every shop already
seeded with the old one, and the next sync would delete those rows and insert fresh unpriced ones,
**losing every price silently**, because the row count would look unchanged. The panel shows the field
locked with that explanation rather than just disabling it.

**Every write reloads `internal/catalog` before responding.** The whole API reads templates out of
memory, so a write that skipped the reload would leave the process seeding from the old list until it
restarted — the founder would edit a template, press sync, and watch nothing happen.

---

## The visual language is deliberately not the app's

The phone app is cool grey on white with soft shadows. This panel is a warm neutral ramp, flat — **no
shadows on content at all**, separation comes from fill — with a shell floating on beige, a sidebar
whose active item is an orange pill, and charts along a graduated orange ramp. Same brand orange
(`#FF6F00`), different surface.

### The ramp runs beige → `--surface` → `--shell` → `--card`, and the direction is the point

It ran the other way until 2026-08-21: `main` was `--surface` and every dashboard card was
`.card.plain`, white with a `--line` hairline. **Two fills two units apart is not separation by fill**,
which is the principle the panel claims, so the cards read as nothing at all — reported, correctly, as
«карточки просто белые на почти белом».

Now: `aside` is `--surface`, `main` is `--shell`, cards and `.kpi` are `--card` with a `--line-2`
hairline. **`.card.plain` is gone rather than left as a class that no longer changes anything**, and so
are its six call sites. Three consequences worth knowing before editing:

- **`.tbl` stays white with a `--line-2` border.** Standing on `main` it is a white object with a
  visible edge; inside a card it is a lighter block inset into a darker one, which is the same idiom
  the reference dashboards use. `thead` at `--card` gives it its header band either way.
- **`--card` is used in fifteen other places** — nav pips, `thead`, `.tag.g`, `.empty .bx`, the chat
  background, several `:hover`s. Anything that sits *inside* a card and used `--card` to differ from
  white now needs checking. `.btn-g` was the one that broke: grey-on-grey on the storage card, a button
  you had to look for, so it is `--shell` with a `--card` hover.
- **`C.line2` exists in the JS colour mirror for the chart grid**, because `--line` on `--card` is a
  gridline nobody can see. Svg attributes cannot read a custom property, which is why that mirror
  exists at all.

**The principle did not change, only which end of the ramp the content sits at: still no shadows on
content.** Modals, tooltips and the map's own controls are the only things that lift, and adding a
shadow to a card would be a change of language, not a polish pass.

### The section highlight is one object that moves

`nav` is `position:relative` and holds an absolutely positioned `.nav-pill` that `moveNavPill()` sizes
and moves by `transform` from the active button's `offsetLeft/offsetTop/offsetWidth/offsetHeight`.
Before, the highlight was `background` on whichever button carried `[aria-current]` — one fill dying and
another being born, two events in two places, which reads as a flicker rather than as a change of place.
The model is `BestOffersList` in the phone app: a pill sliding along a track, **drawn under the labels**.

- **`z-index` on both is load-bearing.** An absolutely positioned element paints above its in-flow
  siblings, so without `z-index:0` on the pill and `z-index:1` on the buttons the orange fill lands on
  top of the label it is supposed to sit behind.
- **The active button paints no background of its own, and its `:hover` is killed too** — a fill on top
  of the pill covers the thing that just slid underneath.
- **Measured, never derived.** The sidebar is a column on a laptop and a scrolling row under 900px where
  the labels are hidden and the widths change, so the same four numbers answer both layouts. The
  debounced `resize` listener calls `moveNavPill(true)`.
- **`.cold` suppresses the transition for a placement that is not a movement** — the first paint and a
  resize. Reading `offsetWidth` between removing and re-adding the class is what forces the layout that
  makes the suppression real; without it the two class changes collapse into one style recalculation.
  Verified per-frame in headless chrome: 13 distinct positions on a section change, exactly one on load.

### The black borders on the nav buttons

Reported as "the section buttons grow black borders after a while", and it was **Chrome's own focus
ring**: `outline: auto 1px rgb(16,16,16)`. Nothing in the file had ever styled a focus ring, so the user
agent's took over — and it appears on whatever still holds focus the moment the browser decides the user
is on the keyboard. One arrow key to scroll a table, or the window being clicked away from and back, and
the nav button clicked minutes ago lights up. Nothing the reader did was aimed at that button, so it
reads as a rendering fault.

The fix is a **replacement, never `outline:none`** — that deletes the ring for the one person it exists
for. Zero-specificity `:where(button,a[href],[tabindex]):focus-visible` gets `2px solid var(--o-600)` at
a 3px offset, and `:where(input,select,textarea):focus-visible` opts out because those already carry a
ring of their own (`border-color` + `box-shadow`). A mouse click still shows nothing: `:focus-visible`
does not match on a pointer.

> Reproducing this needs `Emulation.setFocusEmulationEnabled` **and** a keyboard event after the click —
> the click alone gives `:focus` without `:focus-visible`, which is the state that looks fine.

Before editing it:

- **Everything user-supplied reaches the page through `textContent`, never `innerHTML`.** The admin's
  JWT is in `localStorage`, so a shop named `<img src=x onerror=…>` rendered as HTML would hand away
  administrator access to the whole database. Building nodes is the version of this the next person
  adding a column cannot get wrong. **Owner-written shop and product names are the highest-risk field
  database** — a stranger writes them and an admin reads them.
- **The charts are hand-rolled SVG, measured in real pixels** rather than drawn in a scaled `viewBox` —
  a viewBox that scales also scales the text, so the same chart gets 9px labels on a laptop and 14px on
  a monitor. Hence the debounced `resize` listener, and no charting library.
- **The signups line is a Catmull-Rom curve at tension 0.18**, low on purpose: higher overshoots below
  zero on a spike and draws a negative day.
- **The donut carries no legend of its own** — it always sits beside the markets table, whose first
  column names each category against a swatch from the same `shade(i, n)`.
- **A button has to move when it is pressed.** `#refresh` was reported as dead while working: against a
  local database every request finishes inside a frame, so the spinner flickered and the numbers —
  usually the same numbers — did not visibly change. Three fixes, all needed:
  `.ib:active{transform:scale(.88)}`, a 420ms floor on the spinner, and a toast, because an answer
  identical to the last one still has to look like an answer. The first load passes `{silent:true}`.
- **`generate_series` in `AdminSignupsByDay` is what produces the empty days** — `GROUP BY
  created_at::date` returns only days that have rows, and a chart drawn from that compresses a quiet
  week into one step. The gap is the information.
- **The lists are capped at 500 and filtered/sorted in the browser.** An admin screen must not be the
  one endpoint that can pull the whole database into memory; `offset` is already wired through, so the
  day 500 stops being enough the panel grows a pager rather than the API changing.
- **Deleting a user prunes the shops list held in memory**, because the schema's cascade takes their
  shops and the two tabs would otherwise disagree until a reload.
- **Not built, deliberately:** editing anything beyond the fields listed above, and any audit log beyond
  `log.Printf("ADMIN %d deleted user %d …")` — ids and a role, never a name, a phone number, or the text
  of a shop's own name.

### The map picker

**The shop editor picks a location on a map, and the map is hand-rolled** — about 120 lines of
web-mercator arithmetic, a grid of 256px `<img>` tiles positioned by `transform`, drag to pan, wheel or
± to zoom, click to drop the pin.

- **The alternative was Leaflet from a CDN, rejected for the reason every string here goes through
  `textContent`**: a `<script src="//cdn…">` hands whoever controls that host the ability to read the
  JWT in `localStorage`. Raster tiles are `<img>` elements and an image cannot reach `localStorage`, so
  the pictures come from OpenStreetMap and the code does not. It also keeps the deploy story intact.
- **The coordinates stay the authoritative input and stay visible**, wired both ways: clicking the map
  writes the number fields, editing a number recentres the map. The API validates lat/lng and
  `ST_MakePoint` stores exactly those two numbers, so a picker that hid them would make a wrong point
  unfixable by hand.
- **A drag is not a click** — classified on pointerup by whether it moved more than 4px, or every pan
  would drop the pin wherever the finger came up.
- **Search is Nominatim, on submit only** — free and keyless, but its policy asks for at most a request
  a second. Biased with `countrycodes=uz`, because unbiased «Чиланзар» lands wherever the planet has the
  better-known match. A failure toasts and leaves the map alone.
- **The first draw has to wait for layout.** The picker is built before its form is attached, so the
  frame is 0×0 on the first pass and centring against that width drops the point in the top-left corner.
  `draw()` reschedules on rAF with a 120-frame bail-out, so a modal closed before layout does not leave
  it rescheduling forever.
- **The modal's action row is `position: sticky`** — the map makes this the one form tall enough to
  scroll, and a Save button that scrolls off the bottom is one people cannot find.

**Unseen:** a real browser. Every screen was rendered headless and read back — driven over the devtools
protocol with a signed token, at 1440px and at 880px, against the live database and against stubbed
`/api/admin/stats` payloads for the empty market and a half-filled one — plus search, sort, the
badge lighting and clearing on read, the templates help modal, the pill's per-frame motion and the focus
ring. The two 2026-08-22 rebuilds were checked the cheaper way: a copy of `admin.html` with a `<script>`
injected before `</head>` that stubs `fetch` and `localStorage`, opened as a `file://` URL under
`chromium --headless --screenshot` and driven by a `?view=` parameter that clicks the nav button. That
covers layout at both widths, the empty market, the chat modal and the anomaly table — it does **not**
cover the live loop, the real endpoints or `:focus-visible`. Nobody has logged in with a code on
this page, the one path a screenshot cannot stand in for.

> **Headless never applies `:focus` unless `Emulation.setFocusEmulationEnabled` is on.** Checking a
> focus ring without it shows the resting border and looks like the css is wrong.
