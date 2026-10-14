---
name: deployment
description: >
  Shipping Domix: the upload keystore and the encrypted secrets vault, the production stack
  (Hetzner VPS, nginx, Cloudflare R2, domix-api.uz), the R2 cutover, Google Play's policy
  requirements, and the open list that still blocks a submission. Use when building a release
  artifact (`make apk`, `make release`), editing `frontend/android/`, `env.prod.json`,
  `key.properties`, `proguard-rules.pro` or the manifest, handling the keystore or
  `secrets.vault.enc`, setting up the server or nginx, or answering "what is left before we can
  ship".
---

# Shipping Domix to Google Play

Release-specific. Day-to-day feature work does not need it.

**Two reference files — read only when the task is actually about them:**

- `reference-android.md` — `applicationId`, the adaptive launcher icon, release signing, R8 /
  `proguard-rules.pro`, `env.json` vs `env.prod.json`, and the adb + MIUI setup for the test phone.
- `reference-mapkit.md` — MapKit Lite's licence, its silent traps, the three MapKit-only things in
  `android/`, the merged permissions, and what the migration cost.

---

## The two irreplaceable files

`~/Main/domix-upload-key.jks` (the path `frontend/android/key.properties` must point at) and the repo-root
`.env` cannot be regenerated. `scripts/secrets.sh` packs both, plus `key.properties`, into
`secrets.vault.enc` — AES-256, PBKDF2:

```bash
./scripts/secrets.sh backup    # pack + encrypt
./scripts/secrets.sh restore   # decrypt back; never overwrites an existing file
./scripts/secrets.sh list      # contents, without unpacking
```

**Encryption is what makes an off-laptop copy possible, not paranoia.** A plain `.env` cannot go in Drive
or Telegram; an encrypted vault can go anywhere. A vault that stays on this laptop is worth nothing — one
dead SSD takes originals and copy together.

**The vault is NOT in git, and must not be re-added.** Git history is permanent and retroactive: `git rm`
does not remove a committed secret from clones, forks or backups. A leaked `JWT_SECRET` can be rotated at
the cost of signing every user out; a leaked `.jks` cannot be rotated at all.

**It is a snapshot, not a mirror**: re-run `backup` after every `.env` change — `DB_URL` changes the day
the backend leaves ngrok. The passphrase is not in the repo and not recoverable.

---

## Still open before release

**Nothing below is in progress.** The first three are ordered and gate everything else.

### Do these first

1. **Buy the Play developer account** ($25, one-time) and **start the closed test.** A personal account
   created after 2023-11-13 cannot apply for production until it has run a closed test with **12 testers
   opted in for 14 continuous days**. "Opted in" means accepted the invite **and installed** under the
   matching Google account — invited-but-not-installed does not count, and dropping to 11 restarts the 14
   days. Google also checks the testers genuinely *used* the app. Production review then takes up to ~7
   days. **The real calendar is 3 weeks minimum, and it runs independently of everything else — start it
   before the infrastructure work.**
2. **Copy `secrets.vault.enc` off this laptop.** The script has been run and verified once, so the
   passphrase works, but **the vault does not exist on disk right now**, leaving the keystore, the
   repo-root `.env` and `key.properties` on one laptop and nowhere else. Passphrase on paper, off the
   laptop.
3. **Stand the production infrastructure up.** `env.prod.json` still says `https://REPLACE_ME` and
   `make release` refuses until it does not. Android 9+ blocks cleartext HTTP, so an `http://` address
   fails every request silently in release. Nothing else can be tested end to end without it.

### The production stack — decided, not yet bought

Domain **`domix-api.uz`**, registered at eskiz.uz, expires 2027-04-19. It already reads as "api", so the
apex is the backend and there is exactly one subdomain:

| host               | serves                        | runs on       |
| ------------------ | ----------------------------- | ------------- |
| `domix-api.uz`     | the API and the web pages     | Hetzner VPS   |
| `img.domix-api.uz` | every product photo           | Cloudflare R2 |

**The domain's nameservers already point at Cloudflare** (`adele.ns.cloudflare.com`,
`sonny.ns.cloudflare.com`), set up by the friend who registered it, so the zone lives in an existing
Cloudflare account. **Get access to that account rather than creating a new one**: a new account is issued
a *different* NS pair, which has to be re-entered at eskiz and drags the domain through a propagation
window for nothing.

**A plain VPS, not a container platform** (Hetzner CX22 / CAX11, ~€4–5/mo). Fly.io, Railway and Cloud Run
were rejected on four counts, all about *not migrating later*: a VPS is the most portable thing there is (a
move is rsync plus a dump restore, zero code changes); no platform has a region near Tashkent; PostGIS is
`apt install` on a VPS and a coin toss on managed Postgres; and **every backend developer already knows how
to SSH into Linux**, which matters the moment somebody is hired. Latency to Tashkent is ~87 ms to Hetzner's
German datacentre — fine for a marketplace, where mobile radio adds 30–80 ms anyway. A local Uzbek host
would give 5–15 ms and is a legitimate future move; **not worth agonising over, because moving between
VPSes costs half a day and no code.**

**Nginx + certbot in front of Go** (`deploy/nginx.conf`). Nginx takes 80/443, terminates TLS, and forwards
plain HTTP to Go on 8080. **HTTPS is not a private tunnel** — the API is public to everyone; it encrypts
transit and proves the server owns the domain. Access control is `RequireAuth`/`RequireAdmin` and the rate
limiter, nothing else. Play rejects a cleartext app, so this is not optional. **`TRUST_PROXY=true` goes into
`.env` the moment anything proxies the api, ngrok included** — without it every request looks like it came
from the proxy and the whole internet shares one bucket; with it the api reads the last `X-Forwarded-For`
entry and listens on `127.0.0.1` only, so nothing can reach it around the proxy. nginx also needs
`deny all` on `/admin` and `/api/admin/` — see the `admin-panel` skill for the tunnel that replaces it.

**Cloudflare R2 for photos, chosen for decoupling.** On a VPS the disk persists, so photos-on-disk would
work; what R2 buys is that the one irreplaceable dataset — an owner's uploads, where the database can be
restored from a dump and their photos cannot — stops being part of the machine and gets its backups for
free. **The migration is cheap now and expensive later**: today it is one code path with no data behind it;
in a year it is also a file move plus rewriting every path in the database. **R2 is also the only reason
Cloudflare is involved at all** — its custom-domain feature requires the zone to be in Cloudflare.
Cloudflare does not sell `.uz`, so the registration stays at eskiz permanently.

Order: server → Cloudflare account access → `A` record for the apex → Postgres (**with a UTF-8 locale**:
migration `000002` refuses a database that cannot lowercase Cyrillic) and nginx → certbot → deploy the
binary → R2 bucket and `img.` → **upload `images/` to the bucket** → fill in `.env` (`IMAGE_BASE_URL` **and**
the four `R2_*` keys, or the api will not start; `TRUST_PROXY=true`) → point `env.prod.json` at
`https://domix-api.uz` → ship the `.aab`.

**Verify before buying:** that an international Visa/Mastercard is accepted by Hetzner and Cloudflare. Uzbek
Humo/UzCard do not work abroad; Hetzner also takes PayPal and bank transfer. Running cost ~$6–8/mo.

### The storage code is written and dormant

**Nothing here is a change still to make.** It runs on the disk path today and switches to R2 when the four
keys are set; `imagestore.Storage` has two implementations chosen once in `mustOpenPhotoStorage`. The
mechanics are in the `backend` skill.

**Four things the deploy must get right, three of them silent:**

- **The curated catalogue has to go into the bucket too**, `_thumb` files included — `images/shops/plumbing`,
  `universal` and `wood`. Every seeded row points at one, so a bucket holding only `shops/uploads/` is a
  market where the only visible photos are the ones owners took themselves. **Object keys must match
  `products.image_path` exactly**, so the copy starts one level above `shops/`:
  ```bash
  rclone copy images/ r2:domix-photos/ --exclude 'shops/uploads/**'
  ```
  (The catalogue files are tracked in git; only `images/shops/uploads/` is ignored.)
- **R2 without `IMAGE_BASE_URL` refuses to boot**, deliberately: photos would be written to the bucket and
  served from a disk that does not have them — `/health` green, uploads answering 200, every tile blank.
  **Three R2 keys out of four also refuses to boot.**
- **`img.domix-api.uz` must be R2's _public_ custom domain**, not the S3 endpoint. The S3 host wants a
  signature on every GET; `<img>` cannot sign.
- `IMAGES_DIR` still matters on R2 only for `/images/`, which nothing asks for once `IMAGE_BASE_URL` is set.
  **The boot log prints which store and url prefix are live** — the fastest answer to "why are there no
  photos".

### Play policy — a listing is rejected without each of these

- **The public site is built**: `/`, `/privacy`, `/terms`, `/delete-account`, in ru, uz and en, served by the
  API (see the `admin-panel` skill). The Console takes `https://domix-api.uz/privacy` and
  `https://domix-api.uz/delete-account`.
- **App access instructions — the mechanism is built.** `PLAY_REVIEW_PHONE` and `PLAY_REVIEW_CODE` arm one
  number whose six digits are fixed and never delivered, so a reviewer with no Telegram account can get past
  the login wall; otherwise the submission is refused as broken, one of the most common rejections for
  phone-verified apps. `auth.CodeManager.WithReviewAccount` is the whole of it, and the account it opens is
  an ordinary `customer`. **Set both or neither** — the api refuses to boot on half a configuration, because
  an armed-looking, unarmed deployment is discovered by a rejection weeks later. **Unset both once the review
  is over**: it is a fixed code on a known number. Fill the Console's **App access** section with that
  number, that code and a screen recording.
- **The Data Safety form.** Declare name, phone number, the store's address, product photos and favourites —
  **not device location**: the app never requests it. `docs-privacy.md` has the row-by-row answers. A
  mismatch found later is a policy strike, not a correction.
- **Justify `ACCESS_FINE_LOCATION`** — see the MapKit permissions note.
- **The policy exists twice**, `/privacy` and `privacy_policy.dart`, and
  `TestTheAppCarriesThePublishedPolicy` compares them line by line. `deploy/logrotate.conf` is what makes the
  policy's "90 days" true rather than a promise; read its header before installing, it collides with nginx's
  own rule.
- Content rating questionnaire and target audience are Console forms.
- **`docs-privacy.md` is the inventory behind all of this**: every SDK, every merged permission, every
  external host, the Data Safety answer per row. Re-run its manifest check after any MapKit upgrade.

### Code and build

- **Run `make apk` once the domain exists, emulator closed.** `make apk-test` covers everything a release
  build can get wrong except the production address, and has run on the test phone. `make apk` is also the
  only way to confirm the upload key signs a real artifact end to end.
- **Keep testing on the device**: pin rasterization, the teardrop's anchor, a tap opening the sheet, the
  camera listener surviving a GC, the location picker's address keeping step.
- **Delete `DevicePreview` before release** — the rule and the wrapper order are in the `frontend` skill.
- **A slow request _body_ is unbounded in time on the two public POSTs.** `ReadHeaderTimeout` and
  `IdleTimeout` close the slowloris hole; `ReadTimeout`/`WriteTimeout` are deliberately absent because they
  budget the whole request and would cut off a 6 MiB photo upload on 3G (**do not add them**). What remains:
  a caller can send valid headers, pass the guard, then feed the body one byte at a time forever.
  `http.MaxBytesReader` bounds the bytes, nothing bounds the time. The real exposure is
  `POST /api/auth/request-code` and `POST /api/account-deletion/request-code`: public, body-carrying, and the
  login limiter counts *requests*, which an unfinished one never becomes. **Fix per handler before going
  live**: `http.NewResponseController(w).SetReadDeadline(…)`. **nginx closes it once it is in front** —
  `deploy/nginx.conf` buffers every body in full before Go sees it and bounds the silence between reads
  (`client_body_timeout 30s`), so the per-handler deadline only matters while the api still sits behind ngrok.
- **There is no rating in this build**: the column was dropped in migration `000003`. Lighting the star needs
  a `reviews` table.
- **Pricing a hundred products costs ~500 taps**, and under the all-or-nothing rule an owner who stops at 80
  of 100 publishes **nothing**. The fix is a quick-entry list where the keyboard stays up and Next jumps to
  the next unpriced row. **Deferred deliberately** — do it when a real shop owner gives up halfway.

### Infrastructure and operations

- **Database backups.** There is no `pg_dump` on any schedule. Every shop's catalogue is hand-typed by its
  owner and exists in exactly one place; losing it loses work real people did. **This ranks above every
  polish item on this list.**
- **No error reporting.** When the app breaks on an owner's phone, nobody finds out. Structured server logs
  plus a crash reporter would turn "it doesn't work" into a stack trace.
- **Photon's public instance promises no speed** — measured at ~20 s after answering instantly a week
  earlier, which is why a typed lookup gives up after 4 s and falls back to «Найти» (the rule is in the
  `frontend` skill). If that becomes common: self-host Photon on the VPS (open source, an Uzbekistan extract
  is small, wants Java and ~1–2 GB RAM), take a keyed free tier (LocationIQ ~5 000/day, Geoapify ~3 000/day),
  or pay Yandex. All are OSM data, so «© OpenStreetMap contributors» stays under the results and in «О
  приложении».
- **Nothing exposes `pool.Stat().EmptyAcquireCount()`** — the count of requests that waited for a connection,
  and the only evidence that would justify changing `DB_MAX_CONNS`. Ten lines behind a token-protected
  `/metrics`.
- **`ListShops` has no `LIMIT` and no bounding box**, so opening the map fetches every shop. Irrelevant at
  50–70; revisit around 1 000.
- **The trigger-maintained `shop_basket_index` is why the home screen is fast** (migration `000006`), and the
  numbers are here because the shape of the problem recurs. As a view, its `basket` CTE was referenced twice
  — a materialization barrier — so postgres could not push the category predicate down and every query
  touching it sequentially scanned every template product row; `GET /api/home` paid that five times.
  Measured at 500 shops / 50 k products: `ListBestOffersInCategory` 84.2 ms → **0.37 ms**, `ListShops` (the
  map) 10.4 ms → **0.17 ms**. The cost moved to the write that causes it — one owner retyping one price
  recomputes that market, 24 ms at 500 shops — which is the right side of the trade while reads outnumber
  price edits, and **the number to watch if that ever stops being true. The axis that hurts is shop count,
  not user count.**
- **The glibc collation mismatch on the local database.** `domix_db` was created under an older glibc than
  the OS now provides, so `CREATE DATABASE` from `template1` fails outright. The repair is
  `REINDEX DATABASE domix_db;` **and then** `ALTER DATABASE domix_db REFRESH COLLATION VERSION;` — in that
  order. Refreshing alone silences the warning while leaving text indexes possibly sorted by the old rules.
- **The api sends no CORS headers at all**, deliberately: the app is a native client and both web pages call
  it same-origin. The day a browser on another origin needs this api, that is a decision to take then — and
  the day anything authenticates with a cookie instead of a bearer header, it becomes urgent.
- **No refresh token.** The user-existence check in `RequireAuth` covers deletion, but a *stolen* token
  belonging to a live account works until it expires. Revoking one without deleting the account needs a
  `token_version` column bumped on logout.
