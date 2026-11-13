---
name: admin-panel
description: >
  The html the Go API serves itself — the `/admin` panel (dashboard, the «Накладные» inbox, anomaly report, users,
  shops, VIP placements, template editing and sync, the storage sweeps, the «Система» health screen) and the public site
  (`/`, `/privacy`, `/terms`, `/delete-account`). Use when working in
  `backend/internal/webui/`, `backend/internal/endpoints/admin.go`,
  `backend/db/queries/admin.sql`, `backend/internal/sysstat/`, the `RequireAdmin` middleware, admin roles, or the panel's
  HTML/CSS/JS. Layout and chart rationale: `reference-dashboard.md`; colours, theming and the
  hand-rolled widgets: `reference-ui.md`.
---

# The web pages: the public site and the admin panel

**Both are `go:embed`-ed into the binary** (`internal/webui/`), unlike product photos, which are read
off disk. These pages are *program* — small, changing only when the API they call changes — so
embedding means a deploy is one file and a page can never 404 because a directory was not copied. The
cost is that editing html needs a rebuild.

**Nothing here goes through `WithJSON`** — it sets `Content-Type: application/json`, so a page routed
through it downloads instead of rendering.

---

## The public site — `internal/webui/site/`

Four pages in one shell: `/` (home), `/privacy`, `/terms`, `/delete-account`, with «Связаться» as a
`mailto:`.

- **`layout.html` is written once** — header, nav, the language switch, footer, shared css — and each
  page fills `content` (plus `style`/`script` if it needs them). Rendered **once at startup** by
  `webui.NewSite`, so a broken template stops the boot rather than 500-ing its first reader. The admin
  panel is not in the shell; `webui.Page` serves that file as it is.
- **All three languages are in the markup** and css shows one off `<html lang>`, so every page is
  complete with javascript off. A script in `<head>` picks the language before the body is drawn:
  `?lang=` → the reader's earlier click (`localStorage`) → the browser → ru. Only a click is stored.
- **The documents' contents list is built from their own `h2`s**, so it cannot disagree with the
  headings; without javascript it is simply not there.
- **The policy text lives twice**: `site/privacy.html` (ru/uz/en) and the app's `privacy_policy.dart`
  (ru/uz). `TestTheAppCarriesThePublishedPolicy` reads the dart source and compares every heading and
  line. The terms exist only on the site.
- **`supportEmail`, `policyVersion` and `termsVersion` are constants in `main.go`, not env**: the app
  prints the same address and date in its own copy, and a deployment that set a different one would
  publish a policy the app does not show.
- Dates are written per language by `humanDate`. `/delete-account` is `noindex`; the documents and the
  home page are indexable.

## `/delete-account`

**A Google Play requirement, not a feature.** An app that creates accounts must publish a deletion page
that works *without installing the app* — the point is that somebody who has already uninstalled can
still be forgotten.

**The page performs the deletion; it does not describe where to ask for one.** It is the app's own
telegram handshake pointed at delete: «Подтвердить в Telegram», the bot's «Подтвердить удаление» button
(which shares the number), gone. Nothing is typed on the page — the contact is the number, and the
account on it is the one deleted (`TelegramAuth.StartDeletion`, `/api/account-deletion/status`).

- **«no account» is said only after the number is proven**, in the bot and on the page, so the page
  cannot be used to ask whether a number is registered: nothing before the contact touches the database.
- **A deletion session is its own purpose** and can never be read back as a login
  (`TestADeletionCannotBeUsedAsALogin`).
- **The «Открыть Telegram» link is an anchor drawn after `/start` answers**, never a `window.open` from
  script: a window opened after a fetch is a popup every browser blocks. The page then polls every two
  seconds, at once on `visibilitychange` (a background tab's timers are slowed while the reader is in
  Telegram), and gives up at `expires_in`.
- Three steps swapped by the `hidden` attribute. **`[hidden]{display:none !important}` in `layout.html`
  is load-bearing** — `hidden` is styled by the *browser's* stylesheet, which any author rule outranks,
  so `.btn{display:flex}` would silently un-hide every button carrying it.
- **Every dynamic string is written in all three languages** (`say`), so switching language after an
  answer has landed does not blank it out. Every poll status has an outcome, and an unrecognised one
  falls through to `failed`. «Начать заново» is hidden on `deleted` alone, since there is no account left.
- The code-based `/api/account-deletion/request-code` and `/confirm` are still routed for the switch
  back to Telegram Gateway (`backend` skill), and the page does not call them.
- **Deleting an account deletes the owner's uploaded photos** (`eraseAccount`): the cascade takes the
  rows, never the files, so the paths are read first and unlinked after. The panel's own delete does the
  same through `removeUploads`. A file that fails to go is left for the orphan sweep, never undoing the
  deletion.
- `/delete-account/` and `/account-deletion` are 301s onto it: the url goes into the Play Console and
  into support replies, and those copies cannot be corrected later.
- The retention line says what is true — nothing personal is kept, and server logs may hold the deleted
  account's **numeric id**, which is exactly what `DeleteMe` and the deletion handlers log. **If logging
  ever records more, that sentence moves with it**, or the page becomes a false statement in a policy
  document.

---

## `/admin` — the security model

**Not on the internet**: nginx refuses `/admin` and `/api/admin/`, and the panel is opened through an SSH
tunnel (below). Everything privileged is still behind `RequireAdmin` — the tunnel is a second lock, not a
replacement for the first.

**Authentication is the app's own telegram handshake, reused.** «Войти через Telegram» POSTs
`/api/auth/init` with no name and `role: customer` (so an existing account is not renamed and nothing
typed here grants anything), draws «Открыть Telegram» as an anchor to the t.me link, polls
`/api/auth/status` every two seconds, then calls `GET /api/me` to check the role. **No new credential
exists** — no admin password, nothing to leak. **It works through the tunnel unchanged**: the link opens
Telegram on the laptop, the poll goes down the tunnel to the server's loopback, and only telegram's
webhook needs the public address.

**`RequireAdmin` is the whole security model, and it is one comparison.** It composes *inside*
`auth.RequireAuth`: that one proves who the caller is, this one asks the database what role that id holds
**now**. Reading the role from the token was never an option — `jwt.go` carries no role claim, because a
token lives four months and a demoted admin would otherwise keep administering until it expired.
`TestARevokedAdminLosesAccessOnTheNextRequest` pins it.

**Routes are built through the one `adminRoute` helper in `main.go`**, not typed per route: a route
registered without `RequireAdmin` still compiles, still returns JSON, and hands the whole user list to any
logged-in customer. `TestOnlyAnAdminReachesTheAdminAPI` checks a customer *and* a shop owner are refused,
because both hold perfectly valid tokens.

**`admin` is assignable over the API** (`PUT /api/admin/users/{id}`), and an administrator can edit and
delete another one. The property that was traded away is worth stating: not "an attacker cannot reach it"
but "there is no code path at all", which survives a stolen token and a mistake in the middleware wiring.
**The cost, plainly: an admin token is enough to mint another administrator, so a stolen one is a
permanent compromise rather than one that ends when the token expires.**

- **Nothing unauthenticated may assign it, and that is the half that must not move.** The login maps
  anything that is not `shop_owner` to `customer` and only ever upgrades `customer → shop_owner`.
  `TestSignupStillCannotAskForAdmin` notices if `assignableRoles` ever grows a fourth entry.
- **The one refusal left is arithmetic rather than policy**: the last administrator cannot be demoted or
  deleted (`anotherAdminRemains`). Zero administrators is the only state no screen can undo, since
  signing in here requires one. It answers **409, not 403**, because the panel signs itself out on a 403
  — that is what a revoked admin looks like — and this is a request that was understood, allowed, and is
  simply impossible right now. The panel shows it as a toast rather than a disabled button, because
  whether it applies depends on how many admins exist, which a row does not know.
- **The count and the write are two statements, not a transaction.** Two administrators demoting each
  other in the same second could both pass; at one machine and one person that is not a race worth a
  lock, and the honest fix is a constraint in the database.
- SQL fallback, for a database with no administrator in it yet:
  ```sql
  UPDATE users SET role = 'admin' WHERE phone = '998...';       -- grant
  UPDATE users SET role = 'shop_owner' WHERE phone = '998...';  -- revoke
  ```

**Decided: the panel is reachable only through an SSH tunnel.** nginx answers `deny all` on `/admin` and
`/api/admin/`, so neither the page nor its api exists as far as the internet is concerned. It is opened
with

```bash
ssh -L 8081:127.0.0.1:8080 ayzrixsiev@<server>   # leave this terminal open
```

then `http://localhost:8081/admin` in a browser on that same laptop. The port is forwarded through the
ssh connection, so the laptop is talking to the server's own loopback. No code change is needed: every call
the panel makes is root-relative (`/api/admin/…`) and `/admin/` redirects with a relative `Location`, so
both follow whatever origin served the page. The token is stored per origin, so `localhost:8081` signs in
on its own. A request through the tunnel carries no `X-Forwarded-For`, so its per-address buckets are
keyed `127.0.0.1` — which nothing else ever is, since nginx always writes the header. **This is what makes a stolen admin token useless from the internet** — `RequireAdmin`
is still the authorization, the tunnel just means an attacker never reaches the door to try.

**The trade-off, taken knowingly: a second administrator needs a login on the production server**, which
is more power than the panel itself — shell, the database, the photos. Acceptable for co-founders, wrong
for anyone else. The alternative considered and rejected for now was an nginx password (`htpasswd`) in
front of those two paths, which grants exactly the panel and nothing more, is revocable per person by
deleting one line, and works from any computer without server access. **Revisit the day somebody who
should not have shell needs the panel** — it is a `location` block and one file, not a design change.

**The raw price index is shown here and nowhere else.** An administrator is the reader who has been
taught to read it; **this is not a licence to add it to `ShopResponse`.**

---

## The sections

| tab | holds |
| --- | --- |
| **Главная** | the dashboard — see `reference-dashboard.md` |
| **Накладные** | the lists anybody signed in sends from Корзина, owners included, tagged by role: open, download the PDF, delete; a category filter |
| **Аномалии** | prices that disagree with the market for the same basket line |
| **Пользователи** | edit name and role, delete; a role filter in the header |
| **Магазины** | edit the four editable fields, grant/revoke VIP and the storefront photo, exclude from the comparison, open the catalogue, delete; a category filter |
| **Шаблоны** | the two storage strips, a banner when a market is behind its template, then per category a grid of product cards |
| **Система** | how close the server is to its limits: whether the pool ran out, cpu over the last hour, memory, disk, load, the pool, search slots, the Yandex budget, the Go heap |

**One search field on the page, belonging to whichever list is open** (`SEARCH` maps a section to its
`state.q` key and its render function; `setView` shows or hides it). Главная and Шаблоны hide it: they
have no list to filter. **A search spanning every section would be a different feature** and needs
results of its own.

**A filter is not a sort.** Each list section carries one `select.fsel` built by `fillFilter` from
`SHOP_CATS`/`ROLES` themselves, so a fifth category reaches the dropdown the day it is declared; it
narrows `state.filter` in the browser alongside the search, and `countLabel` says «Показано: N из M»
whenever either is narrowing. Sorting is the `th.s` click, and the arrow shows at low opacity on hover so
an unsorted header says it can be clicked.

**No badge on a nav button.** Row counts belong in the header of the section they describe; three figures
down the side of every screen are three facts nobody came to the menu for. Do not put one back without a
reason the header cannot serve.

**The lists are capped at `adminListMaxLimit` (500) and filtered and sorted in the browser.** An admin
screen must not be the one endpoint that can pull the whole database into memory; `offset` is already
wired through, so the day 500 stops being enough the panel grows a pager rather than the API changing.

**Deleting a user prunes the shops list held in memory**, because the schema's cascade takes their shops
and the two tabs would otherwise disagree until a reload.

---

## Rules inside the sections

### Накладные

A person is waiting on the other end of these, so the section sits second. **It reloads whenever it is opened
and every `LIVE.waybills` (30s) while it is the section on screen**, unlike the other lists, because a new row
here is the point; the redraw restores `.scroll`'s `scrollTop`.

- **Files come through `apiBlob`, never a link or `<img src>`**: neither sends the bearer token, and the
  photo and the PDF have no public url at all. The photo modal holds a blob url and revokes it in `onClose`.
- The list carries `item_count` and no rows; `GET /api/admin/waybills/{id}` is read when one is opened. **The
  name «Накладные» is deliberate**: «В корзине» in Шаблоны already means the price index.
- Sender names reach the page through `textContent` like everything else a stranger writes.
- Deleting is the panel's only write. A list is otherwise immutable: it has a number and its sender holds it.

### The anomaly report

**Its baseline is the MEDIAN, and the price index stays the arithmetic mean.** The two answer different
questions: the index asks "what does this market cost", where every real price should count; the report
asks "is this one price wrong", where the whole point is to be unmoved by the outlier being hunted.
**Changing the index to a median because of this report would be the bug.** Comparison is per (shop
category, `template_key`), and a line needs at least three priced shops before its median means anything;
both numbers are query parameters, because the right ones are unknown until there is real data.

**The columns are named for their owners** — «Цена магазина» and «Обычная цена», both right-aligned so
the two numbers line up on their last digit, with the median's sample size under it rather than in a
column of its own. **The number to ring is in the row**: `AdminPriceAnomalies` joins `users` and carries
`contact_phone`, `owner_name` and `owner_phone`; the panel renders a `tel:` link and prints the owner's
number only when it differs. A report that makes the founder open Магазины and search for the shop is one
that gets read and not acted on.

### Products and shops

- **An admin editing a product goes through the same three-way rule the owner does**, not a bypass:
  `UpdateProductPricing` has no `SET` for name at all, so a template row cannot be renamed from here.
  The rule is data integrity rather than permissions — a renamed template row stops being the same
  product as its counterpart down the road.
- **Shop category is not editable from here or anywhere**: the panel reuses `UpdateShop`, which keeps that
  true by construction.
- **Excluding a shop from the comparison is an admin decision that outranks completeness**
  (`POST /api/admin/shops/{id}/exclude`); see the `backend` skill for the column.

### VIP placements

`PUT /api/admin/shops/{id}/vip` takes **days, not a date** — the realistic input is "sold them a month",
and an absolute date makes extending a live placement ambiguous about from when. `days: 0` revokes
through the same statement, since a grant and a revoke are one fact with different values. Capped at 730
days so a slipped keypress cannot sell a placement into the next century.

**The storefront photograph is the panel's job** (`editShopPhoto`, `POST`/`DELETE
/api/admin/shops/{id}/photo`). The VIP carousel is the part of the home screen that is *sold*, so the
picture on it is checked by whoever sold the placement rather than uploaded by the owner. One photo per
shop, the same decode as every other upload.

- **A grant is never refused for a missing photo.** A placement is sold before anybody has the picture to
  hand, so `SetVIP` answers `needs_photo` and the panel opens the upload window on the back of that
  answer. The VIP cell then carries «без фото» until it has one.
- Its own window rather than a field on «Редактировать магазин»: the file uploads the moment it is picked
  (multipart, where that form is json) and the server points the row at it, so there is nothing for a
  «Сохранить» to do.

### «Система»

`GET /api/admin/system` (`Admin.System`) over `internal/sysstat`, polled every tick while it is open
(`LIVE.system`). **A section, not a card on Главная**: that screen is about the business and is full.

- **One goroutine samples every 5 s** (`sysstat.Sampler.Run`) and the handler returns its last reading.
  **The geo count (`DailyQuota.Usage`, the window `SpendGeoCall` refuses on) is the only database work,
  and it must stay so** — everything else is in-memory, which is what lets the screen sit on the tick.
  The host comes from `/proc` and one `statfs` on the photo volume, never a directory walk.
- **CPU% is the difference between two `/proc/stat` readings**, five seconds apart. One reading is the
  average since boot: a plausible number that says nothing about now. `TestCPUIsTheIntervalBetweenTwoReadingsNotTheAverageSinceBoot`.
  Memory used is `MemTotal − MemAvailable`; `MemFree` would count the page cache as used.
- **The headline is `busy_waits`, not pgx's `EmptyAcquireCount`.** pgx also counts an acquire that found
  no idle connection and opened one while the pool had room — routine after `MaxConnIdleTime` shrinks the
  pool to `MinConns`. `sysstat.busyWaits` subtracts every connection that could have finished opening in
  the interval, so it errs towards silence; the raw count is printed beside it, named, with that caveat.
  `TestOnlyAWaitForABusyConnectionCountsAsTheFullPool`.
- **Nothing is persisted.** The cpu hour, the wait count and its first/last moment start again at each
  restart, which is why the strip says when the server started.
- **Only the processor has a chart**: a fixed 0–100% axis, points at their real age. Load average is
  already a time average, the disk does not move in an hour, and the pool and search slots are instants
  a 5 s sample would mostly read as zero. Bars turn amber at `NEAR` (80%) — a colour, not an alarm.
- **It cannot answer while Postgres is down**: `RequireAdmin` reads the role first. A failed geo count
  alone answers `geo: null` and the rest still renders.

### The panel refreshes itself — `liveTick`

«Обновить» is a button nobody presses at the moment it would matter, so one `setInterval` (`LIVE.tick`,
5s) drives the dashboard counts every `LIVE.stats` (45s). `liveNow()` forces a round when a section is
opened or the tab comes back into view.

- **Nothing runs while `document.hidden`** — a panel left open on a second monitor costs nothing, and a
  `visibilitychange` listener catches up the moment it is looked at again.
- **`live.busy` skips a round rather than queueing it**, so a slow database stretches the interval
  instead of stacking identical requests on it.
- **A re-render restores the `.scroll` container's `scrollTop`**, or a table jumps to the top while it is
  being read.
- **SSE was the obvious fit and cannot be used: `EventSource` sends no headers**, and every request here
  authenticates with a bearer token from `localStorage`. It would mean an admin token in a query string
  — server logs, browser history — or a short-lived ticket endpoint.

### Before editing the page at all

- **Everything user-supplied reaches the page through `textContent`, never `innerHTML`.** The admin's JWT
  is in `localStorage`, so a shop named `<img src=x onerror=…>` rendered as html would hand away
  administrator access to the whole database. **Owner-written shop and product names are the highest-risk
  strings in the database** — a stranger writes them and an admin reads them.
- **Not built, deliberately**: editing anything beyond the fields listed above, and any audit log beyond
  `log.Printf("ADMIN %d deleted user %d …")` — ids and a role, never a name, a phone number, or the text
  of a shop's own name.

---

## The storage sweeps — «Файлы без товара»

`GET /api/admin/storage/orphans` counts and measures; `DELETE` does it. Both are `RouteOrphans`, and both
re-derive the list from scratch.

**Why there is anything to sweep:** deleting a shop is one statement and the schema cascades, so its
products go and their uploaded photos stay — they are not in Postgres and nothing in that transaction
could reach them. Replacing and removing a photo both unlink correctly; a deleted shop, and a crash
between "write the file" and "point the row at it", are what feed this.

**Three rules, and every one of them deletes a live photo if it is reversed:**

1. **List the files first, read the database second.** In that order a row committed between the two reads
   is *seen*, so its file is protected. Reversed, a row written after the query whose file was already on
   disk looks unreferenced, and the sweep deletes a photo a product is pointing at.
2. **Nothing younger than an hour.** The real window between "the file exists" and "the row exists" is one
   upload request, bounded by `dbctx`'s deadline. An hour is orders of magnitude of headroom and costs
   nothing. The card says how many were held back, or "12 files, 0 deleted" reads as a broken button.
3. **A referenced master claims its `_thumb`.** Only the master's path is stored, so a sweep matching paths
   literally would find every thumbnail unreferenced and **blank every grid in the market on its first
   run**, with the database perfectly consistent throughout.

**Two sweeps, one scan, two doors.** `sweepScope` is the only difference between them:

| sweep | route | lists | protected by | deletes through |
| --- | --- | --- | --- | --- |
| uploads | `/api/admin/storage/orphans` | `shops/uploads` | `AdminUploadedImagePaths` | `RemoveFile` (`IsUpload`) |
| catalogue | `/api/admin/storage/catalogue` | `shops` (uploads skipped) | `AdminReferencedImagePaths` — templates **and** every shop row | `RemoveCatalogueFile` (`IsCatalogue`) |

**A shop row protects a curated file as much as a template row does**: a shop seeded before a template's
photo changed still draws the old one. Neither door accepts the other's paths, so a bug in one sweep
cannot reach the other's files — `TestTheTwoDeletionDoorsDoNotOverlap`,
`TestTheCatalogueSweepTakesOnlyWhatNothingDraws`, `TestASweepCannotReachTheCuratedCatalogue`,
`TestASweepKeepsThumbnailsAndAnythingWrittenRecently`.

**The catalogue GET doubles as the photo picker's source** (`listsEveryFile`: every master with `used` and
a `thumb_url`), built on the same walk so it obeys rule 1 for free. A GET also carries `paths`, so the
confirm dialog can name what goes. **The DELETE takes no list of paths** — a client-supplied list would be
a request naming files to delete, behind one middleware check, operating on a scan minutes old — and it is
capped at `orphanSweepLimit` (2000), so one press cannot be an hour of network round trips.

Panel-side: the strips live under Шаблоны (`drawStorage`, `storageStrip`), because this is maintenance
rather than a fact about the business.

- **It does not load itself.** Every other panel rides on the timer; this one would mean walking the whole
  store and reading every image path every 45 seconds — every file in the market, on every tick.
  «Проверить» is a button.
- **The result is rendered from `state.storage`, never written into the DOM by the click handler**, which
  is what lets opening Шаблоны again show the last scan rather than an empty strip.
- **After a sweep the card re-scans rather than rendering the DELETE's own answer**: that response's
  `files` is how many were removed, not how many are left, and after a capped sweep there genuinely are
  more.

---

## Templates

They live in `product_templates`, not in Go. **The two-step shape is the design: editing a template decides
what the *next* shop is created with** — add, rename, change a unit, delete, none of it touches an
existing shop — and **«Применить ко всем» is the second, louder step.** Merging them would make a typo in
a name an event that touches thousands of rows.

**Every write reloads `internal/catalog` before responding.** The whole API reads templates out of memory,
so a write that skipped the reload would leave the process seeding from the old list until it restarted:
the founder edits a template, presses sync, and watches nothing happen.

### The sync — `POST /api/admin/templates/{category}/sync`

The button that replaces "delete the shop and make it again": seeding happens once, at creation, so a
template edited afterwards reaches nobody. Three statements in one transaction:

```
insert  rows the template has and the shop does not, unpriced
update  names/units/categories/photos/specs/section/in_basket for rows both have — prices untouched
delete  rows the shop has and the template no longer does
```

- **The transaction is not decoration.** A shop with the new rows inserted but the stale ones not yet
  deleted holds two versions of its own basket, and `shop_basket_index` would count both — publishing a
  total for goods it does not sell, under a badge claiming that is what it costs.
- **`price` and `availability` are absent from the update's `SET` list, and that is why it is safe to
  run.** They are the owner's work; a sync that reset them would destroy hundreds of hand-typed numbers
  silently, because the rows would still be there.
  `TestSyncRestoresMissingRowsAndKeepsEveryPrice` is the test that matters.
- **Names are not synced for обои** — a slot's name is the owner's real wallpaper, so syncing would replace
  every обои catalogue with ten copies of «Обои премиум (Россия)». The flag comes from
  `catalog.IsOwnerNamedCategory`, derived from the same declaration `IsOwnerNamedSlot` uses, so a second
  slot-based category is covered automatically.
- **Two consequences the confirm dialog says out loud**: adding a product to a template drops **every shop
  of that category out of the price comparison** until its owner prices the new row, and deleting one takes
  whatever price the owner had typed.
- **`AdminTemplateChangedRows` is the third kind of drift**, alongside missing and surplus rows. Without it
  a rename showed «все магазины совпадают» — false, and with membership it would hide half a market
  totalling a different basket. It compares exactly the columns the sync's update rewrites; **keep the two
  in step.**
- The template travels as **one jsonb array** expanded with `jsonb_to_recordset`, not five parallel
  `text[]`s that could get out of step.
- **Write endpoints refuse GET** (`SyncTemplate`, `ImportTemplate`): a prefetching browser must not run a
  sync.

### Basket membership

**«В корзине» is a switch on each row, and «Оценили» beside it is how the founder knows when to flip it**:
priced shops over *all* shops of the market (`AdminTemplateCoverage`), green at 100%, with «можно в
корзину» from `BASKET_READY` (80%). Voting a row in asks first when not everybody has priced it, naming
how many shops will drop out; voting out never asks. Like every template edit it reaches shops only
through the sync — which is why ticking the box no longer asks, and `confirmSync` is the dialog on the step
that actually reaches them. What the editor owes the founder is the number, which `basketNote` carries and
`warnNote` paints amber when enabling it would drop shops out.

### The catalogue grid and the editor

**The catalogue is cards, and a card opens an editor.** It was a table whose first column was a 38px
thumbnail: eight columns of which one was the thing being looked for, and checking that five sizes of one
shovel share the right picture meant reading a column of postage stamps.

**The grid is the app's `ProductTile` drawn again** — same geometry, the `#EFF0F5` photo panel, the «В
наличии» badge, name, `specs`, price slot — so the founder sees what a customer will see. **It carries the
app's literals, not the panel's tokens, and stays light in the dark theme** (the app has none): change
`product_tile.dart` and this moves with it. **A template row has no price, so the card has no price line**:
«Цена не указана / шт» was the panel inventing a line the app never draws, on every card in the grid.

**Admin facts sit under the card, outside it** — the basket chip, «N / M» priced, the coverage line — so
the card itself stays what a customer sees. The key and the section ride on the button's `title`, because a
long section name truncates on every card in the grid. **The whole card is one button** and every field is
behind it, which is what stops the row growing its own controls again.

**`tplScroll` restores each grid's scroll position, and `renderTemplates` restores `window.scrollY`** —
the page scrolls on the window, the rebuild empties `#tpl-list`, and the first grid's `scrollTop` forces a
layout while the later categories do not exist yet, which threw the page to the top on every edit.

**One size is one row.** «Похожий размер» opens the add form prefilled from a row, so another size is a new
key and a new description. «Описание» is free text up to 80; «Раздел в магазине» is a select over
the row's own category's `SECTION_GROUPS` (a plumbing row cannot be filed under «Смеси и краски»), refused
server-side as `invalid_section`.

**The photo field is three doors and no text input** (`photoField`): «Загрузить», «Из каталога»
(`pickPhoto` over the catalogue scan), «Убрать». A path that cannot be typed cannot be mistyped into a
blank tile in every shop of a market.

- **The upload writes the file before any row names it**, which is the api's ordering: abandoning the form
  leaves a file for the catalogue sweep, and the other order leaves a row naming a file that is not there.
- **`api()` sets `Content-Type: application/json` only for a string body.** A FormData body carries its own
  with the multipart boundary in it, and overwriting that makes the server see no parts.

### `image_path` and `template_key` are both guarded

- **A non-empty `image_path` must pass `imagestore.IsCatalogue` and name the row's own category's folder**
  (`checkTemplatePhoto`, `invalid_image_path`) — on the one-row form, on the sheet import with its line
  number, and on the edit endpoint, which reads the row first (`AdminGetTemplateItem`) because the url
  carries only an id.
- **`template_key` cannot be edited, and the statement enforces it**: `AdminUpdateTemplateItem` has no
  `SET` for that column. Changing a key would not rename anything — it would orphan every shop already
  seeded with the old one, and the next sync would delete those rows and insert fresh unpriced ones,
  **losing every price silently**, because the row count would look unchanged.

### The обои photo rule — three locks, because one is a silent market-wide outage

An обои row names a *kind* of wallpaper; the product is the roll standing in one shop. The owner's right to
photograph it is granted by **the template row having no photo** (`templateFlags`), so one picture put on a
slot from the panel takes that right away from every обои shop at once — and the next sync replaces each of
their real photographs with it, sending the files they replaced to the orphan sweep. The row count looks
exactly as it should throughout.

| lock | where |
| --- | --- |
| the field is disabled for an owner-named category | `photoField`'s `locked`, panel |
| a write naming a photo is refused | `checkTemplatePhoto`, `owner_named_photo` |
| the upload endpoint refuses the category outright | `UploadCataloguePhoto`, before a byte is read |
| the sync keeps a shop's own upload | `AdminSyncTemplateUpdate`'s `uploadPathPattern` |

**The sync's guard is the `shops/uploads/` prefix, not the category**, so a second slot-based category is
covered the day it exists — and `AdminTemplateChangedRows` carries the same `CASE`, or the panel reports the
market as behind its template forever. `TestSyncKeepsAShopsOwnPhotographWhenTheTemplateGainsOne` pins both
halves.

### The sheet import has no UI

`POST /api/admin/templates/{category}/import` (`ImportTemplate`, `maxTemplateImportRows` 500) takes the
whole template as TSV and is **reachable only by curl** — the «Таблицей» box was removed from the panel.
**The paste is the whole template, so a missing row is a deletion**, which is why `apply: false` is a
check-only pass: the same code path, rolled back instead of committed. Keys of another category are refused up front, and errors
name `row N`.
