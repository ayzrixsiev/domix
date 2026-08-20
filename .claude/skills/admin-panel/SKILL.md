---
name: admin-panel
description: >
  Domix's two web pages, served by the Go API itself — the `/admin` panel (statistics,
  anomaly report, user/shop/product management, VIP placements, the support inbox, template
  editing and sync) and the `/delete-account` page Google Play requires. Use when working in
  `backend/internal/webui/`, `backend/internal/endpoints/admin.go`,
  `backend/db/queries/admin.sql`, the `RequireAdmin` middleware, the template sync endpoint,
  or anything about admin roles, the anomaly report, the support inbox, or the panel's
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

**The page performs the deletion; it does not describe where to ask for one.** It used to print an
email address and a thirty-day promise — a promise a person keeps by hand, which made it the part of
the product most likely to be quietly broken. It is now the app's own Telegram handshake pointed at
delete: type the number, confirm it in the bot, the account is gone. Root §7 has the rules that make
that safe; what follows is the page.

- **One centred card, and deliberately almost nothing on it**: the field, the button, and what
  disappears. Everything else that was there — the in-app instructions, the email path, the English
  column — was describing a process that no longer exists.
- **Two languages in one file** (ru/uz), picked by CSS off `<html lang>`, and it **renders correctly
  with javascript disabled** — the audience is a Play reviewer following a URL, and a blank page is a
  rejection. Confirming needs JS, so `<noscript>` points at the support address. Every dynamic string
  is written into the DOM in **both** languages for the same reason the static copy is: switching
  language after an answer has landed must not blank it out.
- **Three steps in one card**, swapped by the `hidden` attribute: the field, "you are in Telegram now",
  the answer. `[hidden]{display:none !important}` is load-bearing — `hidden` is styled by the
  *browser's* stylesheet, which any author rule outranks, so `.btn{display:flex}` silently un-hides
  every button carrying it.
- **The lede disappears once the form does**, and «Начать заново» is hidden on `success` alone — after
  a successful deletion there is no account left to start again with.
- **Five outcomes, one sentence each**: `success`, `no_account`, `mismatch`, `error`, and `not_found`
  for a session that expired. They are the `Deletion*` constants in `internal/auth/session.go`; **a
  status added there needs a sentence added here** or the page renders the fallback.
- **A failed poll is not an answer** — only the server ends the flow. The client's own cap is five
  minutes, half the session's ten-minute life, and `visibilitychange` polls immediately on return from
  Telegram, where a backgrounded tab's timers have been throttled.
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

**Authentication is the app's own Telegram handshake, reused.** The page POSTs `/api/auth/init`,
shows the `t.me` link, polls `/api/auth/status`, then calls `GET /api/me` to check the role. **No new
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

**Deleting an admin account is refused, including your own.** The small reason: a panel whose delete
button can remove the last administrator can destroy itself. The real one: every other account can
register again with the same phone number, where an admin cannot re-grant themselves a role only SQL
can set.

**The raw price index is shown here and nowhere else.** Root §5 is emphatic that `price_index` must
not reach the app; an administrator is the reader who has been taught to read it. **This is not a
licence to add it to `ShopResponse`.**

---

## What the panel does

| tab | holds |
| --- | --- |
| **Обзор** | four KPIs, a 30-day signups line, the catalogue funnel, «кому позвонить», and «Рынки» — a donut and a per-category table in one card |
| **Поддержка** | the support inbox: who wrote in, who is waiting, and the reply box |
| **Аномалии** | prices that disagree with the market for the same basket line |
| **Пользователи** | edit name and role, delete |
| **Магазины** | edit the four editable fields, grant/revoke VIP, open the catalogue, delete |
| **Шаблоны** | what each template holds, how far shops have drifted, and one button to push it to all of them |

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

**An admin editing a product goes through the same three-way rule the owner does**, not a bypass —
`UpdateProductPricing` has no `SET` for name at all, so a template row cannot be renamed from here
either. The rule is data integrity rather than permissions: a renamed template row stops being the same
product as its counterpart down the road. What an admin actually needs is the price, editable on every
row. **Shop category is not editable from here or anywhere** — the panel reuses `UpdateShop`, which
keeps that true by construction.

**`admin` cannot be assigned or removed over the API.** The endpoint is behind `RequireAdmin`, so only
an administrator could call it, and it stays closed anyway: the property worth having is "there is no
code path", which survives a stolen token and a mistake in the middleware wiring.
`TestAdminRoleCannotBeAssignedOverTheAPI` pins both directions — granting is a 400, demoting an
existing admin a 403.

### VIP placements

`PUT /api/admin/shops/{id}/vip` takes **days, not a date** — the realistic input is "sold them a
month", and an absolute date makes extending a live placement ambiguous about from when. `days: 0`
revokes through the same statement, since a grant and a revoke are one fact with different values.
Capped at 730 days so a slipped keypress cannot sell a placement into the next century. SQL fallback:

```sql
UPDATE shops SET vip_until = '2026-09-03T00:00:00Z' WHERE id = 1;  -- grant
UPDATE shops SET vip_until = NULL WHERE id = 1;                    -- revoke
```

### The support inbox

One row per user who has written in (root §7 has the schema and the app's half). **Two counts, two
questions, and collapsing them into one is the mistake to avoid:**

- **`unanswered`** — messages from the user newer than the last support reply, still derived in SQL and
  still the queue. Reading a thread does **not** move it: a conversation opened and not replied to is
  still work, and settling it on read loses it the moment the founder is interrupted.
- **`unread`** — messages newer than the last time *this admin* opened the thread, from
  `support_thread_reads` (migration `000002`). This is the one reading clears, and the one the sidebar
  badge shouts about. Rows with unread carry an orange left edge and a «новых N» tag.

**The sidebar pip counts `unread` and is hidden outright at zero** (`pip.hidden`), with both numbers
spelled out in the nav button's `title`. It briefly fell back to `awaiting` when nothing was unread —
so a founder who read five and answered none still saw five — and that was wrong in practice: it is a
badge that only clears when a reply is *sent*, which is the behaviour the read marker existed to fix.
Plenty of messages are read and need no answer. **Reading is the action; the badge follows the
action.** The queue lives in the «Ждёт ответа» column, which still carries `unanswered` per thread.

**Opening a thread is what marks it read** — `GET /api/admin/support/threads/{id}` advances the
watermark, because in this panel that request *is* the reading. The listing endpoint deliberately does
not, since it is polled on a timer. Replying marks it read too. **The modal's first successful `pull()`
calls `loadStats()` and `loadSupport()` outright** rather than resetting the loop's clocks: a badge
that clears five seconds after you opened the thread still reads as stuck.

- **Threads are addressed by user id.** A thread *is* one user's messages, so there is no row to point
  at. The handlers check the user exists before reading or replying, so "they deleted their account
  while you were typing" is a 404 the panel explains rather than a foreign-key 500.
- **The reply sets `from_support` server-side**, exactly as the app's endpoint hardcodes false.
- **The conversation is drawn as chat bubbles, not another table** — the founder is answering a person,
  and it has to look like what the user is looking at on their phone, since both halves of a
  misunderstanding start here. Support is on the right in orange, the user on the left; the app draws
  the same thread mirrored. Bubbles carry the **clock only** — the «Сегодня»/«Вчера»/date chip between
  days carries the date — and they are not signed, because in this panel orange already means "you".
- **It is the one modal that is a window rather than a form** (`.modal.chatm`), and the layout is what
  makes that true: a flex column that **does not scroll**, with the conversation scrolling inside it,
  so the header and the composer keep their full height at any window size. Built the ordinary way —
  the modal body scrolling with the shared **`.m-acts` row sticky at `bottom: 0`** — that row's opaque
  background paints over whatever is beneath it, which clipped the textarea's bottom border and read as
  a field with a missing edge. **If another tall modal grows a composer, it needs this shape, not a
  taller `.m-acts`.** The floor is `min-height` on `.chatm` and `min-height: 0` on `.chat`: a pixel
  floor on the conversation would refuse to shrink and push the composer out of an `overflow:hidden`
  box on a short window.
- **No «Закрыть» button** — the × in the header closes it (so do Escape and the scrim), and the row it
  would occupy is the composer's. **The composer has no placeholder either**: the Ctrl+Enter hint sits
  under the field rather than inside the box the answer is typed into.
- **Ctrl/⌘+Enter sends, not plain Enter.** These answers run to several lines, and a newline key that
  sends half of one is how a support reply goes out unfinished.
- After a reply the inbox and the stats are both reloaded — the row behind the modal still counts the
  conversation as waiting.
- **Nothing notifies the user.** The app has no push at all; the reply waits until they open the tab,
  where a poll of its own picks it up (root §7).

### The panel refreshes itself — `liveTick`

`«Обновить»` is a button nobody presses at the moment it would matter, so one `setInterval` (5s tick)
drives everything: the dashboard counts behind the badge every 45s **everywhere**, the inbox every 12s
**while its section is open**, and an open conversation every 8s. `liveNow()` forces a round when a
section is opened or the tab comes back into view.

- **Nothing runs while `document.hidden`.** A panel left open on a second monitor costs nothing; a
  `visibilitychange` listener catches up the moment it is looked at again.
- **`live.busy` skips a round rather than queueing it**, so a slow database stretches the interval
  instead of stacking identical requests on it.
- **`renderSupport` restores the `.scroll` container's `scrollTop`**, or the table would jump to the
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

An admin panel that counts rows tells you how much of the product exists. These tell you what to *do*:

- **The catalogue funnel** — how many shops sit at nothing / started / half / almost / done. It matters
  more here than in most marketplaces because of the all-or-nothing rule: a shop at 99% publishes
  exactly as much as one at 0%, which is nothing. «Почти готово» is not a progress bar, it is a list of
  people who did nearly all the work and are getting none of the benefit.
- **«Кому позвонить»** — the same fact turned into an afternoon: owners nearest the line, their phone
  numbers, rows remaining. The panel's most useful screen, and it is four columns of a table.
- **«Рынки»** — a donut of the shop split plus a table of shops / coverage / basket price / spread per
  category. The app shows a customer one shop's badge; nobody could see whether сантехника varies by 4%
  or 60%, which is the difference between the comparison being the product and being a decoration.
  **It iterates the shop categories, not the baskets**: a market with shops and nobody in the comparison
  is the row most worth seeing, and the basket query cannot return it (it reads the index view, which
  has no row for an incomplete catalogue).
- **Pricing activity** — did anybody price anything this week, counted by shop as well as by row so one
  owner's evening does not read as a busy market. It is the funnel card's footer, not a KPI: it is the
  rate of change of exactly what those bars measure.
- **Live VIP placements** ride in the VIP KPI's note, soonest to lapse first — a placement that expires
  unnoticed is revenue that stopped without anybody deciding it should.

**The editing rule: every panel answers a question no other panel answers.** `ranked / total` had been
drawn four times over — a KPI, a gauge, two boxes under the gauge, and the funnel's terminal bar — and
four renderings of one ratio read as four findings. The gauge is gone; the KPI states the number and
the funnel explains how it got there. **Removed on purpose:** the product-category bar chart (a picture
of the catalogue, not a fact about the business), the anomaly teaser (a worse version of a screen one
click away), and the identity block in the top bar.

---

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
shadows on content at all**, separation comes from fill — with a white shell floating on beige, a white
sidebar whose active item is a filled orange pill, and charts along a graduated orange ramp. Same brand
orange (`#FF6F00`), different surface.

Before editing it:

- **Everything user-supplied reaches the page through `textContent`, never `innerHTML`.** The admin's
  JWT is in `localStorage`, so a shop named `<img src=x onerror=…>` rendered as HTML would hand away
  administrator access to the whole database. Building nodes is the version of this the next person
  adding a column cannot get wrong. **Support message bodies are the highest-risk field in the whole
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
  of a support message.

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

**Unseen:** a real browser. Every screen was rendered headless and read back — the chat window through
the real page, driven over the devtools protocol with a signed token, at both a normal and a 560px-tall
viewport — and the API was exercised end to end against the live database. But nobody has logged in
through Telegram on this page, the one path a screenshot cannot stand in for.

> **Headless never applies `:focus` unless `Emulation.setFocusEmulationEnabled` is on.** Checking a
> focus ring without it shows the resting border and looks like the css is wrong.
