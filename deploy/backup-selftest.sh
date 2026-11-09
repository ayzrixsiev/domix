#!/usr/bin/env bash
#
# Proves deploy/backup.sh and deploy/restore.sh work - with no Cloudflare account, no credentials and
# nothing touched in production.
#
#   ./deploy/backup-selftest.sh
#
# **A directory stands in for the bucket.** rclone treats a path and a bucket the same way, so the
# scripts under test run their real code paths against `$TMP/remote` instead of R2; the only thing
# not exercised is Cloudflare itself. A throwaway database stands in for production's: the dump is
# taken from the local DB_URL read-only and restored into a fresh database, which is dropped again.
#
# What it proves, in this order:
#
#    1. a first night: the mirror equals the photo directory, and a dated dump lands.
#    2. the dump is ciphertext, and the wrong passphrase cannot open it.
#    3. a second night after a deletion: the mirror follows the server, **and the deleted file and
#       the previous bytes of an overwritten one are in that night's photo-changes/ folder** - which
#       is the whole reason the design is a mirror plus deltas rather than a plain sync.
#    4. retention: a folder and a dump dated 40 days back are pruned, the recent ones are not.
#    5. a restore of the photo mirror matches the server, file for file.
#    6. a restore of that night's changes brings the deleted photo back, byte for byte.
#    7. a restore of the database into an empty one reproduces every table, column, index and row
#       count - and every `image_path` in the restored database resolves to a restored file, which is
#       what "rebuild the market from the backup alone" actually means.
#    8. a half-configured backup refuses to run and writes nothing.
#    9. a failing run reports itself to the heartbeat url, and no log line or alert body anywhere
#       carries the passphrase, the bucket secret or the database password.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=backup-lib.sh
source "$REPO_ROOT/deploy/backup-lib.sh"

BACKUP="$REPO_ROOT/deploy/backup.sh"
RESTORE="$REPO_ROOT/deploy/restore.sh"

TMP=""
SINK_PID=""
SCRATCH_DB=""
PASSES=0

ok()   { printf '  ok    %s\n' "$*"; PASSES=$((PASSES + 1)); }
bad()  { printf '  FAIL  %s\n' "$*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
same() { [[ "$2" == "$3" ]] || bad "$1: expected [$3], got [$2]"; ok "$1"; }

finish() {
    local code=$?
    if [[ -n "$SINK_PID" ]]; then kill "$SINK_PID" 2>/dev/null || true; fi
    if [[ -n "$SCRATCH_DB" ]]; then
        psql --dbname="$SOURCE_DB" --quiet \
            --command="DROP DATABASE IF EXISTS \"$SCRATCH_DB\"" >/dev/null 2>&1 || true
    fi
    if [[ -n "$TMP" ]]; then rm -rf "${TMP:?}"; fi
    if (( code == 0 )); then
        printf '\nPASS - %d checks\n' "$PASSES"
    else
        printf '\nFAILED\n' >&2
    fi
}
trap finish EXIT

# ---------------------------------------------------------------------------- the workspace

# the real .env, read for one thing only: a database to dump. **the test's own environment file
# carries nothing else**, so a .env holding live R2 credentials cannot drag them into this run.
load_env_file "$REPO_ROOT/.env"
require_tools rclone pg_dump pg_restore psql openssl curl python3
[[ -n "${DB_URL:-}" ]] || bad "DB_URL is not set - this test needs a local database to dump"
SOURCE_DB="$DB_URL"

TMP="$(mktemp -d /var/tmp/domix-selftest.XXXXXX)"
mkdir -p "$TMP/remote" "$TMP/disk" "$TMP/restored-photos" "$TMP/restored-changes"

printf '%s\n' "selftest-$(openssl rand -hex 16)" > "$TMP/pass"
chmod 600 "$TMP/pass"
printf 'DB_URL=%s\n' "$SOURCE_DB" > "$TMP/env"
chmod 600 "$TMP/env"

# the real photo directory, copied: this test deletes and overwrites files, and the catalogue every
# seeded row points at is not a thing to experiment on
SRC_PHOTOS="${IMAGES_DIR:-$REPO_ROOT/images}"
if [[ -d "$SRC_PHOTOS" ]] && [[ -n "$(find "$SRC_PHOTOS" -type f -print -quit)" ]]; then
    cp -a "$SRC_PHOTOS/." "$TMP/disk/"
else
    bad "no photos in $SRC_PHOTOS - nothing to mirror"
fi
PHOTOS="$TMP/disk"

# a local sink for the dead man's switch, so the success ping and the failure post are asserted
# rather than assumed
SINK_LOG="$TMP/heartbeat.log"
: > "$SINK_LOG"
python3 -I - "$SINK_LOG" 28123 <<'PY' &
import http.server, sys
log = open(sys.argv[1], "a", buffering=1)
class Sink(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length") or 0)).decode("utf-8", "replace")
        log.write("%s %s\n" % (self.path, body.replace("\n", " ")))
        self.send_response(200)
        self.send_header("content-length", "2")
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *args):
        pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[2])), Sink).serve_forever()
PY
SINK_PID=$!
HEARTBEAT="http://127.0.0.1:28123/domix-selftest"
for _ in 1 2 3 4 5 6 7 8 9 10; do
    curl --silent --max-time 1 --data-raw probe "$HEARTBEAT" >/dev/null 2>&1 && break
    sleep 0.2
done
[[ -s "$SINK_LOG" ]] || bad "the heartbeat sink did not start on port 28123"
: > "$SINK_LOG"

TODAY="$(date +%F)"
NIGHT1="$(date -d "$TODAY -1 day" +%F)"
NIGHT2="$TODAY"
ANCIENT="$(date -d "$TODAY -40 days" +%F)"

# every run of the scripts under test goes through here: a clean environment, the test's own env
# file, and the directory standing in for the bucket. the log is kept for the credential scan.
LOG_INDEX=0
run_backup() {
    LOG_INDEX=$((LOG_INDEX + 1))
    local log="$TMP/backup-$LOG_INDEX.log"
    local rc=0
    env DOMIX_ENV_FILE="$TMP/env" \
        IMAGES_DIR="$PHOTOS" \
        BACKUP_DEST_DIR="$TMP/remote" \
        BACKUP_PASSPHRASE_FILE="$TMP/pass" \
        BACKUP_HEARTBEAT_URL="$HEARTBEAT" \
        BACKUP_R2_ACCOUNT_ID="" BACKUP_R2_ACCESS_KEY_ID="" \
        BACKUP_R2_SECRET_ACCESS_KEY="" BACKUP_R2_BUCKET="" \
        "$@" "$BACKUP" >"$log" 2>&1 || rc=$?
    LAST_LOG="$log"
    return "$rc"
}

run_restore() {
    LOG_INDEX=$((LOG_INDEX + 1))
    local log="$TMP/restore-$LOG_INDEX.log"
    local rc=0
    env DOMIX_ENV_FILE="$TMP/env" \
        BACKUP_DEST_DIR="$TMP/remote" \
        BACKUP_PASSPHRASE_FILE="$TMP/pass" \
        BACKUP_R2_ACCOUNT_ID="" BACKUP_R2_ACCESS_KEY_ID="" \
        BACKUP_R2_SECRET_ACCESS_KEY="" BACKUP_R2_BUCKET="" \
        "$RESTORE" "$@" >"$log" 2>&1 || rc=$?
    LAST_LOG="$log"
    return "$rc"
}

remote_files() { (cd "$TMP/remote" && find . -type f | sort); }
identical() { rclone --config "" check "$1" "$2" --checksum >/dev/null 2>&1; }

# ---------------------------------------------------------------------------- 1. the first night

step "a first night"
run_backup BACKUP_DATE="$NIGHT1" || { cat "$LAST_LOG"; bad "the first backup failed"; }

[[ -f "$TMP/remote/db/domix-$NIGHT1.dump.enc" ]] || bad "no dump for $NIGHT1"
ok "db/domix-$NIGHT1.dump.enc is there"

identical "$PHOTOS" "$TMP/remote/photos" || bad "the mirror does not match the photo directory"
ok "the mirror matches every file on disk ($(find "$PHOTOS" -type f | wc -l) photos)"

same "nothing was deleted, so no changes were filed" \
    "$(find "$TMP/remote/$PHOTO_CHANGES" -type f 2>/dev/null | wc -l)" "0"

same "the success ping reached the dead man's switch" \
    "$(grep -c '^/domix-selftest ' "$SINK_LOG")" "1"

# ---------------------------------------------------------------------------- 2. the dump is opaque

step "the dump cannot be read without the passphrase"
# PGDMP is the first five bytes of every custom-format dump; finding it means the upload is plaintext
if head -c 4096 "$TMP/remote/db/domix-$NIGHT1.dump.enc" | grep -qa 'PGDMP'; then
    bad "the uploaded dump is not encrypted"
fi
ok "the uploaded dump carries no pg_dump header"

printf 'not-the-passphrase\n' > "$TMP/wrong-pass"
chmod 600 "$TMP/wrong-pass"
if openssl enc -d "${CIPHER[@]}" -pass "file:$TMP/wrong-pass" \
    -in "$TMP/remote/db/domix-$NIGHT1.dump.enc" -out /dev/null 2>/dev/null; then
    bad "the wrong passphrase decrypted the dump"
fi
ok "the wrong passphrase is refused"

openssl enc -d "${CIPHER[@]}" -pass "file:$TMP/pass" \
    -in "$TMP/remote/db/domix-$NIGHT1.dump.enc" -out "$TMP/night1.dump" 2>/dev/null \
    || bad "the right passphrase did not open the dump"
pg_restore --list "$TMP/night1.dump" >/dev/null || bad "the decrypted dump is not a pg dump"
ok "the right passphrase opens it and pg_restore reads its table of contents"

# ---------------------------------------------------------------------------- 3. a deletion survives

step "a second night, after a deletion on the server"
# sed -n 1p rather than `head -1`: head closes the pipe on its first line, and under `set -o
# pipefail` the SIGPIPE that kills sort takes the whole test with it
DELETED="$(cd "$PHOTOS" && find . -type f -name '*_thumb.jpg' -printf '%P\n' | sort | sed -n 1p)"
OVERWRITTEN="$(cd "$PHOTOS" && find . -type f -name '*.jpg' ! -name '*_thumb.jpg' -printf '%P\n' | sort | sed -n 1p)"
[[ -n "$DELETED" && -n "$OVERWRITTEN" ]] || bad "the photo directory has no jpegs to work with"

cp "$PHOTOS/$DELETED" "$TMP/deleted-original"
cp "$PHOTOS/$OVERWRITTEN" "$TMP/overwritten-original"
rm -f "${PHOTOS:?}/${DELETED:?}"
printf 'a different photo entirely' > "$PHOTOS/$OVERWRITTEN"
mkdir -p "$PHOTOS/shops/uploads/ff"
printf 'a photo an owner uploaded today' > "$PHOTOS/shops/uploads/ff/ffnew.jpg"

run_backup BACKUP_DATE="$NIGHT2" || { cat "$LAST_LOG"; bad "the second backup failed"; }

identical "$PHOTOS" "$TMP/remote/photos" || bad "the mirror did not follow the server"
ok "the mirror followed the server: the new photo is in, the deleted one is out"

cmp -s "$TMP/deleted-original" "$TMP/remote/$PHOTO_CHANGES/$NIGHT2/$DELETED" \
    || bad "the deleted photo is not in $PHOTO_CHANGES/$NIGHT2 - a plain sync would have lost it"
ok "the deleted photo is kept in $PHOTO_CHANGES/$NIGHT2, byte for byte"

cmp -s "$TMP/overwritten-original" "$TMP/remote/$PHOTO_CHANGES/$NIGHT2/$OVERWRITTEN" \
    || bad "the previous bytes of the overwritten photo were not kept"
ok "the overwritten photo's previous bytes are kept too"

same "only what changed is in that folder" \
    "$(find "$TMP/remote/$PHOTO_CHANGES/$NIGHT2" -type f | wc -l)" "2"

# ---------------------------------------------------------------------------- 4. retention

step "retention keeps 30 days and no more"
mkdir -p "$TMP/remote/$PHOTO_CHANGES/$ANCIENT" "$TMP/remote/$PHOTO_CHANGES/keep-me-by-hand"
printf 'old' > "$TMP/remote/$PHOTO_CHANGES/$ANCIENT/old.jpg"
printf 'old' > "$TMP/remote/db/domix-$ANCIENT.dump.enc"
printf 'put here by a person' > "$TMP/remote/$PHOTO_CHANGES/keep-me-by-hand/note.txt"

run_backup BACKUP_DATE="$NIGHT2" || { cat "$LAST_LOG"; bad "the third backup failed"; }

[[ ! -d "$TMP/remote/$PHOTO_CHANGES/$ANCIENT" ]] || bad "$ANCIENT was not pruned"
[[ ! -f "$TMP/remote/db/domix-$ANCIENT.dump.enc" ]] || bad "the $ANCIENT dump was not pruned"
ok "a folder and a dump dated $ANCIENT are gone"

[[ -d "$TMP/remote/$PHOTO_CHANGES/$NIGHT2" && -f "$TMP/remote/db/domix-$NIGHT1.dump.enc" ]] \
    || bad "a recent backup was pruned"
ok "$NIGHT1 and $NIGHT2 are untouched"

[[ -f "$TMP/remote/$PHOTO_CHANGES/keep-me-by-hand/note.txt" ]] \
    || bad "a folder whose name is not a date was deleted"
grep -q "keep-me-by-hand is not a date" "$LAST_LOG" || bad "no warning about the undated folder"
ok "a folder whose name is not a date is left alone, with a warning in the log"

# ---------------------------------------------------------------------------- 5-6. photo restores

step "restoring the photos"
run_restore photos "$TMP/restored-photos" || { cat "$LAST_LOG"; bad "the photo restore failed"; }
diff <(cd "$PHOTOS" && find . -type f | sort) <(cd "$TMP/restored-photos" && find . -type f | sort) >/dev/null \
    || bad "the restored directory holds different files from the server's"
identical "$PHOTOS" "$TMP/restored-photos" || bad "the restored photos differ from the server's"
ok "$(find "$TMP/restored-photos" -type f | wc -l) photos restored, every byte identical"

step "undoing the deletion"
run_restore changes "$NIGHT2" "$TMP/restored-changes" || { cat "$LAST_LOG"; bad "the changes restore failed"; }
cmp -s "$TMP/deleted-original" "$TMP/restored-changes/$DELETED" \
    || bad "the deleted photo did not come back"
ok "the photo deleted on the server comes back out of $PHOTO_CHANGES/$NIGHT2"

# ---------------------------------------------------------------------------- 7. the database restore

step "restoring the database into an empty one"
SCRATCH_DB="domix_selftest_$$"
read -r SRC_COLLATE SRC_CTYPE < <(psql --dbname="$SOURCE_DB" --tuples-only --no-align --field-separator=' ' \
    --command="select datcollate, datctype from pg_database where datname = current_database()")
psql --dbname="$SOURCE_DB" --quiet \
    --command="CREATE DATABASE \"$SCRATCH_DB\" TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE '$SRC_COLLATE' LC_CTYPE '$SRC_CTYPE'" \
    || bad "cannot create a scratch database"

base="${SOURCE_DB%%\?*}"
query=""
[[ "$SOURCE_DB" == *\?* ]] && query="?${SOURCE_DB#*\?}"
TARGET_DB="${base%/*}/$SCRATCH_DB$query"

run_restore db "$NIGHT2" "$TARGET_DB" || { cat "$LAST_LOG"; bad "the database restore failed"; }
ok "pg_restore finished with no ignored errors"

# structure, not only row counts: a restore that dropped an index is a market whose home screen times
# out, and one that dropped a column is an api that 500s on its first request
columns() {
    psql --dbname="$1" --tuples-only --no-align --field-separator='|' --command="
        select table_name, column_name, data_type, is_nullable, coalesce(column_default, '-')
        from information_schema.columns where table_schema = 'public' order by 1, 2"
}
indexes() {
    psql --dbname="$1" --tuples-only --no-align --field-separator='|' --command="
        select indexname, indexdef from pg_indexes where schemaname = 'public' order by 1"
}
diff <(columns "$SOURCE_DB") <(columns "$TARGET_DB") >"$TMP/columns.diff" \
    || { head -20 "$TMP/columns.diff"; bad "the restored schema differs"; }
ok "every table and column matches ($(columns "$TARGET_DB" | wc -l) columns)"
diff <(indexes "$SOURCE_DB") <(indexes "$TARGET_DB") >"$TMP/indexes.diff" \
    || { head -20 "$TMP/indexes.diff"; bad "the restored indexes differ"; }
ok "every index matches ($(indexes "$TARGET_DB" | wc -l) indexes)"

counts_query="$(psql --dbname="$SOURCE_DB" --tuples-only --no-align --command="
    select string_agg(format('select %L as t, count(*) as c from public.%I', relname, relname), ' union all ' order by relname)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'")"
row_counts() { psql --dbname="$1" --tuples-only --no-align --field-separator='|' --command="$counts_query" | sort; }
diff <(row_counts "$SOURCE_DB") <(row_counts "$TARGET_DB") >"$TMP/rows.diff" \
    || { head -20 "$TMP/rows.diff"; bad "the restored row counts differ"; }
ok "every table has the same number of rows ($(row_counts "$TARGET_DB" | awk -F'|' '{s+=$2} END {print s}') in total)"

# **the check that makes the two halves one backup.** image_path is relative and the mirror's keys are
# the same strings: if this fails, a restore is a catalogue of blank tiles.
step "the restored database and the restored photos agree"
absent=0
checked=0
while read -r rel; do
    [[ -n "$rel" ]] || continue
    # only paths the server actually had a file for: a backup carries what exists, it cannot invent a
    # photo that a row points at and the disk never held
    [[ -f "$PHOTOS/$rel" ]] || continue
    checked=$((checked + 1))
    [[ -f "$TMP/restored-photos/$rel" ]] || absent=$((absent + 1))
done < <(psql --dbname="$TARGET_DB" --tuples-only --no-align --command="
    select distinct image_path from products where image_path is not null
    union select distinct image_path from product_templates where image_path is not null")
(( checked > 0 )) || bad "no image_path in the restored database to check"
same "$checked image paths from the restored database resolve to restored files" "$absent" "0"

# ---------------------------------------------------------------------------- 8. refusals

step "a half-configured backup refuses to run"
before="$(remote_files)"
refuses() {
    local what="$1"; shift
    if run_backup "$@"; then bad "$what: the backup ran anyway"; fi
    grep -q "FAILED" "$LAST_LOG" || bad "$what: no reason given"
    same "$what" "$(remote_files)" "$before"
}
refuses "no destination at all" BACKUP_DEST_DIR=""
refuses "three of the four bucket values" BACKUP_DEST_DIR="" \
    BACKUP_R2_ACCOUNT_ID="acct" BACKUP_R2_ACCESS_KEY_ID="key" BACKUP_R2_SECRET_ACCESS_KEY="shhh"
refuses "a bucket and a local directory at once" \
    BACKUP_R2_ACCOUNT_ID="acct" BACKUP_R2_ACCESS_KEY_ID="key" \
    BACKUP_R2_SECRET_ACCESS_KEY="shhh" BACKUP_R2_BUCKET="bucket"
refuses "no passphrase" BACKUP_PASSPHRASE_FILE=""
refuses "a passphrase file that is not there" BACKUP_PASSPHRASE_FILE="$TMP/nope"
cp "$TMP/pass" "$TMP/pass-readable"
chmod 644 "$TMP/pass-readable"
refuses "a passphrase anyone on the box can read" BACKUP_PASSPHRASE_FILE="$TMP/pass-readable"
refuses "nowhere to report to" BACKUP_HEARTBEAT_URL=""

# ---------------------------------------------------------------------------- 9. a loud failure

step "a failing run says so, out loud"
: > "$SINK_LOG"
if run_backup DB_URL="postgres://nobody:nothing@127.0.0.1:1/nothing"; then
    bad "a backup with an unreachable database reported success"
fi
ok "an unreachable database fails the run"
grep -q '^/domix-selftest/fail ' "$SINK_LOG" || bad "the failure was not reported to the heartbeat url"
grep -q 'dumping the database' "$SINK_LOG" || bad "the alert does not name the step that failed"
ok "the failure reached the dead man's switch at /fail, naming the step"

step "nothing leaked into a log or an alert"
secret="$(cat "$TMP/pass")"
db_password="$(sed -n 's|^postgres\(ql\)\?://[^:]*:\([^@]*\)@.*|\2|p' <<<"$SOURCE_DB")"
for file in "$TMP"/backup-*.log "$TMP"/restore-*.log "$SINK_LOG"; do
    ! grep -qF -- "$secret" "$file" || bad "the passphrase is in $(basename "$file")"
    ! grep -qF -- "shhh" "$file" || bad "a bucket secret is in $(basename "$file")"
    if [[ -n "$db_password" ]]; then
        ! grep -qF -- "$db_password" "$file" || bad "the database password is in $(basename "$file")"
    fi
done
ok "no passphrase, bucket secret or database password in any log or alert"
