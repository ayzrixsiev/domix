#!/usr/bin/env bash
#
# The other half of deploy/backup.sh: getting the market back out of the bucket.
#
#   ./deploy/restore.sh list
#   ./deploy/restore.sh db      <date> <target-database-url>
#   ./deploy/restore.sh photos  <directory>
#   ./deploy/restore.sh changes <date> <directory>
#
# **An untested backup is a hypothesis.** This script is the test, and deploy/backup-selftest.sh runs
# it against a throwaway database and a directory standing in for the bucket, so the restore path is
# exercised on an ordinary day rather than first attempted on the worst one.
#
# REBUILDING ON A NEW SERVER, from the bucket alone
#
#   1. Postgres of the same major version as production (18), with postgis and pg_trgm installable:
#      `apt install postgresql-18-postgis-3` from the PGDG repository, since Ubuntu ships 16. A dump
#      restores into an older postgres only by accident.
#   2. Create the role and an empty database with a UTF-8 locale - migration 000001 refuses a
#      database that cannot lowercase Cyrillic:
#        createdb -T template0 -E UTF8 --locale=en_US.UTF-8 domix
#   3. Create both extensions as the postgres superuser in that database: postgis is untrusted, so
#      the api's own role cannot. Then `restore.sh db <date> <url>`.
#   4. `restore.sh photos /srv/domix/images`, then `chown -R domix:www-data` so the api can write and
#      nginx can read.
#   5. Point .env at the restored database and that directory, and start the api.
#
# The two halves fit without touching a row: `products.image_path` is relative and the mirror's keys
# are byte-identical to it.
#
# UNDOING A DELETION rather than a disaster
#
# `changes <date> <dir>` pulls one night's `photo-changes/<date>/`: exactly the files that were
# deleted or overwritten on the server that day, which the mirror no longer has. Copy them back over
# the photo directory and the deletion is undone. That folder is why the nightly mirror is safe to
# run at all - see the header of backup.sh.
#
# Configuration is the same .env backup.sh reads.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=backup-lib.sh
source "$REPO_ROOT/deploy/backup-lib.sh"

LOG_TAG="domix-restore"
STAGING=""
cleanup() { if [[ -n "$STAGING" ]]; then rm -rf "${STAGING:?}"; fi; }
trap cleanup EXIT

usage() {
    cat >&2 <<'USAGE'
usage:
  restore.sh list                                 what the bucket holds
  restore.sh db      <date> <target-db-url>       a dated dump into an EMPTY database
  restore.sh photos  <directory>                  the photo mirror as it stands now
  restore.sh changes <date> <directory>           one night's deleted or overwritten photos
USAGE
    exit 1
}

prepare() {
    load_env_file "${DOMIX_ENV_FILE:-$REPO_ROOT/.env}"
    require_tools rclone psql pg_restore openssl
    resolve_destination
}

# ---------------------------------------------------------------------------- list

cmd_list() {
    prepare

    echo "database dumps ($(redact "$DEST")/$DB_PREFIX):"
    rclone_ lsl "$DEST/$DB_PREFIX" 2>/dev/null | sort -k4 || echo "  (none)"

    echo
    echo "nights of photo changes ($PHOTO_CHANGES), newest last:"
    local dir count
    while read -r dir; do
        [[ -n "$dir" ]] || continue
        count="$(rclone_ lsf --recursive --files-only "$DEST/$PHOTO_CHANGES/$dir" | wc -l)"
        printf '  %s  %s file(s)\n' "${dir%/}" "$count"
    done < <(rclone_ lsf --dirs-only "$DEST/$PHOTO_CHANGES" 2>/dev/null | sort || true)

    echo
    echo "photo mirror ($PHOTO_MIRROR):"
    rclone_ size "$DEST/$PHOTO_MIRROR" 2>/dev/null || echo "  (empty)"
}

# ---------------------------------------------------------------------------- the database half

cmd_db() {
    local date_stamp="${1:-}" target="${2:-}"
    [[ -n "$date_stamp" && -n "$target" ]] || usage
    prepare
    require_passphrase

    local name="$DUMP_PREFIX$date_stamp$DUMP_SUFFIX"
    STAGING="$(mktemp -d /var/tmp/domix-restore.XXXXXX)"
    chmod 700 "$STAGING"

    log "fetching $DB_PREFIX/$name"
    rclone_ copyto "$DEST/$DB_PREFIX/$name" "$STAGING/dump.enc" \
        || die "no dump for $date_stamp - run: restore.sh list"

    log "decrypting"
    openssl enc -d "${CIPHER[@]}" -pass "file:$BACKUP_PASSPHRASE_FILE" \
        -in "$STAGING/dump.enc" -out "$STAGING/dump" \
        || die "the dump did not decrypt - wrong passphrase in $BACKUP_PASSPHRASE_FILE"
    pg_restore --list "$STAGING/dump" >/dev/null || die "the decrypted file is not a pg dump"

    split_db_url "$target"

    # **never restore over live data.** a restore onto a database that still has rows is how an
    # incident becomes two incidents: pg_restore would leave a half-merged mixture of the two.
    local existing
    existing="$(psql --dbname="$PG_CONN" --tuples-only --no-align \
        --command="select count(*) from pg_class where relname in ('users','shops','products') and relkind = 'r'")" \
        || die "cannot reach the target database"
    (( existing == 0 )) || die "the target database already has Domix tables - restore into a fresh one (createdb -T template0 -E UTF8)"

    # --exit-on-error because pg_restore otherwise prints "errors ignored on restore: N" and carries
    # on: a database missing one table would be reported as restored.
    # --no-owner/--no-privileges because the roles are the old server's, and this is a new one.
    # **--no-comments or the restore stops on the first object**: the only comments a Domix dump
    # carries are pg_dump's two on postgis and pg_trgm, and on a rebuilt server a superuser created
    # those extensions, so the api's role may not comment on them. With --exit-on-error that is not
    # a warning, it is the end of the restore.
    log "restoring into ${target##*@}"
    pg_restore --dbname="$PG_CONN" --no-owner --no-privileges --no-comments --exit-on-error "$STAGING/dump"

    # pg_restore builds the indexes but leaves the planner with no statistics, and the home screen's
    # queries read as broken-slow until something analyses
    psql --dbname="$PG_CONN" --quiet --command="ANALYZE"

    log "restored. tables: $(psql --dbname="$PG_CONN" --tuples-only --no-align \
        --command="select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r'")"
}

# ---------------------------------------------------------------------------- the photo half

cmd_photos() {
    local target="${1:-}"
    [[ -n "$target" ]] || usage
    prepare

    mkdir -p "$target"
    log "copying the mirror into $target"
    rclone_ copy "$DEST/$PHOTO_MIRROR" "$target" --checksum --fast-list --transfers 8 --retries 3

    # the copy is only a claim until something compares both sides
    log "verifying"
    rclone_ check "$DEST/$PHOTO_MIRROR" "$target" --checksum --fast-list \
        || die "the restored directory does not match the mirror"

    log "restored $(find "$target" -type f | wc -l) photos into $target"
    log "set IMAGES_DIR to it, and chown it so the api can write and nginx can read"
}

cmd_changes() {
    local date_stamp="${1:-}" target="${2:-}"
    [[ -n "$date_stamp" && -n "$target" ]] || usage
    prepare

    mkdir -p "$target"
    rclone_ copy "$DEST/$PHOTO_CHANGES/$date_stamp" "$target" --checksum --transfers 8 --retries 3 \
        || die "nothing stored for $date_stamp - run: restore.sh list"

    log "$(find "$target" -type f | wc -l) file(s) from $date_stamp are in $target"
    log "these are the photos the server deleted or overwrote that day - copy them back over IMAGES_DIR to undo it"
}

case "${1:-}" in
    list)    shift; cmd_list "$@" ;;
    db)      shift; cmd_db "$@" ;;
    photos)  shift; cmd_photos "$@" ;;
    changes) shift; cmd_changes "$@" ;;
    *)       usage ;;
esac
