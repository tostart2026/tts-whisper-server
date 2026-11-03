ARG BASE_IMAGE=tts-whisper/torch-base:local
FROM ${BASE_IMAGE}

ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/

WORKDIR /app

COPY requirements.txt ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-url "${PIP_INDEX_URL}" -r requirements.txt

COPY wheels ./wheels
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-url "${PIP_INDEX_URL}" \
        ./wheels/en_core_web_sm-3.8.0-py3-none-any.whl

COPY api_server.py ./

ENV KOKORO_PORT=8882 \
    KOKORO_DATA=/app/models \
    KOKORO_VOICE=af_heart \
    KOKORO_SPEED=1.0 \
    KOKORO_LOG_LEVEL=INFO \
    KOKORO_LOCAL_ONLY=1 \
    HF_HOME=/app/models/hf \
    HF_HUB_CACHE=/app/models/hf/hub \
    HUGGINGFACE_HUB_CACHE=/app/models/hf/hub \
    HF_ENDPOINT=https://hf-mirror.com

EXPOSE 8882

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8882/health', timeout=4).status == 200 else 1)" || exit 1

CMD ["python", "api_server.py"]
