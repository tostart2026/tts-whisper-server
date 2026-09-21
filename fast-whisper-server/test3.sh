#!/bin/bash
curl -X POST "https://oneapi.ylb.cloud/v1/audio/transcriptions" \
  -H "Authorization: Bearer sk-PKz1x35D9IqxDqK3C0Fc5654Ee5f4d44B26855Ae605a9c15" \
  -F "file=@./关税.wav" \
  -F "model=whisper-1" \
  -F "language=zh" \
  -F "response_format=json"
