# CPU-friendly base + CUDA 12 user-space libraries from PyPI.
# The host NVIDIA driver is injected at runtime (CDI / nvidia runtime), so a
# full nvidia/cuda image is not required.
ARG BASE_IMAGE=docker.1panel.live/library/python:3.12-slim
FROM ${BASE_IMAGE}

ARG PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple/
ARG FASTER_WHISPER_SERVER_VERSION=0.0.2

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    HF_HUB_OFFLINE=1 \
    TRANSFORMERS_OFFLINE=1 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    LD_LIBRARY_PATH=/usr/local/lib/python3.12/site-packages/nvidia/cublas/lib:/usr/local/lib/python3.12/site-packages/nvidia/cuda_runtime/lib:/usr/local/lib/python3.12/site-packages/nvidia/cudnn/lib

RUN sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# uv downloads in parallel over HTTP/2, which is much faster than pip here.
RUN pip install --index-url "${PIP_INDEX_URL}" uv

# CTranslate2's CUDA backend dlopens the cuBLAS/cuDNN/cudart shared libraries.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --system --break-system-packages \
        --index-url "${PIP_INDEX_URL}" \
        "faster-whisper-server==${FASTER_WHISPER_SERVER_VERSION}" \
        "av<14" \
        nvidia-cublas-cu12 \
        nvidia-cuda-runtime-cu12 \
        nvidia-cudnn-cu12

# faster-whisper-server reads project.version from a pyproject.toml located in
# site-packages, but the PyPI wheel ships without it. Generate a minimal valid
# file to avoid a FileNotFoundError at import time.
RUN printf '[project]\nname = "faster-whisper-server"\nversion = "%s"\n' \
        "${FASTER_WHISPER_SERVER_VERSION}" \
        > "$(python -c 'import site; print(site.getsitepackages()[0])')/pyproject.toml"

WORKDIR /app

COPY config.yaml /app/config.yaml

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status == 200 else 1)" || exit 1

ENTRYPOINT ["faster-whisper-server"]
CMD ["--config", "/app/config.yaml", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--log-level", "info"]
