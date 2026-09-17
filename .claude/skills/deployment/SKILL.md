---
name: deployment
description: >
  Releasing Domix to Google Play — Android build config, release signing and the upload
  keystore, the adaptive launcher icon, Yandex MapKit setup and its Android build
  requirements, testing on a real device, secrets backup, and the open list of things that
  still block a Play submission. Use when building a release artifact (`make apk`,
  `make release`), editing anything under `frontend/android/`, touching `env.prod.json`,
  `key.properties`, `proguard-rules.pro` or the app manifest, working on MapKit integration
  or its Gradle/JDK requirements, sideloading to a test phone, handling the keystore or
  `secrets.vault.enc`, or answering "what is left before we can ship".
---

# Shipping Domix to Google Play

Release-specific. Day-to-day feature work does not need it.

**Two reference files, read only when the task is actually about them — do not load both by reflex:**

- `reference-android.md` — `applicationId`, the adaptive launcher icon, release signing, R8 /
  `proguard-rules.pro`, `env.json` vs `env.prod.json`, the no-text-scaling and portrait trades, and
  the full adb + MIUI setup for the Redmi test phone.
- `reference-mapkit.md` — MapKit Lite's licence, the five silent traps (`onStart`, weak listeners,
  off-screen pin rasterization, `visualKey`), the three MapKit-only things in `android/`, the merged
  permissions, and what the migration cost.

Everything below is the release itself: secrets, the production stack, and what is still open.

---

## The two irreplaceable files

`~/domix-upload-key.jks` and the repo-root `.env` cannot be regenerated. `scripts/secrets.sh` packs
both (plus `key.properties`) into `secrets.vault.enc` — AES-256, PBKDF2, 600k iterations:

```bash
./scripts/secrets.sh backup    # pack + encrypt
./scripts/secrets.sh restore   # decrypt back; never overwrites an existing file
./scripts/secrets.sh list      # contents, without unpacking
```

**Encryption is what makes an off-laptop copy possible, not paranoia.** A plain `.env` cannot go in
Drive or Telegram; an encrypted vault can go anywhere. A vault that stays on this laptop is worth
nothing — one dead SSD takes originals and copy together.

**The vault is NOT in git** (in `.gitignore`; the script's own output was corrected to match, was
stale). It was committed once (`f2ee5ff`, 2026-08-17), removed the same day, push force-rewound.
**Do not re-add it.** Git history is permanent and retroactive: `git rm` does not remove a committed
secret from clones, forks or backups. A leaked `JWT_SECRET` can be rotated at the cost of signing
every user out; a leaked `.jks` cannot be rotated at all.

**It is a snapshot, not a mirror:** re-run `backup` after every `.env` change — `DB_URL` and
`WEBHOOK_URL` both change the day the backend leaves ngrok. `restore` refuses to clobber an existing
file. The passphrase is not in the repo and not recoverable.

---

---

## Still open before release

**Nothing below is in progress.** The first three are ordered and gate everything else.

### Do these first

1. **Buy the Play developer account** ($25, one-time) and **start the closed test.** A personal
   account created after 2023-11-13 cannot apply for production until it has run a closed test with
   **12 testers opted in for 14 continuous days** (was 20 until 2024-12-11). "Opted in" means
   accepted the invite **and installed** under the matching Google account — invited-but-not-installed
   does not count, and dropping to 11 restarts the 14 days. Since 2026 Google also checks the testers
   genuinely *used* the app. Afterwards you apply for production access; review takes **up to ~7
   days**. So the real calendar is **3 weeks minimum**, and it runs independently of everything else
   — start it before the infrastructure work, not after.
2. **Copy `secrets.vault.enc` off this laptop.** The script has been run and verified once
   (2026-08-17), so the passphrase works — but the vault does not currently exist on disk, leaving
   `~/domix-upload-key.jks`, the repo-root `.env` and `android/key.properties` on **one laptop and
   nowhere else**. Re-running `backup` alone does not close it; it writes to the repo root. Passphrase
   on paper, off the laptop.
3. **Stand the production infrastructure up.** Decided 2026-08-21, nothing bought. `env.prod.json`
   still says `https://REPLACE_ME` and `make release` refuses until it doesn't. Android 9+ blocks
   cleartext HTTP, so an `http://` address fails every request silently in release. Nothing else can
   be tested end to end without it.

### The production stack — decided, not yet bought

Domain **`domix-api.uz`**, registered at eskiz.uz, expires 2027-04-19. It already reads as "api", so
the apex is the backend and there is exactly one subdomain:

| host               | serves                        | runs on       |
| ------------------ | ----------------------------- | ------------- |
| `domix-api.uz`     | the API and the two web pages | Hetzner VPS   |
| `img.domix-api.uz` | every product photo           | Cloudflare R2 |

**The domain's nameservers already point at Cloudflare** (`adele.ns.cloudflare.com`,
`sonny.ns.cloudflare.com`, confirmed by whois 2026-08-26) — set up by the friend who registered it,
so the zone lives in an existing Cloudflare account. **Get access to that account rather than
creating a new one**: a new account is issued a *different* NS pair, which then has to be re-entered
at eskiz and drags the domain through a propagation window for nothing.

**A plain VPS, not a container platform** (Hetzner CX22 / CAX11, ~€4–5/mo). Rejected Fly.io, Railway,
Cloud Run on four counts, all about *not migrating later*: a VPS is the most portable thing there is
(a move is rsync plus a dump restore, half a day, zero code changes); no platform has a region near
Tashkent; PostGIS is `apt install` on a VPS and a coin toss on managed Postgres; and **every backend
developer already knows how to SSH into Linux**, which matters the moment somebody is hired. The cost
— updates, certificates, backups, monitoring — is the founder's. At one small machine that is the
right trade.

**Latency to Tashkent ~87 ms** to Hetzner's German datacentre, measured 2026-08-21 with `mtr`. Fine
for a marketplace; mobile radio adds 30–80 ms anyway. A local Uzbek host would give 5–15 ms and is a
legitimate future move — **not worth agonising over, because moving between VPSes costs half a day
and no code.**

**Nginx + certbot in front of Go.** Nginx is a reverse proxy: it takes 80/443 from the internet,
terminates TLS, and forwards plain HTTP to Go on 8080. HTTPS is **not a private tunnel** — the API is
public to everyone; HTTPS only encrypts the transit and proves the server owns the domain. Access
control is `RequireAuth`/`RequireAdmin` and the rate limiter, nothing else. Play rejects a cleartext
app, so this is not optional.

**Cloudflare R2 for photos, chosen for decoupling.** On a VPS the disk persists, so photos-on-disk
would work; what R2 buys is that the one irreplaceable dataset (an owner's uploads — the database can
be restored from a dump, their photos cannot) stops being part of the machine and gets its backups
for free. **The migration is cheap now and expensive later** — today it is one code path with no data
behind it; in a year it is also a file move plus rewriting every path in the database.

**R2 is also the only reason Cloudflare is involved at all**: its custom-domain feature requires the
zone to be in Cloudflare. eskiz's own DNS would otherwise be fine. Cloudflare does **not** sell `.uz`,
so the registration stays at eskiz permanently.

Order: server → Cloudflare account access → `A` record for the apex → Postgres (with a UTF-8 locale:
migration `000002` refuses a database that cannot lowercase Cyrillic) and nginx (`deploy/nginx.conf`)
→ certbot → deploy the binary → R2 bucket and `img.` → **upload `photos/` to the bucket** → fill in
`.env` (`IMAGE_BASE_URL` **and** the four `R2_*` keys, or the api will not start; `TRUST_PROXY=true`)
→ point `env.prod.json` at `https://domix-api.uz` → ship the `.aab`.

**Verify before buying:** that an international Visa/Mastercard is accepted by Hetzner and
Cloudflare. Uzbek Humo/UzCard do not work abroad; Hetzner also takes PayPal and bank transfer.
Running cost ~$6–8/mo (server €4–5, R2 free under 10 GB then ~$0.015/GB, certificate free).

### The storage code is already written and dormant

**Built and tested 2026-08-21 — nothing here is a change still to make.** It runs on the disk path
today and switches to R2 when four variables are set. Root §7 has the mechanics.

`imagestore.Storage` has two implementations chosen once in `mustOpenPhotoStorage`: `Disk` (laptop,
every test, no network) and `R2` (production). Two files per photo — a 1000px master and a 400px
`_thumb`, the grid loading the thumbnail; that is ~99% of image traffic and turns a 100-tile
catalogue from ~15 MB into ~2.5 MB. Only the master's path is in the database; `ProductResponse`
sends both urls. `IMAGE_BASE_URL` is the host Go prepends — unset, everything is served from this
api's own `/static/products/`.

**Four things the deploy must get right, three of them silent:**

- **The curated catalogue has to go into the bucket too**, `_thumb` files included. `photos/universal`
  and `photos/plumbing` are **gitignored**, so they exist only on the founder's laptop. Every seeded
  row points at one, so a bucket with only `uploads/` is a market where the only visible photos are
  the ones owners took themselves. Regenerate thumbnails first if missing (root §7 has the `magick`
  loop).
  ```bash
  rclone copy photos/ r2:domix-photos/ --exclude 'uploads/**'
  ```
- **R2 without `IMAGE_BASE_URL` refuses to boot**, deliberately: photos would be written to the bucket
  and served from a disk that does not have them — `/health` green, uploads answering 200, every tile
  blank. **Three R2 keys out of four also refuses to boot.**
- **`img.domix-api.uz` must be R2's _public_ custom domain**, not the S3 endpoint. The S3 host wants a
  signature on every GET; `<img>` cannot sign.
- **`PRODUCT_IMAGES_DIR` still matters on R2** only for `/static/products/`, which nothing asks for
  once `IMAGE_BASE_URL` is set. The boot log prints which store and url prefix are in use — the
  fastest answer to "why are there no photos".

**Sweeping orphaned files is built too**, in the admin panel («Обзор» → «Файлы без товара», see the
`admin-panel` skill): it lists files _first_ and the database _second_, deletes only what is
unreferenced **and older than an hour**, and treats a master's path as claiming its `_thumb`. A
button rather than a cron job — at this scale the count is zero or single digits.

### Play policy — a listing is rejected without each of these

- **The account-deletion page** `/delete-account` is served by the API and `SUPPORT_EMAIL` is set
  (`domix.support@gmail.com`). Remaining: put the production URL in the Play Console.
- **App access instructions.** Login goes through a Telegram bot, so a reviewer without Telegram hits
  the login wall and rejects the submission as broken. Fill in the Console's **App access** section
  with a walkthrough and a screen recording — one of the most common rejections for phone-verified
  apps.
- **The Data Safety form.** Declare name, phone number, Telegram chat id, **approximate location**,
  and **in-app messages** (the support thread). A mismatch found later is a policy strike, not a
  correction.
- **Justify `ACCESS_FINE_LOCATION`** (see the MapKit permissions note).
- Content rating questionnaire, target audience, privacy policy URL — all Console forms, all needing
  the domain.

### Code and build

- **Run `make apk` once the domain exists, emulator closed.** `make apk-test` covers most of it and
  has run on the Redmi; what it cannot cover is the production address. `make apk` is also the only
  way to confirm the upload key signs a real artifact end to end.
- **Keep testing on the device**: pin rasterization, the teardrop's anchor, a tap opening the sheet,
  the camera listener surviving a GC, the location picker's address keeping step.
- **A slow request _body_ is unbounded in time on the two public POSTs.** `ReadHeaderTimeout` (10s)
  and `IdleTimeout` (120s) close the slowloris hole; `ReadTimeout`/`WriteTimeout` are deliberately
  absent because they budget the whole request and would cut off a 6 MiB photo upload on 3G (the
  comment above `srv` in `cmd/api/main.go` says so — **do not add them**). What remains: a caller can
  send valid headers, pass the guard, then feed the body one byte at a time forever.
  `http.MaxBytesReader` bounds the bytes, nothing bounds the time. The photo endpoint barely matters
  (behind `RequireAuth` and a per-account limiter). The real exposure is `POST /api/auth/init` and
  `POST /api/account-deletion/init`: public, body-carrying, and the login limiter counts _requests_,
  which an unfinished one never becomes. **Fix before going live**, per-handler:
  `http.NewResponseController(w).SetReadDeadline(time.Now().Add(…))`.
  **nginx closes it once it is in front**: `deploy/nginx.conf` buffers every body in full before Go
  sees it (`proxy_request_buffering` is on by default) and bounds the silence between reads, so the
  per-handler deadline only matters for as long as the api still sits behind ngrok.
- **Delete `DevicePreview`** — see `frontend/CLAUDE.md`, and read the note there before removing it a
  third time.
- **`shops.rating` is a stored column nothing writes** — root §6. Lighting the star needs a `reviews`
  table.
- **Pricing a hundred products costs ~500 taps**, and under the all-or-nothing rule an owner who
  stops at 80 of 100 publishes **nothing**. The fix is a quick-entry list where the keyboard stays up
  and Next jumps to the next unpriced row. **Deferred deliberately** — do it when a real shop owner
  gives up halfway.

### Infrastructure and operations

- **Database backups.** There is no `pg_dump` on any schedule. Every shop's catalogue is hand-typed
  by its owner and exists in exactly one place; losing it loses work real people did. **This ranks
  above every polish item on this list.**
- **No error reporting.** When the app breaks on an owner's phone, nobody finds out. Structured
  server logs plus a crash reporter would turn "it doesn't work" into a stack trace. The support
  inbox is the closest thing there is, and it needs the user to write in.
- **Nominatim** is the free public instance (~1 req/sec shared). The map looks addresses up **as the
  text is typed** (debounced 450 ms), which its policy forbids outright — a deliberate call
  (2026-09-13) for the investor demo, to be replaced by Yandex's own address search once that licence
  is bought. The risk is a block by `User-Agent`, i.e. every install at once. What the app does keep:
  answers cached for the session (`GeocodingService`), a `User-Agent` with a contact,
  «© OpenStreetMap contributors» under the results. MapKit **Lite** has no search, so the move means
  the paid MapKit/Search SDK or Yandex's HTTP geocoder.
- **Nothing exposes `pool.Stat().EmptyAcquireCount()`** — the count of requests that waited for a
  connection, and the only evidence that would justify changing `DB_MAX_CONNS`. Ten lines behind a
  token-protected `/metrics`.
- **`ListShops` has no `LIMIT` and no bounding box**, so opening the map fetches every shop.
  Irrelevant at 50–70; revisit around 1 000.
- **`shop_basket_index` was a plain view and is now a trigger-maintained table** (migration `000006`)
  — **fixed**, and the numbers are here because the shape of the problem recurs. As a view its
  `basket` CTE was referenced twice, a materialization barrier, so postgres could not push the
  category predicate down and every query touching it sequentially scanned every template product
  row; `GET /api/home` paid that five times. Measured at 500 shops / 50 k products:
  `ListBestOffersInCategory` 84.2 ms → **0.37 ms**, `ListShops` (the map) 10.4 ms → **0.17 ms**. The
  cost moved to the write that causes it — one owner retyping one price now recomputes that market,
  24 ms at 500 shops — which is the right side of the trade while reads outnumber price edits, and it
  is the number to watch if that ever stops being true. **The axis that hurts is still shop count,
  not user count**, and the remaining home-screen cost is now `ListShops` having no bound (below).
- **The glibc collation mismatch on the local database.** `domix_db` was created under glibc 2.43 and
  the OS now provides 2.44, so `CREATE DATABASE` from `template1` fails outright. The repair is
  `REINDEX DATABASE domix_db;` **and then** `ALTER DATABASE domix_db REFRESH COLLATION VERSION;` — in
  that order. Refreshing alone silences the warning while leaving text indexes possibly sorted by the
  old rules.
- **CORS is `Access-Control-Allow-Origin: *`, and that is still fine.** CORS is a browser rule, and
  the admin panel is served from the API's **own origin**, so its requests are not cross-origin and
  never consult the header. What the wildcard permits is another site's javascript calling this API —
  and every admin route requires an `Authorization` header, which a browser will not attach
  cross-origin on its own. **The day something authenticates with a cookie, this becomes urgent.**
- **No refresh token.** The user-existence check in `RequireAuth` covers deletion, but a _stolen_
  token belonging to a live account works until it expires. Revoking one without deleting the account
  needs a `token_version` column bumped on logout.
- **`TRUST_PROXY=true` goes into `.env` the moment the api is behind a proxy — ngrok included.**
  Without it every request looks like it came from the proxy and the whole internet shares one
  rate-limit bucket (20 requests/s for *all* users together, 1/s for all logins). With it the api reads
  the **last** `X-Forwarded-For` entry — the one ngrok/nginx appended — and listens on `127.0.0.1`
  only, so nothing can reach it around the proxy. It used to read the *first* entry, which the caller
  writes; fixed 2026-09-11.
