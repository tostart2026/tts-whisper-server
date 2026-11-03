#!/usr/bin/env bash
#
# Run the Microsoft Edge TTS server directly on the host (no Docker image).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Conda environment that provides Python + edge-tts (reused, not recreated).
ENV_NAME="${EDGE_ENV_NAME:-tts-whisper}"
if [[ -z "${CONDA_SH:-}" ]]; then
  for cand in \
    "$HOME/.miniconda3/etc/profile.d/conda.sh" \
    "/home/chenyh/.miniconda3/etc/profile.d/conda.sh" \
    "/data/.miniconda3/etc/profile.d/conda.sh"; do
    [[ -f "$cand" ]] && CONDA_SH="$cand" && break
  done
fi
CONDA_SH="${CONDA_SH:?conda.sh not found; set CONDA_SH=/path/to/conda.sh}"

# Active voice / synthesis defaults (see api_server.py for all EDGE_* vars).
export EDGE_VOICE="${EDGE_VOICE:-zh-CN-XiaoxiaoNeural}"
export EDGE_SPEED="${EDGE_SPEED:-1.0}"
export EDGE_PORT="${EDGE_PORT:-8884}"
export EDGE_LOG_LEVEL="${EDGE_LOG_LEVEL:-INFO}"
export EDGE_API_KEY="${EDGE_API_KEY:-}"
export EDGE_MAX_CONCURRENCY="${EDGE_MAX_CONCURRENCY:-8}"
# Optional outbound proxy, e.g. http://127.0.0.1:7890
export EDGE_PROXY="${EDGE_PROXY:-}"

# Voice catalog cache (kept out of the source tree so it survives upgrades).
EDGE_DATA="${EDGE_DATA:-$HERE/models}"
mkdir -p "$EDGE_DATA"
export EDGE_DATA

echo "Starting Microsoft Edge TTS (direct run)"
echo "  Env:      $ENV_NAME"
echo "  Voice:    $EDGE_VOICE"
echo "  Port:     $EDGE_PORT"
echo "  Cache:    $EDGE_DATA"
echo "  Proxy:    ${EDGE_PROXY:-none}"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

cd "$HERE"

# Stop any previous instance, then start a fresh one.
# Takes no arguments: just run it to (re)deploy.
pkill -f "$HERE/api_server.py" 2>/dev/null || true
sleep 1

nohup python "$HERE/api_server.py" >>"$HERE/nohup.out" 2>&1 &
disown 2>/dev/null || true
echo "Started edge-tts (pid=$!), logging to $HERE/nohup.out"
