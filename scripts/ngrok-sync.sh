#!/usr/bin/env bash
#
# Point .env and frontend/env.json at whatever URL ngrok is currently serving.
#
# The account has a reserved static domain now (jeep-prepay-penholder.ngrok-free.dev, one free per
# ngrok account), so on the happy path this rewrites the same two lines it rewrote last time. It is
# here for the one way that still goes wrong: a reserved domain is only used if it is ASKED for, so
#
#   ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080   <- the static domain
#   ngrok http 8080                                              <- a fresh random one, silently
#
# and the second form leaves both files pointing at a host that no longer exists. It was written when
# the free tier handed out a new hostname on every restart, which is also what a machine without the
# reserved domain still gets.
#
# Two files hard-code that hostname, for two different reasons:
#
#   .env               WEBHOOK_URL     where Telegram PUSHES updates to us
#   frontend/env.json  API_BASE_URL    where the app PULLS from us
#
# Neither can be localhost. Telegram's servers are on the internet and a real phone is on mobile
# data, so both need the public address that ngrok forwards into this laptop's port 8080.
#
# Editing them by hand is a recurring two-file chore where forgetting either one fails silently and
# differently: a stale WEBHOOK_URL means /start never arrives and login hangs on the polling screen,
# a stale API_BASE_URL means every request times out and the home screen quietly shows the showcase
# fallback as though the database were empty. Neither says "your tunnel moved".
#
# Reads ngrok's own local API rather than asking for the URL, so it cannot be mistyped.
#
# Usage:  ./scripts/ngrok-sync.sh      (with ngrok already running)

set -euo pipefail
cd "$(dirname "$0")/.."

URL=$(curl -s --max-time 3 localhost:4040/api/tunnels \
  | python3 -c 'import sys,json;print(next(t["public_url"] for t in json.load(sys.stdin)["tunnels"] if t["public_url"].startswith("https")))' \
  2>/dev/null) || {
    echo "ERROR: no ngrok tunnel found on localhost:4040."
    echo "       Start one first:  ngrok http --url=jeep-prepay-penholder.ngrok-free.dev 8080"
    exit 1
  }

echo "tunnel: $URL"

# -i '' would be a BSD-ism; GNU sed takes -i with no argument. the pattern anchors on the key name
# so it survives whatever host was there before.
sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=$URL/webhook|" .env
sed -i "s|\"API_BASE_URL\": \".*\"|\"API_BASE_URL\": \"$URL/api/auth\"|" frontend/env.json

echo "  .env               WEBHOOK_URL  -> $URL/webhook"
echo "  frontend/env.json  API_BASE_URL -> $URL/api/auth"
echo
echo "Both are read at startup, not live - so restart what is already running:"
echo "  the Go backend (Ctrl+C, then 'go run ./cmd/api')  - it registers the webhook on boot"
echo "  'make dev'                                        - env.json is COMPILED IN, hot reload"
echo "                                                      cannot pick it up"
