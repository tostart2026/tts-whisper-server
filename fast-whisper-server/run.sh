#!/bin/bash
if ! command -v conda >/dev/null 2>&1; then
  for base in "$HOME/.miniconda3" /data/.miniconda3; do
    if [ -f "$base/etc/profile.d/conda.sh" ]; then
      source "$base/etc/profile.d/conda.sh"
      break
    fi
  done
fi
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate tts-whisper

# CTranslate2 is built against CUDA 12, while torch in this env ships CUDA 13 libs.
# Point the loader at the cu12 cuBLAS installed under site-packages.
SITE_PACKAGES="$(python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
export LD_LIBRARY_PATH="$SITE_PACKAGES/nvidia/cublas/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

cd "$(dirname "$0")"

pkill -f "faster-whisper-server" 2>/dev/null || true
sleep 1

nohup \
  faster-whisper-server \
  --config ./config.yaml \
  --host 0.0.0.0 \
  --port 8881 \
  --workers 1 \
  --log-level info \
  >> whisper.log 2>&1 &

echo "Started faster-whisper-server"
