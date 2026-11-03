#!/usr/bin/env bash
#
# Run the Qwen3-TTS server directly on the host (no Docker image).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Conda environment shared with the other servers (default: tts-whisper).
ENV_NAME="${QWEN3_TTS_ENV_NAME:-tts-whisper}"
if [[ -z "${CONDA_SH:-}" ]]; then
  for cand in \
    "$HOME/.miniconda3/etc/profile.d/conda.sh" \
    "/home/chenyh/.miniconda3/etc/profile.d/conda.sh" \
    "/data/.miniconda3/etc/profile.d/conda.sh"; do
    [[ -f "$cand" ]] && CONDA_SH="$cand" && break
  done
fi
CONDA_SH="${CONDA_SH:?conda.sh not found; set CONDA_SH=/path/to/conda.sh}"

# Checkpoint / inference defaults (see api_server.py for all QWEN3_TTS_* vars).
export QWEN3_TTS_MODEL="${QWEN3_TTS_MODEL:-Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice}"
export QWEN3_TTS_DEVICE="${QWEN3_TTS_DEVICE:-auto}"
export QWEN3_TTS_DTYPE="${QWEN3_TTS_DTYPE:-}"
export QWEN3_TTS_ATTN="${QWEN3_TTS_ATTN:-}"
export QWEN3_TTS_TASK="${QWEN3_TTS_TASK:-}"
export QWEN3_TTS_LANGUAGE="${QWEN3_TTS_LANGUAGE:-Auto}"
export QWEN3_TTS_FORMAT="${QWEN3_TTS_FORMAT:-mp3}"
export QWEN3_TTS_PORT="${QWEN3_TTS_PORT:-8885}"
export QWEN3_TTS_LOG_LEVEL="${QWEN3_TTS_LOG_LEVEL:-INFO}"
export QWEN3_TTS_API_KEY="${QWEN3_TTS_API_KEY:-}"
export QWEN3_TTS_MAX_CONCURRENCY="${QWEN3_TTS_MAX_CONCURRENCY:-1}"

# Persistent model / Hugging Face cache (kept out of the source tree).
QWEN3_TTS_DATA="${QWEN3_TTS_DATA:-$HERE/models}"
mkdir -p "$QWEN3_TTS_DATA"
export QWEN3_TTS_DATA
export HF_HOME="${HF_HOME:-$QWEN3_TTS_DATA/hf}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export HUGGINGFACE_HUB_CACHE="$HF_HUB_CACHE"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

echo "Starting Qwen3-TTS (direct run)"
echo "  Env:    $ENV_NAME"
echo "  Model:  $QWEN3_TTS_MODEL"
echo "  Task:   ${QWEN3_TTS_TASK:-auto}"
echo "  Device: $QWEN3_TTS_DEVICE"
echo "  Port:   $QWEN3_TTS_PORT"
echo "  Cache:  $HF_HOME"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

cd "$HERE"

# Stop any previous instance, then start a fresh one.
pkill -f "$HERE/api_server.py" 2>/dev/null || true
sleep 1

nohup python "$HERE/api_server.py" >>"$HERE/nohup.out" 2>&1 &
disown 2>/dev/null || true
echo "Started qwen3-tts (pid=$!), logging to $HERE/nohup.out"
