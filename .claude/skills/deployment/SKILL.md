---
name: deployment
description: >
  Shipping Domix: the upload keystore and the encrypted secrets vault, the production stack
  (Ubuntu VPS in Uzbekistan, nginx, Postgres, domix-app.uz), the nightly backup of the database and
  the photos into Cloudflare R2 and how to restore from it, Google Play's policy requirements, and
  the open list that still blocks a submission. Use when building a release artifact (`make apk`,
  `make release`), editing `frontend/android/`, `env.prod.json`, `key.properties`,
  `proguard-rules.pro` or the manifest, handling the keystore or `secrets.vault.enc`, setting up the
  server, nginx or the backups, restoring one, or answering "what is left before we can ship".
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

**The nightly backup's passphrase belongs in here too**, once the server exists: it is the only thing
that can open 30 days of database dumps, and keeping it solely on the machine the dumps exist to
replace is the one way to own a backup of nothing. See the backups section below.

---

## Still open before release

**The server is built, serving, and has signed a real person in.** On 2026-11-09 the founder
installed the production APK on a Redmi Note 9S and completed the Telegram handshake against
production: account created, session issued, role switched to shop owner, a plumbing shop seeded with
135 template products - no errors in the journal. What is left is the Play side.

**The one number that moved**: placing that single shop's address spent **27 geocoder calls**, because
the picker reverse-geocodes while the pin is dragged. Twelve testers doing the same is ~300 of the 990
a day. Fine now; the first thing to look at if the log ever says the budget is spent.

### Do these first

1. **Create the app in Play Console and start the closed test.** The developer account is bought and
   verified. A personal account created after 2023-11-13 needs **12 testers opted in for 14
   continuous days** - accepted the invite *and* installed, under the matching Google account;
   dropping to 11 restarts the 14 days. Production review then takes up to ~7 days. **The real
   calendar is 3 weeks minimum**, and it runs independently of everything else.
2. **Delete `DevicePreview` from `frontend/lib/main.dart`, then `make release`.** `env.prod.json`
   already points at `https://domix-app.uz/api/auth`. The wrapper is inert in a release build
   (`enabled: !kReleaseMode`), so this is about not shipping a development dependency, not a bug.

**The Play reviewer cannot sign in.** Codes are gone and the Telegram handshake needs a real Telegram
account. The founder decided on 2026-11-09 to declare it in the App access form and deal with a
rejection if one comes. The fallback, if asked for credentials: `PLAY_REVIEW_PHONE` and
`PLAY_REVIEW_CODE` still arm the code flow on the server - what is missing is a screen to type them
into, so re-add the phone+code screen behind a long-press on the onboarding logo and hand Google the
pair plus the gesture.

### How the server was actually built, 2026-11-09

The install order below was followed; these are the parts that differed from it and would be got
wrong again:

- **The Airnet image ships a broken apt source** - `deb file:///cdrom noble main` - and every
  `apt-get update` fails until that line is deleted from `/etc/apt/sources.list`.
- **Postgres came from PGDG, not Ubuntu.** Ubuntu 24.04 ships 16; development is on 18.6, and a dump
  restores into an older postgres only by accident. `apt.postgresql.org` `noble-pgdg`, then
  `postgresql-18`, `postgresql-18-postgis-3`.
- **Go came from the tarball.** `go.mod` asks for 1.26 and Ubuntu packages 1.22.
- **rclone must come from upstream, not apt.** Ubuntu's 1.60 answers every R2 upload with
  `501 Not Implemented` on the first attempt and only succeeds on rclone's retry - 558 errors a night
  for a backup that technically worked. 1.76 from `downloads.rclone.org` uploads clean in 8 seconds.
- **The repo is cloned over a read-only GitHub deploy key** (`~/.ssh/github` on the server, public
  half in the repo's Settings -> Deploy keys). The repository stays private and the server cannot
  push.
- **The timezone is `Asia/Tashkent`**, because `domix-backup.timer` fires on local time and names
  each night's objects after the local date.
- **ufw allows 22, 80 and 443 and nothing else.** Postgres and the api listen on loopback only, so
  this is a second lock rather than the first.

Four things the first real deploy found, all now fixed in the repo: the baseline migration carried a
**stale catalogue** whose `image_path` pointed at names no file has had since the photos were renamed
to content hashes; it also carried `schema_migrations`, `COMMENT ON EXTENSION` and psql `\restrict`
lines, each of which stops a migration or a restore dead; and the nightly dump included postgis's own
`spatial_ref_sys`, which a restore cannot write back.

### The production stack — bought, installed and live

Domain **`domix-app.uz`**, registered at Turn Cloud (my.tdc.uz), expires 2027-09-02. One host serves
everything, and there are no subdomains:

| host           | serves                                            | runs on                    |
| -------------- | ------------------------------------------------- | -------------------------- |
| `domix-app.uz` | the API, the web pages and every product photo    | one Ubuntu 24.04 VPS in UZ |

**Registrar and DNS are two different companies here.** Turn Cloud holds the registration. The zone
was being moved to Cloudflare for exactly one reason — R2's custom domain, so a bucket could serve
photos under `img.` — and **photos are not in a bucket any more, so that move buys nothing**: the
nightly backup reaches R2 over the S3 API with a key pair, which needs no zone, no subdomain and no
proxy. A zone already moved is fine where it is; nothing left depends on it.

**If the zone is in Cloudflare, the apex `A` record stays grey-clouded (DNS only).** Orange-clouding it
puts Cloudflare between the app and nginx, and then certbot's HTTP-01 challenge is answered by
Cloudflare instead of our server and renewal fails — months later, on an expired certificate, with
every request in the app refusing to connect.

**A plain VPS, not a container platform** (a small Ubuntu 24.04 box, ~$5/mo). Fly.io, Railway and Cloud
Run were rejected on four counts, all about *not migrating later*: a VPS is the most portable thing
there is (a move is rsync plus a dump restore, zero code changes); no platform has a region near
Tashkent; PostGIS is `apt install` on a VPS and a coin toss on managed Postgres; and **every backend
developer already knows how to SSH into Linux**, which matters the moment somebody is hired. The box
being *in* Uzbekistan is the other half of it: 5–15 ms to Tashkent instead of ~87 ms to Germany, and
the personal-data localisation rule stops being an argument to have (`docs-privacy.md` §11).

**Nginx + certbot in front of Go** (`deploy/nginx.conf`). Nginx takes 80/443, terminates TLS, serves
`/images/` straight off the disk, and forwards everything else to Go on 8080. **HTTPS is not a private
tunnel** — the API is public to everyone; it encrypts transit and proves the server owns the domain.
Access control is `RequireAuth`/`RequireAdmin` and the rate limiter, nothing else. Play rejects a
cleartext app, so this is not optional. **`TRUST_PROXY=true` goes into `.env` the moment anything
proxies the api, ngrok included** — without it every request looks like it came from the proxy and the
whole internet shares one bucket; with it the api reads the last `X-Forwarded-For` entry and listens on
`127.0.0.1` only, so nothing can reach it around the proxy. **The api refuses to boot unless the line
reads `true` or `false`**, because the wrong guess is silent. nginx answers `deny all` on `/admin` and
`/api/admin/` — see the `admin-panel` skill for the tunnel that replaces it. Run certbot as
`certbot --nginx -d domix-app.uz --redirect`, so port 80 answers nothing but a redirect.

**Photos live on the server's disk, and R2 is backup storage only.** The earlier plan served them from
a public bucket at `img.domix-app.uz`; that is reversed. Two reasons, in this order: a photo fetched
from inside the country is faster for everyone using the app, since ~99% of all requests are these
files; and the decoupling R2 was bought for — an owner's uploads not being hostage to one machine — is
what the nightly mirror in `deploy/backup.sh` now provides, without the photos being readable abroad.
Cloudflare is still in the picture, as the place the backup lands, and still does not sell `.uz`, so
the registration stays at Turn Cloud permanently.

Order: server → `A` record for the apex → Postgres (**with a UTF-8 locale**: the initial migration refuses
a database that cannot lowercase Cyrillic; and `CREATE EXTENSION postgis, pg_trgm` once as the `postgres`
superuser, since postgis is not a trusted extension and the migration run as the api's own role cannot
create it) → `/srv/domix/images` owned so the api can write and nginx
can read, with `images/` from the repo copied into it → nginx → certbot → fill in `.env`
(`IMAGES_DIR=/srv/domix/images`, `YANDEX_GEOCODER_KEY` and `YANDEX_SUGGEST_KEY` and both `TELEGRAM_BOT_*`
lines or the api will not start, `TRUST_PROXY=true`, and the `BACKUP_*` block below) → build the binary
and install `deploy/systemd/domix-api.service` (its header has the commands) → **register the bot's
webhook** (below) → **run `deploy/backup.sh` once by hand and watch it** → enable `domix-backup.timer` → point `env.prod.json` at
`https://domix-app.uz` → ship the `.aab`.

**Registering the webhook.** Until this runs, every sign-in opens the bot and nothing answers. It needs
the api up behind nginx with a real certificate — telegram refuses a self-signed one and any port but
443, 80, 88 or 8443 — and is run once, on the server, from the directory holding `.env`:

```bash
set -a; . ./.env; set +a
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d url=https://domix-app.uz/api/telegram/webhook \
  -d secret_token="$TELEGRAM_WEBHOOK_SECRET" \
  -d 'allowed_updates=["message"]'                     # answers {"ok":true,...}
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/getWebhookInfo"   # last_error_message is the diagnosis
```

**A bot has one webhook.** Pointing it at the ngrok tunnel to test from a laptop takes production's
sign-in down until it is pointed back, and the reverse. **Changing the secret means running `setWebhook`
again with the new one**, or every update is refused with a 401 and nobody can sign in. The command goes
through the shell, not a script in the repo, so the token is never written into a file history.

**Verify before buying:** that an international Visa/Mastercard is accepted — Cloudflare bills R2 that
way and Uzbek Humo/UzCard do not work abroad. Running cost ~$6–8/mo including the bucket.

### The server, and getting into it

**Bought and running.** One VPS at **Airnet** (Uzbekistan), chosen over Hetzner for latency to Tashkent:
5–15 ms instead of ~87 ms to Germany.

| | |
| --- | --- |
| public address | **95.182.119.72** (what `domix-app.uz` resolves to) |
| login | **`ubuntu`**, with sudo — there is no reason to log in as root |
| os | Ubuntu 24.04 LTS, x86_64 |
| size | 2 cores, 3.8 GB RAM, ~43 GB free disk |
| network | behind NAT: the box sees `10.10.21.26/30` on its own interface, **not** its public address |
| ports | 22, 80 and 443 reachable from outside — verified by listening on each and connecting in |

```bash
ssh ubuntu@95.182.119.72                        # a shell on the server
ssh -L 8081:127.0.0.1:8080 ubuntu@95.182.119.72 # the same, plus the admin panel on localhost:8081
```

**The password is not in this repo and must never be committed.** Ask the founder, or take it from
`secrets.vault.enc`. `sudo` on the server takes that same password.

**The NAT matters when reading configuration.** `ip addr` shows a private address, so anything that
needs the public one (nginx `server_name`, certbot, a firewall rule) is written from the table above,
not from what the box reports about itself.

**Password login is still on, decided deliberately for the first release**, and the box is therefore
being guessed at continuously — every public port 22 is, by scanners, within minutes of going online.
**ROADMAP: switch to a key pair and `PasswordAuthentication no`** once there are real owners' phone
numbers in that database. A key is a file on the laptop that never crosses the network and cannot be
guessed, and turning passwords off refuses every one of those attempts outright instead of letting them
keep trying. The order matters: generate the key, confirm it logs in, and only then disable passwords
— with passwords off, a lost private key means a locked-out server.

### The production `.env`

What the api reads, and what happens without it. **Fatal** stops the boot with the reason;
**silent** boots green and misbehaves.

| variable | production value | missing or wrong |
| --- | --- | --- |
| `DB_URL` | the local database | fatal |
| `JWT_SECRET` | `openssl rand -base64 48` | fatal if empty or under 32 bytes |
| `TRUST_PROXY` | `true` | fatal unless `true` or `false` |
| `YANDEX_GEOCODER_KEY`, `YANDEX_SUGGEST_KEY` | the two keys | fatal if empty; **a wrong key is silent** — every lookup 502s and the log says `http 403` |
| `TELEGRAM_BOT_TOKEN` | `@domix_manager_bot`'s token from BotFather | fatal if empty or malformed; **a revoked token is silent** — every sign-in opens the bot and its replies fail with `sendMessage answered 401` in the journal. Never in the app, never in a log line |
| `TELEGRAM_WEBHOOK_SECRET` | `openssl rand -hex 32` | fatal unless 32–256 of `A-Za-z0-9_-`; **disagreeing with the one given to `setWebhook` is silent** — every update is a 401 and `getWebhookInfo` shows it |
| `VERIFY_SENDER`, `TELEGRAM_GATEWAY_TOKEN` | empty | only the kept code flow reads them, and no screen calls it: empty picks the console sender with one WARNING at boot. Naming `telegram` without the token is fatal |
| `PLAY_REVIEW_PHONE`, `PLAY_REVIEW_CODE` | the founder has deferred this | fatal if one is set alone. They arm the code flow only, which the app no longer shows |
| `IMAGES_DIR` | `/srv/domix/images` | defaults to `../images`, which from the unit's working directory is the same path. Unwritable is fatal; **disagreeing with nginx's `alias` is silent** — green `/health`, blank tiles |
| `IMAGE_BASE_URL` | empty | wrong is silent: every photo url points elsewhere. The boot log prints the prefix |
| `PORT` | empty (8080) | anything else is a 502 on every request through nginx |
| `DB_MAX_CONNS`, `DB_MIN_CONNS` | empty (10, 2) | a value that is not a number silently falls back to the default |

`SUPPORT_EMAIL` is read by nothing: the address is a constant in `main.go`, so the policy and the app
cannot disagree. The `BACKUP_*` block is the backup's, below.

### The photo store

**Nothing here is a change still to make.** Photos are written to and served from this server's own
disk; `imagestore.Disk` is the only store there is, and the bucket-backed one was deleted with the
decision to keep photos in Uzbekistan. R2 holds their nightly backup and serves nothing. The mechanics
are in the `backend` skill.

- **The curated catalogue has to be on the server's disk**, `_thumb` files included —
  `images/shops/plumbing`, `universal` and `wood`. Every seeded row points at one, so a deployment with
  only `shops/uploads/` is a market where the only visible photos are the ones owners took themselves.
  The catalogue files are tracked in git; only `images/shops/uploads/` is ignored, so a checkout plus
  `cp -a images/. /srv/domix/images/` is the whole job.
- **`IMAGES_DIR` and nginx's `alias` are two halves of one setting.** When they disagree nothing says
  so: uploads answer 200, `/health` is green, every tile in the market is blank. **The boot log prints
  which store and url prefix are live** — the fastest answer to "why are there no photos".
- `IMAGE_BASE_URL` stays empty unless something in front serves `images/` under its own hostname. It
  renames the host in a url and nothing else; it cannot move a file.

### Nightly backups, and getting the data back

`deploy/backup.sh` runs once a night from `domix-backup.timer` and copies both irreplaceable datasets
into Cloudflare R2. `deploy/restore.sh` is the other half. `deploy/backup-selftest.sh` proves both
without an R2 account, against a directory standing in for the bucket — **run it after touching any of
this**; it is the only evidence the restore path works.

```
domix-backups/                 the bucket
  photos/                      the mirror: object keys identical to products.image_path
  photo-changes/2026-11-07/    only what was deleted or overwritten that night, kept 30 days
  db/domix-2026-11-07.dump.enc one encrypted pg_dump a night, kept 30 days
```

**Why a mirror plus dated deltas and not a plain sync.** A sync propagates deletion. An `rm -rf`, a bug
in the orphan sweep, or a stolen token running DELETE in a loop reaches the backup at 03:30 the same
night and erases the only other copy. `rclone sync --backup-dir` moves what the mirror is about to lose
into that night's folder instead, so a deletion is undone with `restore.sh changes <date> <dir>` for a
month afterwards. Thirty full copies would also fix it and cost thirty times the storage for data that
barely moves; the delta folder is empty on a night when nothing was deleted, which is most nights. That
asymmetry is the whole design.

**Why the dump is encrypted and the mirror is not.** The dump carries names, phone numbers, every
shop's address and every shopping list a customer has sent; R2 is abroad. So it is AES-256 before it
leaves the server, the same cipher `scripts/secrets.sh` uses, and the passphrase stays in the country.
The mirror holds shop-window photos of taps and plywood that the app shows to anybody, so encrypting it
would buy nothing and cost the ability to restore it with one `rclone copy`. **This only holds because
a waybill's photo is a `bytea` in its row and never a file in `imagestore`** — that invariant is what
keeps a customer's handwritten list, which can carry their name, inside the encrypted half. Breaking it
puts personal photos in a plaintext foreign bucket.

**The passphrase must not live only on the server.** It is what makes the dumps worthless to a
stranger — and worthless to us too if its only copy burns with the machine it protects: 30 days of
dumps become 30 days of noise. It belongs in `secrets.vault.enc` and on paper, like the keystore — **re-run
`./scripts/secrets.sh backup` after setting it**, because the vault is a snapshot.

**How it fails loudly.** Every step is checked and the run aborts non-zero with the step named. The
dump is decrypted and read back with `pg_restore` *before* it is uploaded, so a rotated passphrase is
found that night rather than during a restore, and the mirror's file count is compared with the disk's
afterwards. `BACKUP_HEARTBEAT_URL` is a dead man's switch (healthchecks.io's free tier is enough):
pinged on success, posted to `<url>/fail` on failure. **The missing ping is the part that matters** —
nothing on a dead, wedged or forgotten server can raise an alarm about itself, which is why the switch
is required configuration and the script refuses to run without it. A ping that fails is only a warning:
the backup did happen, and the switch alerts on silence anyway.

`.env`, alongside the keys the api already reads (`DB_URL`, `IMAGES_DIR`):

```
BACKUP_R2_ACCOUNT_ID=…        an R2 token with Object Read & Write on this bucket only
BACKUP_R2_ACCESS_KEY_ID=…     **not the api's R2_* keys** - those move the live photo store
BACKUP_R2_SECRET_ACCESS_KEY=…
BACKUP_R2_BUCKET=domix-backups
BACKUP_PASSPHRASE_FILE=/etc/domix/backup.pass   # mode 600, outside the repo
BACKUP_HEARTBEAT_URL=https://hc-ping.com/…
```

Anything missing or half-filled refuses to run rather than taking half a backup: three of the four
bucket values, no passphrase, a passphrase file anyone on the box can read, no heartbeat url, or
`BACKUP_DEST_DIR` set next to real credentials (that one would quietly back the server up onto its own
disk). None of it reaches `argv` — rclone's credentials and the database password are passed through
the environment, because `/proc/<pid>/cmdline` is world-readable and nginx runs as its own user on the
same box.

Install, on the server:

```bash
apt install rclone                            # the one new dependency
install -d -m 700 -o domix -g domix /etc/domix
openssl rand -base64 48 > /etc/domix/backup.pass
chown domix:domix /etc/domix/backup.pass && chmod 600 /etc/domix/backup.pass
cp deploy/systemd/domix-backup.* /etc/systemd/system/
systemctl daemon-reload && systemctl enable --now domix-backup.timer
systemctl start domix-backup.service          # the first run, watched:
journalctl -fu domix-backup
```

**The passphrase file has to be readable by the user in the unit** (`domix`), not only by root — the
unit deliberately does not run as root, and a root-owned key file is the first thing that makes the
first run refuse.

`Persistent=true` in the timer is what makes a missed night catch up: a server that was off at 03:30
runs the backup when it comes back instead of skipping the day in silence.

Restoring, from the bucket alone, on a machine with nothing on it:

```bash
./deploy/restore.sh list                                  # which nights exist
createdb -T template0 -E UTF8 --locale=C.UTF-8 domix_db   # postgis and pg_trgm installable, same major version
./deploy/restore.sh db 2026-11-07 "$DB_URL"               # refuses a database that still has rows
./deploy/restore.sh photos /srv/domix/images
./deploy/restore.sh changes 2026-11-07 /tmp/undelete      # one night's deletions, to undo one
```

**The two halves fit without touching a row**: `products.image_path` is relative and the mirror's keys
are the same strings, which is the thing the self-test checks last. Restore as a superuser connection —
the dump creates extensions — and `chown` the photo directory afterwards or nginx serves 403s.

**What is _not_ in there**: `.env`, the upload keystore and `key.properties`, which are
`secrets.vault.enc`'s job and are still copied off by hand. The server's own configuration is not
either; nginx, the units and the migrations are in this repo.

### Play policy — a listing is rejected without each of these

- **The public site is built**: `/`, `/privacy`, `/terms`, `/delete-account`, in ru, uz and en, served by the
  API (see the `admin-panel` skill). The Console takes `https://domix-app.uz/privacy` and
  `https://domix-app.uz/delete-account`.
- **App access instructions — open again, deferred by the founder.** Sign-in is now the Telegram bot only,
  and the app has no code screen, so the mechanism below cannot be reached from the app. It is kept as it
  is. What it was: `PLAY_REVIEW_PHONE` and `PLAY_REVIEW_CODE` arm one
  number whose six digits are fixed and never delivered, so a reviewer with no Telegram account can get past
  the login wall; otherwise the submission is refused as broken, one of the most common rejections for
  phone-verified apps. `auth.CodeManager.WithReviewAccount` is the whole of it, and the account it opens is
  an ordinary `customer`. **Set both or neither** — the api refuses to boot on half a configuration, because
  an armed-looking, unarmed deployment is discovered by a rejection weeks later. **Unset both once the review
  is over**: it is a fixed code on a known number. Fill the Console's **App access** section with that
  number, that code and a screen recording.
- **The Data Safety form.** Declare name, phone number, the store's address, product photos, shopping lists and their photos, and favourites —
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
- **Slow request bodies are closed, in `decodeJSONBody`.** `ReadHeaderTimeout` and `IdleTimeout` cover the
  headers; `ReadTimeout`/`WriteTimeout` are deliberately absent because they budget the whole request and
  would cut off a 6 MiB photo upload on 3G (**do not add them**). The body half is a per-read deadline in the
  one json helper, so the multipart upload — which reads its body elsewhere — keeps its unbounded time.
  `TestASlowBodyIsCutOffRatherThanHeldOpen` holds a real socket open to prove it.
- **There is no rating in this build**: the column was dropped. Lighting the star needs
  a `reviews` table.
- **Pricing a hundred products costs ~500 taps**, and under the all-or-nothing rule an owner who stops at 80
  of 100 publishes **nothing**. The fix is a quick-entry list where the keyboard stays up and Next jumps to
  the next unpriced row. **Deferred deliberately** — do it when a real shop owner gives up halfway.

### Infrastructure and operations

- **Backups run nightly at 03:30 Tashkent time and have been restored from once.** The bucket, the
  scoped R2 token, the healthchecks.io dead man's switch and the passphrase file are all in place;
  `restore.sh db <date> <url>` rebuilt the 283-row catalogue into a throwaway database on
  2026-11-09. **The passphrase also lives off the server**, because the file that holds it dies with
  the machine the backups exist to replace.
- **No error reporting.** When the app breaks on an owner's phone, nobody finds out. Structured server logs
  plus a crash reporter would turn "it doesn't work" into a stack trace.
- **Three Yandex budgets, not one**, each shown separately in the cabinet under «Подключенные
  продукты»: **API Геокодера** and **API Геосаджеста**, 1000 calls a day each, which the server spends
  and `geo_calls` counts (the `backend` skill has the guard and the bucket sizes), and **MapKit SDK, 1000
  unique users a day**, which the *app* spends and nothing on our side counts. Once the log says `the
  geocoder budget for today is spent`, lookups past the cache answer «Поиск адресов сейчас недоступен»
  until the window frees. **MapKit has no such message, and it is the one hit first.**
  - **The unit is a person, not a map load** (licence 6.2.3: unique users a day visiting the part of the
    app where MapKit is available). A session costs one unit the first time that person opens the app
    that day and nothing after. **The shell builds the map tab at launch and starts MapKit with it**, so
    in practice every Android user of the day counts, whether or not they press Карта.
  - **100 users a day** is a tenth of the licence. **1 000** is all of it. **10 000** is ten times over:
    the paid tiers are 5 000 DAU at 20 800 ₽/month and 20 000 DAU at 58 500 ₽/month (`reference-mapkit.md`).
  - **Going over is not a map that stops at user 1 001.** The terms describe no technical cut-off; they
    give Yandex the right to block the key without notice (6.7), and the free-use page says regular
    overruns are blocked with no right of restoration. **The paid plan has to be bought before the
    average crosses 1 000, not after the key is gone.** Starting MapKit only when Карта is first opened
    would count map users rather than app users — **considered and declined for launch**: it trades the
    map's warm start for a blank Карта tab while the map window is created and the first tiles arrive,
    estimated at half a second to a second and a half and **never measured on a real phone**. Measure it
    there before trading it away, and only trade it once the daily average actually approaches 1 000.
  - **Check all three in the cabinet in the first week of real traffic.**
- **Open: the free Geocoder licence may not cover this app at all.** The free terms
  (`yandex.ru/legal/maps_api`, published 2026-09-01) allow the Geocoder only "на сайтах или в приложениях,
  использующих Сервис JavaScript API Яндекс Карт" and its coordinates only for display through that
  service (6.6.1). Domix draws with MapKit, not the JavaScript API. Geosuggest's clause (6.4) carries no
  such condition. Separately, 5.1.6 forbids storing what the services return beyond a 30-day cache, and
  the free-use page names "save geocoder data into your own database" as the example — while
  `shops.address` keeps the picker's reverse-geocoded line for good.
  **Decided 2026-11-08: ship as it is and buy the commercial licence later.** The app is in closed
  testing with about a dozen people — founders, their families and some friends — so there is no
  marketing, no public user and nothing at stake in the exposure; the licence gets bought when there is
  funding, which is also when the MapKit tier gets bought. **This is a dated decision and not an
  oversight**, and it stops being the right one the day the app is marketed to strangers.
  The clean fix if it is ever wanted before then is to let an owner **type or edit** their own address
  and use the geocoder only to place the pin — what is stored is then a person's text, not Yandex's.
  That would also fix the separate bug where a failed reverse lookup saves `"41.29950, 69.24010"` as the
  shop's address with no way to correct it. **The address field stays as it is until that day.**
- **Nothing exposes `pool.Stat().EmptyAcquireCount()`** — the count of requests that waited for a connection,
  and the only evidence that would justify changing `DB_MAX_CONNS`. Ten lines behind a token-protected
  `/metrics`.
- **`ListShops` has no `LIMIT` and no bounding box**, so every launch fetches every shop (the map tab is
  built at launch). Measured 2026-11-08 at 54 shops: **19.4 KB of json, 3.1 KB gzipped**, ~360 bytes a
  shop. 500 shops is ~180 KB, 1 000 is ~360 KB (~70 KB on the wire). The bytes are not what breaks first:
  the phone decodes the whole list on the UI isolate and `DomixMap` re-adds every placemark on any change
  and walks all of them on every camera frame. **Revisit around 1 000–2 000 shops.** The 60s cache is not
  what is saving it — the query is 0.17 ms at 500 shops — it saves the pool when a crowd opens at once.
- **The trigger-maintained `shop_basket_index` is why the home screen is fast**, and the
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
- **No refresh token.** A token lives four months; a stolen one dies when its owner logs out or changes
  number, both of which bump `users.token_version` (`backend` skill). An owner who never does either keeps
  it alive until it expires.
