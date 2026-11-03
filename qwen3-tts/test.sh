#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8885}"
OUT_DIR="${OUT_DIR:-$PWD/output}"
mkdir -p "$OUT_DIR"

say() { printf '%s\n' "$*"; }

say "== 1. 健康检查 =="
HEALTH="$(curl -s "$BASE_URL/health")"
say "$HEALTH"
TASK="$(printf '%s' "$HEALTH" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("task","custom_voice"))' 2>/dev/null || echo custom_voice)"
say "task = $TASK"

say "== 2. 列出模型 =="
curl -s "$BASE_URL/v1/models"
say

say "== 3. 列出音色 / 语言 =="
curl -s "$BASE_URL/v1/voices"
say

case "$TASK" in
  custom_voice)
    say "== 4. 基础语音合成 (CustomVoice) =="
    curl -s -X POST "$BASE_URL/v1/audio/speech" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "qwen3-tts",
        "input": "你好，这是本地部署的 Qwen3-TTS 语音合成测试。",
        "voice": "Vivian",
        "language": "Chinese",
        "response_format": "wav"
      }' \
      --output "$OUT_DIR/speech_custom.wav"
    say "已生成 $OUT_DIR/speech_custom.wav"

    say "== 5. 英文 + 语速 / 音量后处理 =="
    curl -s -X POST "$BASE_URL/v1/audio/speech" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "qwen3-tts",
        "input": "Hello, this is Qwen3 text to speech running locally.",
        "voice": "Ryan",
        "language": "en",
        "response_format": "mp3",
        "speed": 1.1,
        "volume_multiplier": 1.0
      }' \
      --output "$OUT_DIR/speech_en.mp3"
    say "已生成 $OUT_DIR/speech_en.mp3"

    say "== 6. 指令控制 (仅 1.7B CustomVoice 生效) =="
    curl -s -X POST "$BASE_URL/v1/audio/speech" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "qwen3-tts",
        "input": "我真的很喜欢这个功能！",
        "voice": "Vivian",
        "language": "Chinese",
        "instruct": "用开心、兴奋的语气说",
        "response_format": "wav"
      }' \
      --output "$OUT_DIR/speech_instruct.wav"
    say "已生成 $OUT_DIR/speech_instruct.wav"
    ;;
  voice_design)
    say "== 4. VoiceDesign 语音设计 =="
    curl -s -X POST "$BASE_URL/v1/audio/speech" \
      -H "Content-Type: application/json" \
      -d '{
        "model": "qwen3-tts",
        "input": "哥哥，你回来啦，人家等了你好久好久了，要抱抱！",
        "language": "Chinese",
        "instruct": "体现撒娇稚嫩的萝莉女声，音调偏高且起伏明显。",
        "response_format": "wav"
      }' \
      --output "$OUT_DIR/speech_design.wav"
    say "已生成 $OUT_DIR/speech_design.wav"
    ;;
  voice_clone)
    REF="$OUT_DIR/clone_ref.wav"
    if [ ! -s "$REF" ]; then
      say "== 4. 下载参考音频 =="
      curl -sL "https://qianwen-res.oss-cn-beijing.aliyuncs.com/Qwen3-TTS-Repo/clone.wav" -o "$REF" || true
    fi
    if [ -s "$REF" ]; then
      say "== 5. VoiceClone 声音克隆 (multipart) =="
      curl -s -X POST "$BASE_URL/v1/audio/clone" \
        -F "file=@$REF" \
        -F "input=This is a cloned voice speaking new content." \
        -F "language=English" \
        -F "ref_text=Okay. Yeah. I resent you. I love you. I respect you. But you know what? You blew it! And thanks to you." \
        -F "response_format=wav" \
        --output "$OUT_DIR/speech_clone.wav"
      say "已生成 $OUT_DIR/speech_clone.wav"
    else
      say "参考音频下载失败，跳过 VoiceClone 测试。"
    fi
    ;;
esac

say "== 7. 流式合成 (chunked audio) =="
curl -sN -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-tts",
    "input": "这是流式输出的语音合成测试。",
    "language": "Chinese",
    "response_format": "mp3",
    "stream_format": "audio"
  }' \
  --output "$OUT_DIR/speech_stream.mp3"
say "已生成 $OUT_DIR/speech_stream.mp3"

say "== 8. 流式合成 (SSE) =="
curl -sN -X POST "$BASE_URL/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-tts",
    "input": "Server sent events streaming test.",
    "language": "English",
    "response_format": "mp3",
    "stream_format": "sse"
  }' \
  --output "$OUT_DIR/speech_stream.sse"
say "已生成 $OUT_DIR/speech_stream.sse"

say "== 完成，输出目录: $OUT_DIR =="
