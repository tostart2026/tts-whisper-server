# Shared GPU/Python base for the Kokoro and Qwen3 TTS images.
# The PyPI torch wheel bundles the CUDA runtime, so only the host driver is
# required (injected by the NVIDIA container runtime / CDI).
ARG BASE_IMAGE=docker.1panel.live/library/python:3.12-slim
FROM ${BASE_IMAGE}

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
ARG TORCH_VERSION=2.14.1
ARG TORCHAUDIO_VERSION=2.11.1

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates ffmpeg libsndfile1 espeak-ng sox libsox-fmt-all \
        build-essential \
    && rm -rf /var/lib/apt/lists/*

# uv downloads in parallel over HTTP/2, which is much faster than pip here.
RUN pip install --index-url "${PIP_INDEX_URL}" uv

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-url "${PIP_INDEX_URL}" \
        "torch==${TORCH_VERSION}" "torchaudio==${TORCHAUDIO_VERSION}"
