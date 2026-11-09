# The dashboard — what each panel reports, and why that thing

Read when adding, removing or rewiring a card on Главная. The panel's rules are in `SKILL.md`.

**The editing rule: every panel answers a question no other panel answers.** `ranked / total` was once
drawn four times over — a KPI, a gauge, two boxes under it and a funnel's terminal bar — and four
renderings of one ratio read as four findings. One card draws it now.

An admin panel that counts rows tells you how much of the product exists; these tell you what to *do*.
**Three rows, and nothing below the fold.**

## Row 1 — three counts and the shape of the market

**No tile is tinted.** One of three independent counts carrying a fill and a solid icon looked like the
answer the other two were asking about. The orange is in the glyph, the same on all three.

Each tile is a stack, not two opposed columns: icon and label on the top line, the number, then the delta
and `.k-sub` under it at full width. Right-aligning the delta on the number's baseline left `.k-sub` about
140px and truncated «151 покупателей · 32 владельцев» mid-word — **a line that is cut off is worse than no
line**, because the reader stops to work out what was there.

- **«Магазины» is the count and nothing else.** The gauge one row down is about the in-comparison ratio,
  and a tile that also states it makes the reader compare two renderings of the same thing.
- **«Пользователи»**, with `покупатели N · владельцы M` underneath: the split says how much of the number is
  demand and how much is supply. Named to match the sidebar — a tile calling the same set something else is
  a second name for one thing.
- **The sparkline is the total rebuilt backwards from today** (`runningTotal`), not the per-day figure
  «Регистрации за 30 дней» already draws one row below. The tile's subject is the total, so the line says
  how it got there. Deletions are not in `signups`, so a removed account tilts the earliest points by one —
  the line has no axis and is read for its shape. VIP gets no sparkline: a sold placement is not a
  cumulative count.
- **«VIP-места» is a fraction, because VIP is inventory.** The denominator is `vip_slots`, sent by the
  server from `vipShopsLimit` — the carousel draws that many places whether or not they are sold, and a
  panel with its own copy would keep saying «из 5» the day it grows to six. **Do not hardcode it.** The
  `.k-bar` under it draws the same fraction, and it is the only tile that gets one: inventory is the only
  count here with a ceiling, and a ceiling is what a bar can draw.
- **«Категории магазинов»** answers what this market is made of. The ring plus its list is one object,
  which is why `buildDonut` carries no legend of its own — the table beside it names each category against
  a swatch from the same `shade(i, n)`. It stands beside the KPI row *and* the chart under it, the only
  piece of real structure in the layout.

## Row 2 — the two things that move day to day

Both cards carry `tall` (`align-self:stretch` plus a flex column): they are one row of one subject, and a
card ending 160px short of its neighbour reads as one that failed to load. The gauge's ring and sentence
sit in a `.grow` that takes the slack.

- **«Регистрации за 30 дней»** — **`generate_series` in `AdminSignupsByDay` is what produces the empty
  days.** `GROUP BY created_at::date` returns only days that have rows, and the gap is the information. The
  axis draws `min(top, 4)` gridlines, because quarters of 1 rounded for the label printed «1 1 1 0 0» up
  the side of an empty install.
- **«Заполнение каталогов»** — the completion gauge, and the only place `ranked / total` is drawn.
  **Two states, never more**: a catalogue is finished and the shop is in the comparison, or it is not,
  because 1% and 99% publish the same nothing. `AdminCatalogueFunnel` still returns `empty` and `started`
  separately; the panel sums them.
  - **No caption under the title.** «Магазин попадает в сравнение, только когда заполнен целиком» is the
    rule the whole card is about, and printing it on every load is explaining the same thing to the same
    person forever.
  - **One sentence, and it does not change subject with the answer** — `16 из 37 магазинов в сравнении цен`
    at every value, never congratulating a finished market. **No plural agreement anywhere in it**:
    «21 магазин», «22 магазина» and «25 магазинов» are three endings, so the count sits after a preposition
    where russian does not decline it.
  - **A full ring, matching the «Категории магазинов» ring beside it** — two readings of the same shape are
    one idiom where an arc and a ring were two. The remainder is `--track`, not a tint of orange: the part
    that is missing must not read as a second, paler measurement. The readout is wrapped in one `div`
    inside `.g-mid`, because `place-items:center` gives each child its own grid row and pushed the figure
    and its caption apart onto the ring itself.
  - **The two boxes are one block split by a hairline**, not two bordered cards: one measurement cut in two.
    `grid-template-columns:repeat(2,minmax(0,1fr))` written the long way is load-bearing — a bare `1fr` is
    `minmax(auto,1fr)`, and `auto` is the child's min-content width, which a nowrap label pushes visibly
    outside the card's edge.
  - **«Не заполнены» is a button, and it is disabled at zero.** Worth knowing before it is reported as
    broken: on a market where every catalogue is finished — the usual state of a test database — the number
    reads `0` and it does not open, because there is nothing to list. It keeps its colour rather than
    fading, since it is still half a measurement.

## Row 3 — «Кто дешевле» and «Средний чек»

**The only two panels that report what the product *says* rather than how much of it exists.**

### «Кто дешевле» (`buildRace`)

Up to `adminRankingDepth` (5) shops of one market, cheapest first, from `AdminMarketRankings`. It replaced
a card that printed only the winner, which could not answer the question the founder actually has — **is
anybody competing?** Three shops at 4.61, 4.63 and 4.65 million are fighting; 4.6, 5.4 and 6.2 is one shop
with nothing pressing on it, and a single leader row makes those two markets look identical.

- **`CROSS JOIN LATERAL`, not `ROW_NUMBER()`** — sqlc cannot compile a window function filtered from an
  outer `WHERE`, and "for each category, the first N of this ordered list" is what lateral is for. **The
  rank is not on the wire**: it is the row's position in the result, and a stored rank could disagree with
  the order it came in.
- **The bar measures the distance from that market's average, not the basket.** Drawn from zero, five
  baskets between 4.6 and 5.6 million are five bars within 20% of each other's length — a picture saying
  "these all cost about the same", which is the opposite of the finding. So the axis *is* the average:
  cheaper grows left, dearer grows right, length is `|индекс − 100|` against the widest gap on screen with a
  floor of 4 points, and the centre tick repeated down every row is what makes five bars read as one line.
  Dearer bars are pale, not red: somebody has to be the expensive one, and the chip carries the sign.
- **One market at a time, chosen by tabs on their own row.** Four rankings side by side would be four charts
  on four different scales — an Обои basket is ten lines and a Универсальный one is a hundred — and the eye
  compares whatever is adjacent whether or not the comparison means anything. The tabs sit below the header
  because four category names is ~560px of pills, which wraps inside the header and takes the title with it.
  `state.raceCat` survives the poll and falls back to the busiest market when the one it names empties.
- A row opens that shop's catalogue.

### «Средний чек» (`buildTrend`)

One row per market: what a basket costs there now — the **mean of every complete shop's own basket total**
(`AdminCategoryBaskets`, averaged over `shop_basket_index`, so an unfinished catalogue is not in it) — and a
sparkline of the last thirty days beside it (`AdminBasketHistory`). Two halves of one subject: the figure
says what the category is worth, the line says whether that is moving.

- **Not four lines on one chart.** Four oranges crossing each other is a picture nobody reads, and the four
  numbers are not on the same scale anyway.
- **The 30-day change is a line and not a number.** A «+0,0%» chip beside each sparkline reads as a
  measurement, and it is `0%` on every market until prices have actually moved — which is every market for
  the first weeks of any install. The line says the same thing without claiming to have measured it.
- The sparkline has no axes, labels or tooltip: at 78×26 the only thing it can say is which way the line
  went, which is what it is being asked. A flat series draws down the middle rather than dividing by zero.
- **Fewer than two days of history prints «с сегодня» instead of a line**, because the table starts empty on
  any database that has not been running. It is not a failure state and does not get an error colour.

### The history is written down, because it cannot be recomputed

`shop_basket_index` is recomputed on every write that can move it, so it always answers about *now* and
yesterday's basket is gone the moment an owner retypes a number. `basket_history` is one
row per `(day, category)`, upserted by **`startBasketHistory`, a goroutine in `main.go`**.

- **Hourly, not nightly.** A daily ticker fires at whatever moment the process happened to start, so a server
  restarted around then skips whole days and a laptop that is only on in the afternoon records nothing. The
  statement is an idempotent upsert keyed by `(day, category)`, so twenty-four runs write what the last of
  them would have written alone — and today's point stays current to within the hour.
- **The whole aggregate runs in the database** (`RecordBasketHistory`), one statement, nothing travelling
  through Go, which is what makes it cheap enough to put on a timer.
- A failure is logged and the loop continues; it does not join the shutdown path, because there is no state to
  flush and losing an in-flight upsert costs an hour of a number rewritten every hour.
- **A day with no row is a day the server was not running**, and the sparkline joins across the gap rather
  than inventing a point. `AdminBasketHistory` deliberately has no `generate_series`, unlike
  `AdminSignupsByDay`, where the empty days *are* the information.
- Pinned by `TestTodaysBasketIsRecordedAndComesBackOnTheDashboard` (which runs the statement twice and
  asserts one row) and `TestTheMarketRankingIsPerCategoryAndCheapestFirst`.

## Behind a number instead of on the page

**«Не заполнили каталог»** (`openUnfinished`) is a window hanging off the «Не заполнены» figure, not a table
on the front page: eight rows permanently answering a question the founder asks about once a week. Behind the
number it costs nothing until it is wanted and can carry **every** unfinished shop — shop and category, the
date it was created, how many rows are still unpriced out of how many, and a `tel:` link. It reads
`state.stats.attention`, which the dashboard request already carries, capped at `adminAttentionLimit` (100).
**No second endpoint.**

## Removed, and not to be re-added

- **«Цены по рынкам»** (per-category coverage, median basket and spread) — and the queries behind it went
  with it rather than being left dead.
- The product-category bar chart: a picture of the catalogue, not a fact about the business.
- The anomaly teaser: a worse version of a screen one click away.
- The identity block in the top bar, and a sentence under the page title.
- A date-range picker in the header: every query behind this screen has its window baked in.
- «Подробная статистика →»: there is nothing on the other end of it.
- A `+8%` chip beside each sparkline, and drawing the «Кто дешевле» bars from zero — both are the lies the
  cards above exist to avoid. **Reference dashboards will keep showing all three.**

## The dashboard fills the window

`main` is a flex column, `#v-dash` takes the slack and `.dash` is `grid-template-rows:auto 1fr 1fr` — the KPI
row keeps its content height, rows 2 and 3 share what is left. Two things it rests on: every card in rows 2
and 3 is `.card.tall`, and **`drawSignups` measures `host.clientHeight` instead of writing a height down** —
a chart drawn at a fixed height inside a stretched card leaves the difference as empty fill under it.

`1fr` and deliberately **not** `minmax(0,1fr)`: on a window too short for three rows the page scrolls, where
a zero minimum would clip the ranking inside its own card instead.

**`.dash` is `align-items:start`, not the grid default** — an unfinished card's empty fill reads as a broken
panel, where the same space left as page reads as the page. The two exceptions are rows of one subject:
`.kpi` and `.card.tall`.
