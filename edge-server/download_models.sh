#!/usr/bin/env bash
#
# Microsoft Edge TTS has no local neural model to download — synthesis runs on
# Microsoft's servers. This script instead:
#   1. downloads/caches the full voice catalog to models/voices.json
#   2. synthesizes a short sample to output/sample.mp3 to verify connectivity
#
# Set EDGE_SKIP_SAMPLE=1 to skip the sample synthesis.
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
export EDGE_HOME="$HERE"
export EDGE_DATA="${EDGE_DATA:-$HERE/models}"
export EDGE_VOICE="${EDGE_VOICE:-zh-CN-XiaoxiaoNeural}"
export EDGE_PROXY="${EDGE_PROXY:-}"

# shellcheck disable=SC1090
source "$CONDA_SH"
conda activate "$ENV_NAME"

mkdir -p "$EDGE_DATA" "$HERE/output"

python - <<'PY'
import asyncio
import json
import os
from datetime import datetime, timezone
from pathlib import Path

import edge_tts

data_dir = Path(os.environ["EDGE_DATA"])
cache = data_dir / "voices.json"
proxy = os.environ.get("EDGE_PROXY") or None


async def main() -> None:
    voices = await edge_tts.list_voices(proxy=proxy)
    updated = datetime.now(timezone.utc).isoformat(timespec="seconds")
    tmp = cache.with_suffix(".json.tmp")
    tmp.write_text(
        json.dumps({"updated": updated, "voices": voices}, ensure_ascii=False),
        encoding="utf-8",
    )
    tmp.replace(cache)
    print(f"Cached {len(voices)} voices -> {cache}")

    zh = [v["ShortName"] for v in voices if v["Locale"].startswith("zh")]
    print("Chinese voices:")
    for name in zh:
        print(f"  {name}")

    if os.environ.get("EDGE_SKIP_SAMPLE") == "1":
        return

    voice = os.environ["EDGE_VOICE"]
    out = Path(os.environ["EDGE_HOME"]) / "output" / "sample.mp3"
    out.parent.mkdir(parents=True, exist_ok=True)
    audio = bytearray()
    comm = edge_tts.Communicate(
        "你好，这是一条 Microsoft Edge 语音合成连通性测试。",
        voice,
        proxy=proxy,
    )
    async for chunk in comm.stream():
        if chunk.get("type") == "audio":
            audio.extend(chunk["data"])
    if not audio:
        raise RuntimeError("Edge TTS returned no audio")
    out.write_bytes(bytes(audio))
    print(f"Sample ({voice}) -> {out} ({len(audio)} bytes)")


asyncio.run(main())
PY
