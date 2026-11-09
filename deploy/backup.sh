#!/usr/bin/env bash
#
# Domix's nightly backup: the database and every product photo, into Cloudflare R2.
#
#   ./deploy/backup.sh      # one night's run - what domix-backup.timer calls
#
# WHAT IS IRREPLACEABLE HERE
#
# Two datasets, and only two. Every shop's catalogue was typed in by hand by its owner and every
# product photo was taken by them. Lose the VPS and the rest of this product is a `git clone` and an
# `apt install`; lose these two and work real people did is gone. So the bar is not "a copy exists"
# but **"the VPS is gone - rebuild the market from the bucket alone"**, which is what
# deploy/restore.sh does and deploy/backup-selftest.sh proves end to end.
#
# The database and the photos are one backup, not two: `products.image_path` holds a relative path
# and the bucket's object keys are byte-identical to it, so a restored dump and a restored mirror
# line up without rewriting a single row. Restoring one half alone is a market of blank tiles, or a
# pile of files nothing points at.
#
# PHOTOS: A MIRROR, PLUS A DATED FOLDER OF WHAT CHANGED THAT NIGHT
#
# `photos/` matches the server's photo directory. `photo-changes/<date>/` holds, for 30 days, only
# the files the mirror would otherwise have lost that night: the ones deleted or overwritten on the
# server since the last run.
#
# **A plain sync would be a liability rather than a backup.** It propagates deletion: an `rm -rf`, a
# bug in the orphan sweep, or a stolen token running DELETE in a loop reaches the backup at 03:30 the
# same night, and the only other copy of those photos was the one it just erased. Thirty full copies
# would also fix that, and cost thirty times the storage for data that barely moves. A mirror plus a
# month of dated deltas is the same month of undo for almost no storage, because the delta folder is
# empty on any night when nothing was deleted - which is most nights, and is the point.
#
# The mirror is not encrypted, deliberately: these are shop-window photos of taps and plywood,
# published to anyone who opens the app. The one photo set that *is* personal - a customer's
# photographed shopping list, which can carry their name or address - **lives in Postgres by design**
# and so travels inside the encrypted dump below, never in this mirror.
#
# DATABASE: A DATED DUMP, ENCRYPTED BEFORE IT LEAVES THE SERVER
#
# The dump carries names, phone numbers, every shop's address, and every shopping list a customer has
# sent. R2 is abroad. So it leaves as ciphertext and the passphrase stays here, in Uzbekistan, and on
# paper - which is also what the privacy policy promises about where readable personal data lives.
#
# Dumps are dated and kept 30 days rather than overwritten, because the failure to survive is not a
# dead disk; it is a bad migration or a wrong DELETE noticed a week later. Yesterday's dump of an
# already-broken database is worth nothing.
#
# IT HAS TO FAIL LOUDLY
#
# A backup job that quietly stopped two months ago is worse than none at all: it buys confidence it
# no longer earns. In order of what they catch:
#
#   * every step is checked, and any failure aborts the run non-zero with the step named.
#   * the dump is decrypted and read back with pg_restore *before* it is uploaded, and the mirror's
#     file count is compared with the disk's afterwards. A rotated passphrase or a half-finished
#     sync is then found tonight, in the journal, instead of during a restore.
#   * BACKUP_HEARTBEAT_URL is a dead man's switch (healthchecks.io, Cronitor, self-hosted): pinged on
#     success, posted to at <url>/fail on failure. **The missing ping is the part that matters** -
#     nothing running on a dead, wedged or forgotten server can raise an alarm about itself, so the
#     alarm has to come from the absence of a signal. That is why it is required configuration and
#     not an option.
#
# CONFIGURATION - all of it from the repo-root .env, none of it in this repo
#
#   DB_URL                        the database to dump (already set for the api)
#   IMAGES_DIR                    the photo directory  (already set for the api; default ../images)
#   BACKUP_R2_ACCOUNT_ID          the backup bucket. **deliberately NOT the api's R2_* keys** - those
#   BACKUP_R2_ACCESS_KEY_ID       four move the live *photo store* into a bucket, and photos are
#   BACKUP_R2_SECRET_ACCESS_KEY   served off this server's own disk now. Filling the api's keys to
#   BACKUP_R2_BUCKET              "switch on R2 backups" would relocate every photo in the market.
#   BACKUP_PASSPHRASE_FILE        file holding the dump passphrase, mode 600, outside the repo
#   BACKUP_HEARTBEAT_URL          dead man's switch, pinged on success and on failure
#
# Two overrides let this be proven without touching production - see backup-selftest.sh:
#
#   BACKUP_DEST_DIR               a local directory standing in for the bucket. refuses to run
#                                 alongside the R2 credentials, so it cannot sit unnoticed in a real
#                                 deployment backing the server up onto its own disk.
#   BACKUP_DATE                   the date this run files itself under; default today.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=backup-lib.sh
source "$REPO_ROOT/deploy/backup-lib.sh"

readonly RETENTION_DAYS=30

# what the failure alert says this run was doing. coarse on purpose, and never the error text: a
# pg_dump or rclone failure quotes the connection string or the endpoint, and this one string is the
# only thing the script sends to a third-party monitor.
STEP="starting up"

STAGING=""

# the EXIT trap rather than ERR: it catches `die`, anything `set -e` aborts on, and a signal, none of
# which ERR alone covers.
on_exit() {
    local code=$?
    if [[ -n "$STAGING" ]]; then rm -rf "${STAGING:?}"; fi
    if (( code != 0 )); then heartbeat_fail "$code"; fi
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

main() {
    preflight
    local date_stamp="${BACKUP_DATE:-$(date +%F)}"

    backup_database "$date_stamp"
    backup_photos "$date_stamp"
    prune_old_backups

    STEP="reporting success"
    heartbeat_ok
    log "done - the database and $PHOTOS_DIR are in $(redact "$DEST")"
}

preflight() {
    STEP="checking the configuration"
    load_env_file "${DOMIX_ENV_FILE:-$REPO_ROOT/.env}"
    require_tools rclone pg_dump pg_restore openssl curl

    [[ -n "${DB_URL:-}" ]] || die "DB_URL is not set - there is nothing to dump"
    split_db_url "$DB_URL"

    PHOTOS_DIR="${IMAGES_DIR:-$REPO_ROOT/images}"
    [[ -d "$PHOTOS_DIR" ]] || die "IMAGES_DIR ($PHOTOS_DIR) is not a directory"

    resolve_destination
    require_passphrase

    [[ -n "${BACKUP_HEARTBEAT_URL:-}" ]] \
        || die "BACKUP_HEARTBEAT_URL is not set - a backup nobody is told about is not a backup. Point it at a dead man's switch (healthchecks.io)."

    # disk-backed on purpose: under systemd /tmp is usually a tmpfs, and staging the plaintext dump
    # there spends the RAM postgres is using to produce it
    STAGING="$(mktemp -d /var/tmp/domix-backup.XXXXXX)"
    chmod 700 "$STAGING"

    log "photos from $PHOTOS_DIR, database ${DB_URL##*@}, destination $(redact "$DEST")"
}

# ---------------------------------------------------------------------------- the database half

backup_database() {
    local date_stamp="$1"
    local plain="$STAGING/dump" encrypted="$STAGING/dump.enc"
    local name="$DUMP_PREFIX$date_stamp$DUMP_SUFFIX"

    # --format=custom rather than plain sql: it is compressed, pg_restore can read its table of
    # contents - which is what the verify step below leans on - and a restore can be driven table by
    # table on the day one table is the problem.
    STEP="dumping the database"
    pg_dump --format=custom --file="$plain" --dbname="$PG_CONN"

    STEP="encrypting the dump"
    openssl enc "${CIPHER[@]}" -pass "file:$BACKUP_PASSPHRASE_FILE" -in "$plain" -out "$encrypted"

    # **read it back before it leaves.** this is the step that catches a rotated passphrase, a
    # truncated write, and a dump postgres finished but filled with nothing. all three are otherwise
    # discovered on the day the data they were supposed to hold is already gone.
    STEP="verifying the encrypted dump reads back"
    openssl enc -d "${CIPHER[@]}" -pass "file:$BACKUP_PASSPHRASE_FILE" -in "$encrypted" -out "$plain.check"
    cmp -s "$plain" "$plain.check" || die "the dump does not survive its own decryption"
    pg_restore --list "$plain.check" >/dev/null || die "the decrypted dump is not a readable pg dump"

    STEP="uploading the dump"
    # copyto, not copy: the file name is the date and must not become a directory
    rclone_ copyto "$encrypted" "$DEST/$DB_PREFIX/$name"

    log "database: $(du -h "$encrypted" | cut -f1) encrypted, verified, uploaded as $DB_PREFIX/$name"
}

# ---------------------------------------------------------------------------- the photo half

backup_photos() {
    local date_stamp="$1"
    local mirror="$DEST/$PHOTO_MIRROR" changes="$DEST/$PHOTO_CHANGES/$date_stamp"

    # --checksum rather than the default size-and-modtime pair: a photo restored from somewhere else
    # arrives with a new mtime and the same bytes, and md5 of a 150 KB jpeg costs nothing.
    # --fast-list pages the whole key space instead of listing per directory, and the store is
    # sharded two characters wide - that is thousands of list calls R2 bills for, every night.
    STEP="mirroring the photos"
    rclone_ sync "$PHOTOS_DIR" "$mirror" \
        --backup-dir "$changes" \
        --checksum --fast-list --transfers 8 --retries 3

    # the photo half's equivalent of reading the dump back: rclone reports its own failures, but a
    # mirror with fewer files than the disk is the one outcome that must never pass quietly.
    STEP="counting what landed in the mirror"
    local on_disk mirrored changed=0
    on_disk="$(find "$PHOTOS_DIR" -type f | wc -l)"
    mirrored="$(rclone_ lsf --recursive --files-only "$mirror" | wc -l)"
    # the folder does not exist on a night when nothing changed, which is not a failure to count
    if rclone_ lsf --recursive --files-only "$changes" >"$STAGING/changed" 2>/dev/null; then
        changed="$(wc -l < "$STAGING/changed")"
    fi
    (( mirrored == on_disk )) \
        || die "the mirror holds $mirrored files and the disk $on_disk - the sync did not finish"

    log "photos: $mirrored mirrored, $changed moved into $PHOTO_CHANGES/$date_stamp"
}

# ---------------------------------------------------------------------------- retention

# by the date in the name, not by the object's age in the bucket: re-uploading a file rewrites its
# mtime, while the name says what night it belongs to and cannot drift.
prune_old_backups() {
    STEP="pruning backups older than $RETENTION_DAYS days"
    local cutoff
    cutoff="$(date -d "${BACKUP_DATE:-today} -$RETENTION_DAYS days" +%Y%m%d)"

    local entry dir name stamp
    while read -r entry; do
        [[ -n "$entry" ]] || continue
        dir="${entry%/}"
        # anything that is not a date is left alone and said out loud: it was put there by a person,
        # and a retention rule that deletes what it does not understand is how a restore point dies
        stamp="$(date -d "$dir" +%Y%m%d 2>/dev/null)" \
            || { warn "$PHOTO_CHANGES/$dir is not a date - left alone"; continue; }
        if [[ "$stamp" < "$cutoff" ]]; then
            rclone_ purge "$DEST/$PHOTO_CHANGES/$dir"
            log "pruned $PHOTO_CHANGES/$dir"
        fi
    done < <(rclone_ lsf --dirs-only "$DEST/$PHOTO_CHANGES" 2>/dev/null || true)

    while read -r entry; do
        [[ -n "$entry" ]] || continue
        name="${entry#"$DUMP_PREFIX"}"
        name="${name%"$DUMP_SUFFIX"}"
        stamp="$(date -d "$name" +%Y%m%d 2>/dev/null)" \
            || { warn "$DB_PREFIX/$entry is not a dated dump - left alone"; continue; }
        if [[ "$stamp" < "$cutoff" ]]; then
            rclone_ deletefile "$DEST/$DB_PREFIX/$entry"
            log "pruned $DB_PREFIX/$entry"
        fi
    done < <(rclone_ lsf --files-only "$DEST/$DB_PREFIX" 2>/dev/null || true)
}

# ---------------------------------------------------------------------------- the dead man's switch

# a ping that did not arrive is **not** a failed backup: the switch alerts on silence anyway, and
# marking a good night as failed is how people learn to ignore these alerts.
heartbeat_ok() {
    curl --silent --show-error --max-time 20 --retry 3 \
        --data-raw "domix backup ok" "$BACKUP_HEARTBEAT_URL" >/dev/null \
        || warn "the backup succeeded but the heartbeat could not be pinged"
}

heartbeat_fail() {
    local code="$1"
    log "FAILED while $STEP (exit $code)" >&2
    [[ -n "${BACKUP_HEARTBEAT_URL:-}" ]] || return 0
    curl --silent --show-error --max-time 20 --retry 2 \
        --data-raw "domix backup FAILED while $STEP (exit $code) - journalctl -u domix-backup" \
        "${BACKUP_HEARTBEAT_URL%/}/fail" >/dev/null \
        || warn "could not report the failure to the heartbeat url"
}

main "$@"
