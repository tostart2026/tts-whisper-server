#!/usr/bin/env bash
#
# Install Qwen3-TTS into a dedicated conda environment (created if missing),
# then download the weights ahead of the first start.
#
# qwen-tts pins transformers/accelerate versions, so it is installed into its
# own environment by default instead of being mixed into tts-whisper.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${QWEN3_TTS_ENV_NAME:-qwen3-tts}"
if [[ -z "${CONDA_SH:-}" ]]; then
  for cand in \
    "$HOME/.miniconda3/etc/profile.d/conda.sh" \
    "/home/chenyh/.miniconda3/etc/profile.d/conda.sh" \
    "/data/.miniconda3/etc/profile.d/conda.sh"; do
    [[ -f "$cand" ]] && CONDA_SH="$cand" && break
  done
fi
CONDA_SH="${CONDA_SH:?conda.sh not found; set CONDA_SH=/path/to/conda.sh}"

# shellcheck disable=SC1090
source "$CONDA_SH"

if ! conda env list | awk '{print $1}' | grep -qx "$ENV_NAME"; then
  echo "Creating conda env '$ENV_NAME' (python 3.12)..."
  conda create -y -n "$ENV_NAME" python=3.12
fi

conda activate "$ENV_NAME"

python -m pip install --upgrade pip

# qwen-tts is new; some regional mirrors lag behind. Default to PyPI and allow
# overriding with QWEN3_TTS_PIP_INDEX_URL (e.g. a Tsinghua mirror).
PIP_INDEX_URL="${QWEN3_TTS_PIP_INDEX_URL:-https://pypi.org/simple}"

# The RTX 50-series (sm_120) needs CUDA 12.8+ wheels. Set
# QWEN3_TTS_TORCH_INDEX_URL="" to skip this step when torch is already present.
if ! python -c "import torch" >/dev/null 2>&1; then
  TORCH_INDEX_URL="${QWEN3_TTS_TORCH_INDEX_URL-https://download.pytorch.org/whl/cu128}"
  if [[ -n "$TORCH_INDEX_URL" ]]; then
    echo "Installing torch/torchaudio from $TORCH_INDEX_URL ..."
    python -m pip install torch torchaudio --index-url "$TORCH_INDEX_URL"
  fi
fi

python -m pip install -r "$HERE/requirements.txt" --index-url "$PIP_INDEX_URL"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "WARNING: ffmpeg not found; mp3/flac/opus/aac output will not work." >&2
fi

echo "Qwen3-TTS dependencies installed in conda env '$ENV_NAME'."

"$HERE/download_models.sh"
