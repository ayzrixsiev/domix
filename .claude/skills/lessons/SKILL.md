---
name: lessons
description: >
  Traps in Domix that cost a debugging session and leave no error behind — sqlc type inference,
  panics in goroutines, X-Forwarded-For behind a proxy, the shared Dart http client and dead
  sockets, Flutter list and provider pitfalls, Android package visibility, EXIF orientation. Use
  when something fails silently or inexplicably: a request that works on a laptop and not behind
  ngrok, a query sqlc refuses to compile, a callback that stops firing, a sideways photo.
---

# Traps that leave no error behind

## Go

- **Go has no goroutine-level crash isolation**: a panic in any background goroutine takes the whole
  process down, so every one of them needs its own `recover()`. `startBasketHistory` is the live
  example; `WithJSON` does the same for http handlers.
- **Match database errors with `errors.Is(err, pgx.ErrNoRows)`**, never on the message. String matching
  breaks silently when a driver rewords itself, and would send a "database is down" error into a
  `CreateUser` path as though the row simply did not exist.

## sqlc

- A data-modifying CTE needs an explicit `LEFT JOIN` or the generator infers non-nullability for rows
  that may not be there.
- Boolean expressions and inferences inside functions need an explicit cast (`::boolean`).
- **sqlc cannot compile a window function filtered from an outer `WHERE`.** Use `CROSS JOIN LATERAL`
  for "for each X, the first N of this ordered list", or loop in Go.

## Behind a proxy

Every request's socket address is the proxy's own, so a per-IP limiter keyed on it puts the whole
internet in one bucket. The caller's address is in `X-Forwarded-For`, but **only its last entry can be
trusted**: ngrok and nginx (`$proxy_add_x_forwarded_for`) *append* what they saw to whatever the caller
sent, so the first entry is attacker-chosen and reading it hands out a fresh bucket per request.
`ratelimit.ClientIP` reads the last entry, and only with `TRUST_PROXY=true` — which also makes the api
listen on `127.0.0.1`, so nothing can reach it around the proxy.

## Flutter network and lists

- **One http client, never `http.get()`.** package:http's top-level helpers build a client per call and
  close it after, so every request pays a fresh TCP + TLS handshake (~0.3 s from Tashkent to a German
  server). Everything goes through the shared `appHttpClient` in `core/network/api_client.dart`; a new
  call site reaching for `http.get()` quietly brings the handshake back.
- **Idle mobile connections leave dead sockets in the pool**, and a request that hits one throws
  "Connection closed before full header". The client closes idle connections after 15 s — before nginx
  or Go do — and `apiGet` retries once for whatever still slips through.
- **Never `shrinkWrap: true` on a product grid.** It lays out every child at once, firing up to a
  hundred image requests simultaneously and stalling the whole network pipeline.
- A `RefreshIndicator` needs a scrollable with `AlwaysScrollableScrollPhysics` inside a
  `ConstrainedBox`, or pull-to-refresh silently does nothing.
- **`IndexedStack` keeps every tab mounted and paints one.** Neither `build()` nor `initState()` signals
  a visibility change, so a tab that fetches on becoming visible needs an explicit flag passed in.
- **`flutter test` draws every glyph as a full em square**, so Cyrillic comes out ~2× its real width and
  the harness invents overflows that no phone has. Load a font first:
  `FontLoader('Roboto')..addFont(...)` over any system TTF with Cyrillic.
- `Provider.of` defaults to `listen: true`, which trips a framework assertion when called from a tap or
  event callback. **`listen: false` inside callbacks.**

## Native

- **Android 11+ package visibility** breaks every `url_launcher` call silently unless the manifest
  declares `<queries>` for the https and telephony intents.
- **Go's `image/jpeg` ignores EXIF orientation and re-encoding drops the tag**, so a portrait phone
  photo lands sideways on the server. The orientation is read out of the APP1 segment and the rotation
  applied **after** downscaling, which is where it is cheapest.
