# CUDA 12.4 runtime + cuDNN (cuBLAS is required by ctranslate2's CUDA backend).
# docker.io is unreachable here, so a mirror is used by default. Override with
#   --build-arg CUDA_IMAGE=nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
ARG CUDA_IMAGE=docker.1panel.live/nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
FROM ${CUDA_IMAGE}

ARG PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
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
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

# Ubuntu 22.04 ships Python 3.10, but faster-whisper-server needs >=3.11 (tomllib),
# so install Python 3.11 from the deadsnakes PPA into a dedicated virtualenv.
RUN apt-get update \
    && apt-get install -y --no-install-recommends software-properties-common \
    && add-apt-repository -y ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y --no-install-recommends python3.11 python3.11-venv \
    && rm -rf /var/lib/apt/lists/*

RUN python3.11 -m venv "${VIRTUAL_ENV}" \
    && pip install --upgrade pip \
    && pip install --index-url "${PIP_INDEX_URL}" \
        "faster-whisper-server==${FASTER_WHISPER_SERVER_VERSION}"

# faster-whisper-server reads project.version from a pyproject.toml located in
# site-packages, but the PyPI wheel ships without it. Generate a minimal valid
# file to avoid a FileNotFoundError at import time.
RUN printf '[project]\nname = "faster-whisper-server"\nversion = "%s"\n' \
        "${FASTER_WHISPER_SERVER_VERSION}" \
        > "$(python3 -c 'import site; print(site.getsitepackages()[0])')/pyproject.toml"

WORKDIR /app

COPY config.yaml /app/config.yaml

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4)" || exit 1

ENTRYPOINT ["faster-whisper-server"]
CMD ["--config", "/app/config.yaml", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--log-level", "info"]
