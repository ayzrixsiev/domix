# the constants and DEST/PG_CONN below are read by the scripts that source this file
# shellcheck shell=bash disable=SC2034
# Shared by deploy/backup.sh and deploy/restore.sh. Not executable on its own.
#
# **It exists because a restore that disagrees with the backup by one openssl flag is a backup that
# does not restore**, and that is only discovered on the worst day. The cipher, the object layout,
# the destination and the connection handling are defined once, here.
#
# The reasoning behind the backup design is in deploy/backup.sh; the operator's side in restore.sh.

# the bucket's layout. the mirror and the dated folders have to be siblings: rclone refuses a
# --backup-dir that sits inside the directory it is syncing.
readonly PHOTO_MIRROR="photos"
readonly PHOTO_CHANGES="photo-changes"
readonly DB_PREFIX="db"

# the whole night's database work as one line of `rclone lsf db/`
readonly DUMP_PREFIX="domix-"
readonly DUMP_SUFFIX=".dump.enc"

# **both halves must pass these identically or nothing decrypts.** -pbkdf2 with a high iteration
# count is what makes a short passphrase expensive to brute-force; without it openssl derives the key
# with a single MD5 round, which is not a defence. The same cipher as scripts/secrets.sh, so there is
# one answer to "how does Domix encrypt things".
readonly CIPHER=(-aes-256-cbc -pbkdf2 -iter 600000 -salt)

log()  { printf '%s %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${LOG_TAG:-domix-backup}" "$*"; }
warn() { log "WARNING: $*" >&2; }
die()  { log "FAILED: $*" >&2; exit 1; }

# "r2backup:domix-backups" with the remote name taken off: enough to tell a bucket from a directory
# in the journal without printing either in full.
redact() { printf '%s' "${1##*:}"; }

rclone_() { rclone --config "" --stats 0 "$@"; }

# only KEY=VALUE lines, and **the caller's environment wins**, which is what lets the self-test point
# these scripts at a directory while real credentials sit in the same .env the api reads.
load_env_file() {
    local file="$1" line key value
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]}"
        # set-but-empty also wins, which is how backup-selftest.sh blanks a value that .env fills
        [[ -n "${!key+set}" ]] && continue
        value="${value%$'\r'}"
        value="${value#\"}" ; value="${value%\"}"
        value="${value#\'}" ; value="${value%\'}"
        export "$key=$value"
    done < "$file"
}

require_tools() {
    local tool
    for tool in "$@"; do
        command -v "$tool" >/dev/null \
            || die "$tool is not installed (apt install rclone postgresql-client openssl curl)"
    done
}

# sets DEST to the bucket or, for the self-test, to a directory standing in for it.
#
# **the one place a partial configuration must not become a partial backup**: a run that skipped the
# photos, or wrote them onto this machine's own disk, looks exactly like a good one in the journal
# and is discovered when it is the only copy left.
resolve_destination() {
    local dest_dir="${BACKUP_DEST_DIR:-}"
    local -a missing=() present=()
    local name
    for name in BACKUP_R2_ACCOUNT_ID BACKUP_R2_ACCESS_KEY_ID BACKUP_R2_SECRET_ACCESS_KEY BACKUP_R2_BUCKET; do
        if [[ -z "${!name:-}" ]]; then missing+=("$name"); else present+=("$name"); fi
    done

    if (( ${#present[@]} > 0 )) && [[ -n "$dest_dir" ]]; then
        die "BACKUP_DEST_DIR and ${present[0]} are both set - that would back this server up onto its own disk. Unset BACKUP_DEST_DIR outside the self-test."
    fi

    if [[ -n "$dest_dir" ]]; then
        [[ -d "$dest_dir" ]] || die "BACKUP_DEST_DIR ($dest_dir) is not a directory"
        DEST="$dest_dir"
        return
    fi
    if (( ${#present[@]} == 0 )); then
        die "no backup destination: set the four BACKUP_R2_* values (or BACKUP_DEST_DIR for the self-test)"
    fi
    if (( ${#missing[@]} > 0 )); then
        die "the backup bucket is half configured - ${missing[*]} missing"
    fi

    # rclone reads a remote called r2backup straight out of the environment, so no rclone.conf on the
    # server holds a second copy of these credentials, and **nothing secret reaches argv**: every
    # process on the box can read /proc/<pid>/cmdline, none can read another's environment.
    export RCLONE_CONFIG_R2BACKUP_TYPE="s3"
    export RCLONE_CONFIG_R2BACKUP_PROVIDER="Cloudflare"
    export RCLONE_CONFIG_R2BACKUP_REGION="auto"
    export RCLONE_CONFIG_R2BACKUP_ENDPOINT="https://${BACKUP_R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
    export RCLONE_CONFIG_R2BACKUP_ACCESS_KEY_ID="$BACKUP_R2_ACCESS_KEY_ID"
    export RCLONE_CONFIG_R2BACKUP_SECRET_ACCESS_KEY="$BACKUP_R2_SECRET_ACCESS_KEY"
    # R2 answers a bucket HEAD with 404 for a token that cannot list buckets, and rclone reads that
    # as "the bucket does not exist" and refuses to write into a bucket that is there
    export RCLONE_CONFIG_R2BACKUP_NO_CHECK_BUCKET="true"

    DEST="r2backup:$BACKUP_R2_BUCKET"
}

require_passphrase() {
    [[ -n "${BACKUP_PASSPHRASE_FILE:-}" ]] \
        || die "BACKUP_PASSPHRASE_FILE is not set - the dump would leave the country readable"
    [[ -s "$BACKUP_PASSPHRASE_FILE" ]] \
        || die "BACKUP_PASSPHRASE_FILE ($BACKUP_PASSPHRASE_FILE) is missing or empty"
    # this passphrase is the whole defence for every phone number in the dump, so a file anyone on
    # the box can read is worth stopping for rather than warning about
    local mode
    mode="$(stat -c '%a' "$BACKUP_PASSPHRASE_FILE")"
    [[ "${mode: -2}" == "00" ]] \
        || die "BACKUP_PASSPHRASE_FILE is mode $mode - run: chmod 600 $BACKUP_PASSPHRASE_FILE"
}

# splits the password out of a postgres:// url into PGPASSWORD and leaves the rest in PG_CONN.
#
# **the password must not reach argv**: nginx and the api run as their own users on this box and
# /proc/<pid>/cmdline is world-readable, so `pg_dump -d postgres://user:pass@...` hands the database
# password to anything that can run `ps` for as long as the dump takes.
split_db_url() {
    local url="$1"
    if [[ "$url" =~ ^(postgres(ql)?://)([^:/@]+):([^@]*)@(.+)$ ]]; then
        export PGPASSWORD="${BASH_REMATCH[4]}"
        PG_CONN="${BASH_REMATCH[1]}${BASH_REMATCH[3]}@${BASH_REMATCH[5]}"
    else
        PG_CONN="$url"
    fi
}
