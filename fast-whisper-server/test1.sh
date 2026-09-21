#!/bin/bash
curl -X POST "http://localhost:8000/v1/audio/transcriptions" \
  -F "file=@./关税.wav" \
  -F "model_name=whisper-1" \
  -F "language=zh" \
  -F "response_format=json"
