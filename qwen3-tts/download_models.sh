#!/usr/bin/env bash
#
# Download the Qwen3-TTS checkpoint (and its 12Hz tokenizer) into the local
# Hugging Face cache so the server can start without network access.
#
# Override the checkpoint with QWEN3_TTS_MODEL. Set HF_ENDPOINT (default:
# https://hf-mirror.com) to use a mirror; a local directory is used as-is.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

export QWEN3_TTS_MODEL="${QWEN3_TTS_MODEL:-Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice}"
QWEN3_TTS_DATA="${QWEN3_TTS_DATA:-$HERE/models}"
export HF_HOME="${HF_HOME:-$QWEN3_TTS_DATA/hf}"
export HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
export HUGGINGFACE_HUB_CACHE="$HF_HUB_CACHE"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
export HF_HUB_ENABLE_HF_TRANSFER="${HF_HUB_ENABLE_HF_TRANSFER:-0}"

mkdir -p "$QWEN3_TTS_DATA"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

python - <<'PY'
import os
from pathlib import Path

from huggingface_hub import snapshot_download

model = os.environ["QWEN3_TTS_MODEL"]
low = model.lower()

if Path(model).expanduser().exists():
    print(f"Model is a local path, nothing to download: {model}")
    raise SystemExit(0)

if "25hz" in low:
    tokenizer = "Qwen/Qwen3-TTS-Tokenizer-25Hz"
else:
    tokenizer = "Qwen/Qwen3-TTS-Tokenizer-12Hz"

for repo in (tokenizer, model):
    print(f"Downloading {repo} ...")
    path = snapshot_download(repo_id=repo)
    print(f"  -> {path}")

print("Done. HF_HOME =", os.environ.get("HF_HOME"))
PY
