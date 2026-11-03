#!/usr/bin/env bash
#
# Install Microsoft Edge TTS dependencies into the existing conda environment
# (reused, not recreated), then cache the voice catalog / verify synthesis.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

pip install -r "$HERE/requirements.txt"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "WARNING: ffmpeg not found; mp3 output works but wav/opus/aac/flac/pcm do not." >&2
fi

echo "Edge TTS dependencies installed in conda env '$ENV_NAME'."

"$HERE/download_models.sh"
