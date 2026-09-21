#!/usr/bin/env bash
#
# Run the Kokoro text-to-speech server directly on the host (no Docker image).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Conda environment that provides Python + torch (reused, not recreated).
ENV_NAME="${KOKORO_ENV_NAME:-runtime}"
CONDA_SH="${CONDA_SH:-$HOME/.miniconda3/etc/profile.d/conda.sh}"

# Active voice / synthesis defaults (see api_server.py for all KOKORO_* vars).
export KOKORO_VOICE="${KOKORO_VOICE:-af_heart}"
export KOKORO_SPEED="${KOKORO_SPEED:-1.0}"
export KOKORO_PORT="${KOKORO_PORT:-8880}"
export KOKORO_LOG_LEVEL="${KOKORO_LOG_LEVEL:-INFO}"
export KOKORO_API_KEY="${KOKORO_API_KEY:-}"

# Persistent model / huggingface cache directory (kept out of the source tree
# so it is not lost on upgrades).
KOKORO_DATA="${KOKORO_DATA:-$HERE/data}"
mkdir -p "$KOKORO_DATA"
export HF_HOME="${HF_HOME:-$KOKORO_DATA/hf}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export HUGGINGFACE_HUB_CACHE="$HF_HUB_CACHE"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

echo "Starting Kokoro TTS (direct run)"
echo "  Env:   $ENV_NAME"
echo "  Voice: $KOKORO_VOICE"
echo "  Port:  $KOKORO_PORT"
echo "  Cache: $HF_HOME"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

cd "$HERE"
exec python "$HERE/api_server.py"
