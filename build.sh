#!/usr/bin/env bash
#
# Build all voice-service images.
#
# The Kokoro and Qwen3 images share a local torch base image. It is not built
# by docker compose automatically, so build it first and then build the rest.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

docker build -t tts-whisper/torch-base:local ./base
docker compose build "$@"
