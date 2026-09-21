#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8880}"
OUT_DIR="${OUT_DIR:-./output}"
mkdir -p "$OUT_DIR"

echo "== 1. 健康检查 =="
curl -s "$BASE_URL/health"
echo

echo "== 2. 列出可用音色 =="
curl -s "$BASE_URL/v1/voices"
echo

echo "== 3. 列出模型 =="
curl -s "$BASE_URL/v1/models"
echo

echo "== 4. 基础语音合成 (OpenAI 兼容接口) =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "你好，这是一个本地部署的语音合成测试。",
    "voice": "zf_xiaobei",
    "response_format": "mp3"
  }' \
  --output "$OUT_DIR/speech.mp3"
echo "已生成 $OUT_DIR/speech.mp3"

echo "== 5. 指定语速 / 格式 / 音量 =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "Hello, this is a text to speech test at normal speed.",
    "voice": "af_bella",
    "response_format": "wav",
    "speed": 1.0,
    "volume_multiplier": 1.0
  }' \
  --output "$OUT_DIR/speech_speed.wav"
echo "已生成 $OUT_DIR/speech_speed.wav"

echo "== 6. 使用 OpenAI 音色别名 =="
curl -s -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "The quick brown fox jumps over the lazy dog.",
    "voice": "alloy",
    "response_format": "mp3"
  }' \
  --output "$OUT_DIR/speech_en.mp3"
echo "已生成 $OUT_DIR/speech_en.mp3"

echo "== 7. 流式合成 (chunked audio) =="
curl -N -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "这是流式输出的语音合成测试，音频边生成边返回。",
    "voice": "zf_xiaobei",
    "response_format": "mp3",
    "stream_format": "audio"
  }' \
  --output "$OUT_DIR/speech_stream.mp3"
echo "已生成 $OUT_DIR/speech_stream.mp3"

echo "== 8. 流式合成 (SSE) =="
curl -N -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "Server sent events streaming test.",
    "voice": "af_heart",
    "response_format": "mp3",
    "stream_format": "sse"
  }' \
  --output "$OUT_DIR/speech_stream.sse"
echo "已生成 $OUT_DIR/speech_stream.sse"

echo "== 完成，输出目录: $OUT_DIR =="
