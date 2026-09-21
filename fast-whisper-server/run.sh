#!/bin/bash
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate runtime

cd "$(dirname "$0")"

kill_existing() {
  pkill -f "faster-whisper-server" 2>/dev/null || true
  sleep 1
}

case "$1" in
  start)
    kill_existing
    nohup \
      faster-whisper-server \
      --config ./config.yaml \
      --host 0.0.0.0 \
      --port 8000 \
      --workers 1 \
      --log-level info \
      >> whisper.log 2>&1 &
    echo "Started faster-whisper-server"
    ;;
  kill)
    kill_existing
    echo "Killed faster-whisper-server"
    ;;
  *)
    echo "Usage: $0 {start|kill}"
    ;;
esac
