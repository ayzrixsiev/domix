---
name: lessons
description: >
  Critical technical traps, platform quirks, concurrency pitfalls, and network gotchas 
  discovered during the development of Domix. Use when debugging mysterious crashes, 
  network failures, or native platform issues.
---

# Domix Hard-Won Lessons & Technical Traps

### Telegram & Authentication Guardrails
When integrating Telegram bots for authentication, we discovered several security and stability hazards. First, never blindly trust an incoming Telegram contact update; you must explicitly verify that `Contact.UserID == From.ID` to prevent malicious actors from spoofing phone numbers. Second, Go lacks goroutine-level crash isolation, meaning any panic in the webhook handler takes down the entire HTTP server—always wrap updates in `recover()` and perform strict nil-checks on `Message.From`. Finally, database error handling must use `errors.Is(err, pgx.ErrNoRows)` rather than string matching on error messages, which can silently break if the driver rewords its outputs.

### SQLC & Database Quirks
Our PostgreSQL queries compiled via `sqlc` carry specific type-inference traps. Data-modifying CTEs require an explicit `LEFT JOIN` to prevent the generator from incorrectly inferring non-nullability when dealing with incomplete data rows. Similarly, boolean expressions and type inferences inside functions need explicit casts like `::boolean`. Additionally, `sqlc` cannot compile window functions filtered from outer `WHERE` clauses, requiring multi-query loops in Go instead.

### Proxies & Rate Limiting
Behind a proxy (ngrok, nginx) every request's socket address is the proxy's own, so a per-IP limiter keyed on it puts the whole internet in one bucket. The caller's address is in `X-Forwarded-For`, but only its **last** entry can be trusted: ngrok and nginx (`$proxy_add_x_forwarded_for`) *append* what they saw to whatever the caller sent, so the first entry is attacker-chosen and reading it hands out a fresh bucket per request. `ratelimit.clientIP` reads the last entry, and only with `TRUST_PROXY=true` - which also makes the api listen on 127.0.0.1, so nothing can reach it around the proxy.

### Flutter Network & UI Performance Traps
* **One HTTP client, never `http.get()`:** package:http's top-level `http.get/post/...` build a new client per call and close it afterwards, so every request pays a fresh TCP + TLS handshake (~0.3 s from Tashkent to a German server). Every request goes through the shared `appHttpClient` in `core/network/api_client.dart`; a new call site reaching for `http.get()` quietly brings the handshake back.
* **Network Dead Sockets:** Idle mobile connections leave dead sockets in the shared client's pool. When a request hits one, it throws a "Connection closed before full header" exception. The client closes idle connections after 15 s, before nginx or Go do, and `apiGet` in `api_client.dart` retries once for whatever slips through.
* **The `shrinkWrap: true` Hazard:** Never use `shrinkWrap: true` on product grids[cite: 2]. It forces Flutter to lay out every single child at once, firing up to 100 network image requests simultaneously and completely stalling the app's network pipeline[cite: 2].
* **Android 11+ Package Visibility:** Android's package visibility rules break `url_launcher` silently unless explicit `<queries>` blocks for HTTPS and telephony intents are declared in the Android manifest[cite: 2].
* **RefreshIndicator Constraints:** A `RefreshIndicator` must always wrap a scrollable widget that uses `AlwaysScrollableScrollPhysics` and a `ConstrainedBox`, otherwise pull-to-refresh gestures break silently[cite: 2].
* **IndexedStack Visibility:** `IndexedStack` keeps all its child tabs mounted in memory while only painting one active tab[cite: 2]. Neither `build()` nor `initState()` signal visibility changes; you must pass explicit boolean states or use proper lifecycle flags to trigger data fetches[cite: 2].
* **Provider Context Crash:** `Provider.of<context>` defaults to `listen: true`, which immediately triggers a framework assertion crash if called inside a tap or event callback[cite: 2]. Always pass `listen: false` within callbacks[cite: 2].

### Image Processing & Exif Orientation
Go's standard `image/jpeg` library completely ignores EXIF orientation tags, and standard re-encoding drops them entirely. This causes portrait photos taken on mobile devices to appear sideways on the server. To fix this, we extract the orientation number directly from the image's APP1 segment and manually apply the rotation transform *after* downscaling, saving massive CPU overhead.