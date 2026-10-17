#!/bin/bash
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate tts-whisper

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
