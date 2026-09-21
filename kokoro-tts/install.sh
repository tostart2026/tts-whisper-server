#!/usr/bin/env bash
#
# Install Kokoro TTS dependencies into the existing conda environment
# (reused, not recreated) so the server can run directly on the host.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_NAME="${KOKORO_ENV_NAME:-runtime}"
CONDA_SH="${CONDA_SH:-$HOME/.miniconda3/etc/profile.d/conda.sh}"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

pip install -r "$HERE/requirements.txt"

# English spaCy model used by the Kokoro/misaki text pipeline.
pip install "$HERE/wheels/en_core_web_sm-3.8.0-py3-none-any.whl"

echo "Kokoro dependencies installed in conda env '$ENV_NAME'."
