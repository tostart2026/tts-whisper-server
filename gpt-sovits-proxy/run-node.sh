#!/usr/bin/env bash
#
# Run the Digital Man voice proxy (Node.js) directly on the host.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export MONGODB_URI="${MONGODB_URI:-mongodb://192.168.168.33:27017,192.168.168.33:27018,192.168.168.33:27019/?replicaSet=rs0}"
export MONGODB_DB="${MONGODB_DB:-voice_helper_db}"
export DIGITALMAN_DB="${DIGITALMAN_DB:-digitalman_db}"
export REDIS_URL="${REDIS_URL:-redis://192.168.168.33:6379}"
export VOICE_SCHEME="${VOICE_SCHEME:-http}"
export VOICE_HOST="${VOICE_HOST:-192.168.168.60}"
export VOICE_PORT="${VOICE_PORT:-60002}"
export VOICE_TTS_PATH="${VOICE_TTS_PATH:-/tts}"
export TRUST_PROXY="${TRUST_PROXY:-true}"
export DIGITALMAN_PROXY_HOST="${DIGITALMAN_PROXY_HOST:-0.0.0.0}"
export DIGITALMAN_PROXY_PORT="${DIGITALMAN_PROXY_PORT:-8083}"
export DIGITALMAN_TIMEOUT="${DIGITALMAN_TIMEOUT:-600}"

echo "Starting Digital Man voice proxy (Node.js)"
echo "  Listen:   ${DIGITALMAN_PROXY_HOST}:${DIGITALMAN_PROXY_PORT}"
echo "  MongoDB:  $MONGODB_URI"
echo "  Redis:    $REDIS_URL"
echo "  Voice:    ${VOICE_SCHEME}://${VOICE_HOST}:{TtsBaseUrl|${VOICE_PORT}}"

exec node "$HERE/server.js"
