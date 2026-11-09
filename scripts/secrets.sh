#!/usr/bin/env bash
#
# Encrypted backup of the two files that cannot be regenerated.
#
#   ./scripts/secrets.sh backup    # pack + encrypt into secrets.vault.enc, then copy it OFF this laptop
#   ./scripts/secrets.sh restore   # decrypt secrets.vault.enc back into place
#   ./scripts/secrets.sh list      # show what is inside the vault without unpacking it
#
# WHAT IS IN HERE AND WHY IT IS ENCRYPTED
#
# Two files in this project are irreplaceable:
#
#   ~/domix-upload-key.jks          the Google Play upload key. lose it and there is no way to ship
#                                   an update to the installed app, ever - only a new listing.
#   .env                            DB_URL, TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET, JWT_SECRET, PORT.
#
# Both belong in a backup. Neither belongs in git *as plain text*, and the reason is not that the
# repository is public - it is private today. The reason is that git history is permanent and
# retroactive: once a secret is committed it stays in every clone, every fork and every backup of
# the repo forever, and `git rm` does not remove it. Rotating a leaked JWT_SECRET afterwards signs
# every user out; a leaked .jks cannot be rotated at all. Making the repo public later, adding one
# collaborator, or handing a laptop to a contractor would each expose all of it at once, years after
# the commit that did it.
#
# So the files are encrypted with a passphrase that lives only in your head. That is what makes an
# off-laptop copy possible at all: a plain .env cannot go in Drive or a chat, an encrypted vault can
# go anywhere. The vault is gitignored and stays out of git - encryption is what would make
# committing it *safe*, not what makes it *desirable*, and only the first question was ever settled.
#
# A vault that never leaves this laptop is worth nothing: one dead disk takes the originals and the
# copy together. Copying it somewhere else is the entire point of running this.
#
# AES-256 via openssl, which is already installed everywhere, with PBKDF2 key derivation so the
# passphrase is not used as a key directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT="$REPO_ROOT/secrets.vault.enc"
KEY_PROPERTIES="$REPO_ROOT/frontend/android/key.properties"

# **read from key.properties rather than assumed**: gradle signs with whatever that file's storeFile
# points at, so a path guessed here could differ from the keystore actually in use - and a vault
# missing the real one still says "wrote secrets.vault.enc" and is discovered on a dead laptop.
KEYSTORE="$HOME/domix-upload-key.jks"
if [[ -f "$KEY_PROPERTIES" ]]; then
    from_properties="$(sed -n 's/^storeFile=//p' "$KEY_PROPERTIES" | tail -1)"
    if [[ -n "$from_properties" ]]; then KEYSTORE="$from_properties"; fi
fi

# the scratch directory is a global rather than a `local`, because the EXIT trap that deletes it
# runs after the function has returned and a local would be out of scope by then - under `set -u`
# that is not a leak, it is a crash on the way out.
STAGED=""
# plain `[[ ... ]] && rm` would return 1 when STAGED is empty, and a trap's last exit status becomes
# the script's - so a clean run would report failure.
cleanup() { if [[ -n "$STAGED" ]]; then rm -rf "$STAGED"; fi; }
trap cleanup EXIT

# openssl arguments used identically by backup and restore. -pbkdf2 with a high iteration count is
# what makes a short passphrase expensive to brute-force; without it openssl falls back to a single
# MD5 round, which is not a defence.
CIPHER=(-aes-256-cbc -pbkdf2 -iter 600000 -salt)

usage() {
    echo "usage: $0 {backup|restore|list}"
    exit 1
}

cmd_backup() {
    STAGED="$(mktemp -d)"
    local staged="$STAGED"

    local found=0

    if [[ -f "$REPO_ROOT/.env" ]]; then
        cp "$REPO_ROOT/.env" "$staged/.env"
        echo "  + .env"
        found=$((found + 1))
    else
        echo "  ! .env not found at $REPO_ROOT/.env - skipping"
    fi

    if [[ -f "$KEYSTORE" ]]; then
        cp "$KEYSTORE" "$staged/domix-upload-key.jks"
        echo "  + domix-upload-key.jks"
        found=$((found + 1))
    else
        # **fatal rather than skipped**: the keystore is the one file in here that cannot be
        # regenerated, and a vault written without it reads as a successful backup
        echo "  ! keystore NOT FOUND at $KEYSTORE" >&2
        echo >&2
        echo "Refusing to write a vault without it: losing this file means never shipping an update" >&2
        echo "to the installed app again. Fix storeFile in $KEY_PROPERTIES, or generate the key." >&2
        exit 1
    fi

    if [[ -f "$REPO_ROOT/frontend/android/key.properties" ]]; then
        cp "$REPO_ROOT/frontend/android/key.properties" "$staged/key.properties"
        echo "  + frontend/android/key.properties"
        found=$((found + 1))
    fi

    if [[ "$found" -eq 0 ]]; then
        echo "nothing to back up." >&2
        exit 1
    fi

    echo
    echo "Choose a passphrase. Write it down somewhere that is not this laptop - without it the"
    echo "vault is as lost as the files it protects."
    tar -czf "$staged/vault.tar.gz" -C "$staged" $(cd "$staged" && ls -A | grep -v vault.tar.gz)
    openssl enc "${CIPHER[@]}" -in "$staged/vault.tar.gz" -out "$VAULT"

    echo
    echo "wrote $VAULT ($(du -h "$VAULT" | cut -f1))"
    echo
    echo "Now copy it somewhere that is NOT this laptop and NOT this repo - cloud drive, another"
    echo "machine, a USB stick. It is encrypted, so anywhere is fine. A vault that stays here is"
    echo "worth nothing: one dead disk takes the originals and the copy together."
    echo
    echo "Do NOT commit it. It is gitignored on purpose."
    echo
    echo "To get the files back later (new laptop, or after losing them): put secrets.vault.enc in"
    echo "the repo root and run"
    echo "  ./scripts/secrets.sh restore"
    echo
    echo "Re-run backup after changing .env or key.properties - the vault is a snapshot, not a live"
    echo "mirror, so an edit made today is not in yesterday's vault."
}

cmd_restore() {
    [[ -f "$VAULT" ]] || { echo "no vault at $VAULT" >&2; exit 1; }

    STAGED="$(mktemp -d)"
    local staged="$STAGED"

    openssl enc -d "${CIPHER[@]}" -in "$VAULT" -out "$staged/vault.tar.gz"
    tar -xzf "$staged/vault.tar.gz" -C "$staged"

    # never clobber silently - a restore onto a machine that already has a working .env would
    # otherwise replace a current secret with an older one and the failure would show up much later
    # as "everyone got logged out".
    restore_one() {
        local src="$1" dst="$2"
        [[ -f "$src" ]] || return 0
        if [[ -f "$dst" ]]; then
            echo "  = $dst already exists, left alone (vault copy at $src)"
        else
            cp "$src" "$dst"
            echo "  + $dst"
        fi
    }

    restore_one "$staged/.env" "$REPO_ROOT/.env"
    restore_one "$staged/domix-upload-key.jks" "$KEYSTORE"
    restore_one "$staged/key.properties" "$REPO_ROOT/frontend/android/key.properties"

    # the staged copies die with the tmpdir on exit, so anything reported as "left alone" is gone
    # once this returns. re-run after moving the existing file out of the way.
}

cmd_list() {
    [[ -f "$VAULT" ]] || { echo "no vault at $VAULT" >&2; exit 1; }
    openssl enc -d "${CIPHER[@]}" -in "$VAULT" | tar -tzf -
}

case "${1:-}" in
    backup)  cmd_backup ;;
    restore) cmd_restore ;;
    list)    cmd_list ;;
    *)       usage ;;
esac
