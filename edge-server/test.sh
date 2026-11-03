#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8884}"
OUT_DIR="${OUT_DIR:-$PWD/output}"
mkdir -p "$OUT_DIR"

echo "== 1. 健康检查 =="
curl -s "$BASE_URL/health"
echo

echo "== 2. 列出中文音色 =="
curl -s "$BASE_URL/v1/voices?locale=zh-CN"
echo

echo "== 3. 列出模型 =="
curl -s "$BASE_URL/v1/models"
echo

echo "== 4. 基础语音合成 (OpenAI 兼容接口) =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "edge-tts",
    "input": "你好，这是一套本地运行的 Microsoft Edge 语音合成方案。",
    "voice": "zh-CN-XiaoxiaoNeural",
    "response_format": "mp3"
  }' \
  --output "$OUT_DIR/speech.mp3"
echo "已生成 $OUT_DIR/speech.mp3"

echo "== 5. 使用短别名 + WAV 格式 =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "Hello, this is Microsoft Edge text to speech running on the local server.",
    "voice": "nova",
    "response_format": "wav"
  }' \
  --output "$OUT_DIR/speech_en.wav"
echo "已生成 $OUT_DIR/speech_en.wav"

echo "== 6. 指定语速 / 音调 / 音量 =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "edge-tts",
    "input": "这是一条调整了语速、音调和音量的语音合成测试。",
    "voice": "yunxi",
    "response_format": "mp3",
    "speed": 1.2,
    "pitch": 20,
    "volume_multiplier": 1.2
  }' \
  --output "$OUT_DIR/speech_tuned.mp3"
echo "已生成 $OUT_DIR/speech_tuned.mp3"

echo "== 7. 流式合成 (chunked audio) =="
curl -sN -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "edge-tts",
    "input": "这是流式输出的语音合成测试，音频边生成边返回。",
    "voice": "xiaoxiao",
    "response_format": "mp3",
    "stream_format": "audio"
  }' \
  --output "$OUT_DIR/speech_stream.mp3"
echo "已生成 $OUT_DIR/speech_stream.mp3"

echo "== 8. 流式合成 (SSE) =="
curl -sN -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "edge-tts",
    "input": "Server sent events streaming test.",
    "voice": "alloy",
    "response_format": "mp3",
    "stream_format": "sse"
  }' \
  --output "$OUT_DIR/speech_stream.sse"
echo "已生成 $OUT_DIR/speech_stream.sse"

echo "== 完成，输出目录: $OUT_DIR =="
