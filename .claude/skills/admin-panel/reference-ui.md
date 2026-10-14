# The panel's visual language and hand-rolled widgets

Read when changing the panel's colours, theme, nav, charts or the map picker. The panel's rules are in
`SKILL.md`.

## The language is deliberately not the app's

The phone app is cool grey on white with soft shadows. This panel is a cool neutral ramp, **flat — no
shadows on content at all**, separation by fill, with a sidebar whose active item is an orange pill and
charts along a graduated orange ramp. Same brand orange (`#FF6F00`), different surface.

Green is emerald, because the one place it carries meaning — a finished catalogue — reads better against
the slate. **Both themes move together**: inverting one alone leaves a warm light panel next to a cool
dark one, which is two products.

**`--track` is the empty half of anything that fills up**: the gauge's ring, a race bar, a catalogue bar,
the plate under a KPI icon. Deliberately neutral — an orange remainder reads as a second, paler
measurement rather than as the part that is missing. It is in the JS colour mirror as `C.track`, because
two of its users are SVG.

`--beige` is only the login page's ground: one page, with the orange mark standing on it. **The app frame
is gone** — `.app` used to have a margin and a radius on a beige body, a frame around every screen costing
28px in both directions. It fills the window now, and because the margin was deleted rather than
recoloured, dark does not bring the same frame back in another colour.

## The ramp runs `--surface` → `--shell` → `--card`, and the direction is the point

`aside` is `--surface`, `main` is `--shell`, cards and `.kpi` are `--card` with a `--line-2` hairline. It
ran the other way once, with white cards on a near-white `--surface`: **two fills two units apart is not
separation by fill**, which is the principle the panel claims, so the cards read as nothing at all.

- **`.tbl` stays white with a `--line-2` border.** Standing on `main` it is a white object with a visible
  edge; inside a card it is a lighter block inset into a darker one. `thead` at `--card` gives it its
  header band either way.
- **`--card` is used in a dozen other places** — `thead`, `.tag.g`, `.empty .bx`, both icon buttons,
  several `:hover`s. Anything that sits *inside* a card and used `--card` to differ from white needs
  checking. `.btn-g` was the one that broke: grey on grey, a button you had to look for, so it is
  `--shell` with a `--card` hover.
- **`.ib` and `.ia` are filled with `--card`, not `--shell`.** `--shell` is lighter than the card in light
  and *darker* in dark, so an outlined control on it was a ring with nothing inside at one end of the ramp
  and a hole at the other.
- **`C.line2` exists in the JS colour mirror for the chart grid**, because `--line` on `--card` is a
  gridline nobody can see.

**Adding a shadow to a card would be a change of language, not a polish pass.** Modals, tooltips and the
map's own controls are the only things that lift.

## Dark

**One block of tokens under `:root[data-theme="dark"]`, and no second stylesheet** — which is what every
colour in the file being a custom property was for. Three lines in `<head>` write the attribute before the
first paint (an explicit choice from `localStorage`, otherwise the operating system); resolving it at the
bottom of the file would start every load of a dark panel with a white flash.

- **The ramp keeps its direction and inverts its ends**: the page is the darkest thing, the sidebar recedes
  under the work area, a card is a step lighter than the work area.
- **Two groups cannot simply be darkened.** The orange tints 50–200 are *fills* and go dark while the
  accents 300–700 and `--o-ink` go light; and red splits in two, because `.btn-d` needs a fill white text
  reads on while `.tag.rd` needs a word on a dark tint (`--red` / `--red-ink`).
- **The charts are the trap, and it is solved by deletion rather than by discipline.** Svg attributes
  cannot read a custom property, so the `C` mirror has to exist — but it is *read out of the cascade*
  (`readThemeColours`) instead of being a second hand-written copy, and `applyTheme` re-reads it and
  redraws. Nothing in a table needs redrawing: the one colour a list writes from javascript is
  `.prog.full`.
- **`RAMP` is deliberately not read from the tokens and is the same in both themes.** Those are surface
  tints; this is data, and six warm oranges that read on white read better on near-black. A ramp that
  followed the tokens would put the donut's three smallest segments at the colour of the card behind them.
- **Every gradient needs a unique id or the last one rendered wins the page.** `sparkline`'s fill counts
  its own: svg `url(#…)` resolves by document id, so two charts sharing a literal would both paint with
  whichever `<defs>` was written last.
- The only literals left are white *on brand orange* (`--o` is `#FF6F00` in both themes) and the map's own
  controls, which stand on an OpenStreetMap raster tile and are light whatever the panel is.

## The section highlight is one object that moves

`nav` is `position:relative` and holds an absolutely positioned `.nav-pill` that `moveNavPill()` sizes and
moves by `transform` from the active button's offset box. A `background` on whichever button carried
`[aria-current]` was one fill dying and another being born — two events in two places, which reads as a
flicker rather than as a change of place. The model is `BestOffersList` in the app: a pill sliding along a
track, **drawn under the labels**.

- **`z-index` on both is load-bearing.** An absolutely positioned element paints above its in-flow
  siblings, so without `z-index:0` on the pill and `z-index:1` on the buttons the orange fill lands on top
  of the label it is supposed to sit behind.
- **The active button paints no background of its own, and its `:hover` is killed too** — a fill on top of
  the pill covers the thing that just slid underneath.
- **Measured, never derived.** The sidebar is a column on a laptop and a scrolling row under 900px where
  the labels are hidden, so the same four numbers answer both layouts. The debounced `resize` listener
  calls `moveNavPill(true)`.
- **`.cold` suppresses the transition for a placement that is not a movement** — the first paint and a
  resize. Reading `offsetWidth` between removing and re-adding the class is what forces the layout that
  makes the suppression real; without it the two class changes collapse into one style recalculation.

## The focus ring

Nothing in the file had ever styled one, so Chrome's own (`outline: auto 1px rgb(16,16,16)`) took over, and
it appears on whatever still holds focus the moment the browser decides the user is on the keyboard — one
arrow key to scroll a table, or the window being clicked away from and back, and a nav button clicked
minutes ago grows a black border. It reads as a rendering fault, and it was reported as one.

The fix is a **replacement, never `outline:none`**, which deletes the ring for the one person it exists for.
Zero-specificity `:where(button,a[href],[tabindex]):focus-visible` gets `2px solid var(--o-600)` at a 3px
offset; `:where(input,select,textarea):focus-visible` opts out, because those already carry a ring of their
own. A mouse click still shows nothing — `:focus-visible` does not match on a pointer.

> **Headless chrome never applies `:focus` unless `Emulation.setFocusEmulationEnabled` is on**, and it needs
> a keyboard event after the click: the click alone gives `:focus` without `:focus-visible`, which is the
> state that looks fine. Checking a focus ring without either shows the resting border and looks like the css
> is wrong.

## The charts

**Hand-rolled SVG, measured in real pixels** rather than drawn in a scaled `viewBox` — a viewBox that scales
also scales the text, so the same chart would get 9px labels on a laptop and 14px on a monitor. Hence the
debounced `resize` listener, and no charting library.

- **The signups line is a Catmull-Rom curve at tension 0.18**, low on purpose: higher overshoots below zero
  on a spike and draws a negative day.
- **A button has to move when it is pressed.** `#refresh` was reported as dead while working: against a
  local database every request finishes inside a frame, so the spinner flickered and the numbers — usually
  the same numbers — did not visibly change. Three fixes, all needed: `.ib:active{transform:scale(.88)}`, a
  420ms floor on the spinner, and a toast, because an answer identical to the last one still has to look
  like an answer. The first load passes `{silent:true}`.

## The map picker

**The shop editor picks a location on a map, and the map is hand-rolled** — about 120 lines of web-mercator
arithmetic, a grid of 256px `<img>` tiles positioned by `transform`, drag to pan, wheel or ± to zoom, click
to drop the pin.

- **The alternative was Leaflet from a CDN, rejected for the reason every string here goes through
  `textContent`**: a `<script src="//cdn…">` hands whoever controls that host the ability to read the JWT in
  `localStorage`. Raster tiles are `<img>` elements and an image cannot reach `localStorage`, so the pictures
  come from OpenStreetMap and the code does not.
- **The coordinates stay the authoritative input and stay visible**, wired both ways: clicking the map writes
  the number fields, editing a number recentres the map. `ST_MakePoint` stores exactly those two numbers, so
  a picker that hid them would make a wrong point unfixable by hand.
- **A drag is not a click** — classified on pointerup by whether it moved more than 4px, or every pan would
  drop the pin wherever the finger came up.
- **Search is Nominatim, on submit only** — free and keyless, but its policy asks for at most a request a
  second. Biased with `countrycodes=uz`, because unbiased «Чиланзар» lands wherever the planet has the
  better-known match. A failure toasts and leaves the map alone.
- **The first draw has to wait for layout.** The picker is built before its form is attached, so the frame is
  0×0 on the first pass and centring against that width drops the point in the top-left corner. `draw()`
  reschedules on rAF with a bail-out, so a modal closed before layout does not leave it rescheduling forever.
- **The modal's action row is `position: sticky`** — the map makes this the one form tall enough to scroll,
  and a Save button that scrolls off the bottom is one people cannot find.

## How the panel is checked

A copy of the page with `fetch` stubbed from real `psql` output, driven by *clicking* (the panel's functions
sit in a closure, so a stub cannot call them by name), rendered in headless chrome at 1440 and 880 and read
back — against the live database and against stubbed `/api/admin/stats` payloads for an empty market and a
half-filled one, plus search, sort, the templates help modal, the pill's per-frame motion and the focus ring.

**What a screenshot cannot stand in for**: the live poll, a real upload, a sync, and signing in with a code.
