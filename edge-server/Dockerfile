ARG BASE_IMAGE=docker.1panel.live/library/python:3.12-slim
FROM ${BASE_IMAGE}

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# ffmpeg is required for wav/opus/aac/flac/pcm output (mp3 works without it).
RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt ./
RUN pip install --index-url "${PIP_INDEX_URL}" -r requirements.txt

COPY api_server.py ./

ENV EDGE_PORT=8884 \
    EDGE_DATA=/app/models \
    EDGE_VOICE=zh-CN-XiaoxiaoNeural \
    EDGE_SPEED=1.0 \
    EDGE_LOG_LEVEL=INFO

EXPOSE 8884

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8884/health', timeout=4).status == 200 else 1)" || exit 1

CMD ["python", "api_server.py"]
