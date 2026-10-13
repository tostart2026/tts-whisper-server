#!/usr/bin/env bash
#
# Run the Digital Man voice proxy directly on the host (no Docker image).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_NAME="${DIGITALMAN_ENV_NAME:-runtime}"
CONDA_SH="${CONDA_SH:-$HOME/.miniconda3/etc/profile.d/conda.sh}"

export digitalman_server_url="${digitalman_server_url:-http://127.0.0.1:8092/}"
export DIGITALMAN_VOICE_PATH="${DIGITALMAN_VOICE_PATH:-/gsv-tts}"
export DIGITALMAN_PROXY_HOST="${DIGITALMAN_PROXY_HOST:-0.0.0.0}"
export DIGITALMAN_PROXY_PORT="${DIGITALMAN_PROXY_PORT:-8083}"
export DIGITALMAN_TIMEOUT="${DIGITALMAN_TIMEOUT:-600}"

echo "Starting Digital Man voice proxy"
echo "  Env:      $ENV_NAME"
echo "  Listen:   ${DIGITALMAN_PROXY_HOST}:${DIGITALMAN_PROXY_PORT}"
echo "  DigitalMan: $digitalman_server_url"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

cd "$HERE"
exec python "$HERE/proxy.py"
