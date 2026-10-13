import base64
import json
import logging
import os

import httpx
import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response

logger = logging.getLogger("digitalman-proxy")

DIGITALMAN_SERVER_URL = os.getenv("digitalman_server_url", "http://127.0.0.1:8092/")
DIGITALMAN_VOICE_PATH = os.getenv("DIGITALMAN_VOICE_PATH", "/proxy/get_voice_by_text")
PROXY_HOST = os.getenv("DIGITALMAN_PROXY_HOST", "0.0.0.0")
PROXY_PORT = int(os.getenv("DIGITALMAN_PROXY_PORT", "8083"))
REQUEST_TIMEOUT = float(os.getenv("DIGITALMAN_TIMEOUT", "600"))

app = FastAPI(title="Digital Man Voice Proxy", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def get_gpt_sovits(token: str, voice_text: str, role: str = "master") -> dict:
    """伪函数：获取数字人声音合成的音频地址。

    通过 digitalman_server_url（默认 http://127.0.0.1:8092/）页面中的
    “声音地址接口” /proxy/get_voice_by_text 获取音频，参数:
        text  = voice_text
        token = token
        type  = role（master / assit，用于区分主声音与助播声音）

    返回:
        {
            "url": "<声音地址接口完整地址>",
            "params": { ... 请求参数 ... },
        }
    """
    base = (DIGITALMAN_SERVER_URL or "").rstrip("/")
    params = {
        "text": voice_text,
        "token": token,
    }
    if role:
        params["type"] = role
    return {
        "url": f"{base}{DIGITALMAN_VOICE_PATH}",
        "params": params,
    }


async def _read_params(request: Request) -> dict:
    data = dict(request.query_params)
    ctype = request.headers.get("content-type", "")
    if "application/json" in ctype:
        try:
            payload = await request.json()
            if isinstance(payload, dict):
                data.update(payload)
        except Exception:
            pass
    elif "form" in ctype:
        form = await request.form()
        data.update(dict(form))
    return data


def _meta_headers(url: str, params: dict, status: int = None) -> dict:
    headers = {
        "Access-Control-Expose-Headers": (
            "X-DIGITALMAN-Url, X-DIGITALMAN-Params, X-DIGITALMAN-Status"
        ),
        "X-DIGITALMAN-Url": (url or "")[:1024],
        "X-DIGITALMAN-Params": base64.b64encode(
            json.dumps(params or {}, ensure_ascii=False).encode("utf-8")
        ).decode("ascii"),
    }
    if status is not None:
        headers["X-DIGITALMAN-Status"] = str(status)
    return headers


@app.get("/health")
async def health():
    return {"status": "ok", "digitalman_server_url": DIGITALMAN_SERVER_URL}


@app.post("/gptsovit")
async def gptsovit(request: Request):
    req = await _read_params(request)
    token = (req.get("token") or "").strip()
    voice_text = (req.get("voiceText") or "").strip()
    role = (req.get("role") or req.get("type") or "master").strip() or "master"

    if not token:
        return JSONResponse(status_code=400, content={"message": "token is required"})
    if not voice_text:
        return JSONResponse(status_code=400, content={"message": "voiceText is required"})

    cfg = get_gpt_sovits(token, voice_text, role)
    url = cfg["url"]
    params = cfg["params"]
    logger.info("digitalman role=%s url=%s params=%s", role, url, json.dumps(params, ensure_ascii=False))

    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            upstream = await client.get(url, params=params)
    except httpx.HTTPError as exc:
        logger.warning("digitalman url=%s error=%s", url, exc)
        return JSONResponse(
            status_code=502,
            headers=_meta_headers(url, params),
            content={"message": "upstream request failed", "detail": str(exc)},
        )

    logger.info("digitalman url=%s status=%s bytes=%d", url, upstream.status_code, len(upstream.content))
    if upstream.status_code != 200:
        return JSONResponse(
            status_code=upstream.status_code,
            headers=_meta_headers(url, params, upstream.status_code),
            content={
                "message": "upstream error",
                "detail": upstream.text[:2000],
            },
        )

    media_type = upstream.headers.get("content-type", "audio/wav")
    if "application/json" in media_type:
        media_type = "audio/wav"
    return Response(
        content=upstream.content,
        media_type=media_type,
        headers=_meta_headers(url, params, upstream.status_code),
    )


if __name__ == "__main__":
    uvicorn.run(app, host=PROXY_HOST, port=PROXY_PORT)
