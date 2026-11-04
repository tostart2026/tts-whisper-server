ARG BASE_IMAGE=base:cu121
FROM ${BASE_IMAGE}

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/

WORKDIR /app

COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-url "${PIP_INDEX_URL}" -r requirements.txt

COPY api_server.py ./

ENV QWEN3_TTS_PORT=8885 \
    QWEN3_TTS_DATA=/app/models \
    QWEN3_TTS_MODEL=Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice \
    QWEN3_TTS_DEVICE=auto \
    QWEN3_TTS_LANGUAGE=Auto \
    QWEN3_TTS_FORMAT=mp3 \
    QWEN3_TTS_LOG_LEVEL=INFO \
    QWEN3_TTS_MAX_CONCURRENCY=1 \
    HF_HOME=/app/models/hf \
    HF_HUB_CACHE=/app/models/hf/hub \
    HUGGINGFACE_HUB_CACHE=/app/models/hf/hub \
    HF_ENDPOINT=https://hf-mirror.com \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1

EXPOSE 8885

HEALTHCHECK --interval=30s --timeout=5s --start-period=300s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8885/health', timeout=4).status == 200 else 1)" || exit 1

CMD ["python", "api_server.py"]
