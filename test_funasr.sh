#!/usr/bin/env bash
#
# Test the FunASR WebSocket endpoint through nginx.
#
# Usage:
#   ./test_funasr.sh [URL]
#   ./test_funasr.sh https://voice.ylb.cloud/funasr
#   ./test_funasr.sh ws://127.0.0.1:8880/funasr
#
# A healthy endpoint returns: 101 Switching Protocols
# 426 Upgrade Required means the reverse proxy is dropping the Upgrade headers.
#
set -euo pipefail

DEFAULT_URL="https://voice.ylb.cloud/funasr"
TARGET="${1:-$DEFAULT_URL}"

# curl needs an http(s) URL to perform the handshake, not ws(s).
URL="${TARGET/#ws:\/\//http://}"
URL="${URL/#wss:\/\//https://}"

echo "Testing FunASR WebSocket: $TARGET"

# A successful upgrade keeps the socket open, so curl will time out after
# printing the headers. Ignore the timeout and inspect the headers instead.
RESPONSE="$(
  curl -sS -i --http1.1 --max-time 5 \
    -H 'Connection: Upgrade' \
    -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' \
    -H 'Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==' \
    "$URL" 2>/dev/null || true
)"

STATUS="$(printf '%s\n' "$RESPONSE" | grep -m1 -E '^HTTP/[0-9.]+ [0-9]{3}' || true)"

if printf '%s\n' "$RESPONSE" | grep -q '101 Switching Protocols'; then
  echo "$STATUS"
  echo "OK: WebSocket upgrade succeeded."
elif printf '%s\n' "$RESPONSE" | grep -q '426 Upgrade Required'; then
  echo "$STATUS"
  echo "FAIL: Upgrade headers are not being forwarded by a reverse proxy." >&2
  exit 1
else
  printf '%s\n' "$RESPONSE"
  echo "FAIL: unexpected response." >&2
  exit 1
fi
