#!/usr/bin/env python3
"""
Microsoft Edge TTS API Server
Provides an OpenAI-compatible /v1/audio/speech endpoint backed by the
Microsoft Edge online neural voices (via the `edge-tts` package).

Notes
-----
* The neural voices run on Microsoft's servers. This process runs locally and
  streams audio from Microsoft, so an internet connection is required.
* There is no local neural model to download. `download_models.sh` caches the
  voice catalog (and verifies synthesis) so `/v1/voices` works at startup even
  when the catalog request is temporarily unavailable.
"""

import asyncio
import base64
import json
import logging
import os
import subprocess
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator, Literal, Optional, Union

import edge_tts
import uvicorn
from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_log_level_str = os.environ.get("EDGE_LOG_LEVEL", "INFO").upper()
_log_level = getattr(logging, _log_level_str, logging.INFO)
logging.basicConfig(
    level=_log_level,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("edge_server")

HERE = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("EDGE_DATA", str(HERE / "models")))
VOICES_CACHE = DATA_DIR / "voices.json"

DEFAULT_VOICE = os.environ.get("EDGE_VOICE", "zh-CN-XiaoxiaoNeural")
DEFAULT_SPEED = float(os.environ.get("EDGE_SPEED", "1.0"))
PROXY = os.environ.get("EDGE_PROXY", "").strip() or None
CONNECT_TIMEOUT = int(os.environ.get("EDGE_CONNECT_TIMEOUT", "10"))
RECEIVE_TIMEOUT = int(os.environ.get("EDGE_RECEIVE_TIMEOUT", "60"))
MAX_CHARS = int(os.environ.get("EDGE_MAX_CHARS", "4096"))
MAX_CONCURRENCY = int(os.environ.get("EDGE_MAX_CONCURRENCY", "8"))
RETRIES = max(1, int(os.environ.get("EDGE_RETRIES", "2")))

# OpenAI voice aliases. Multilingual voices are used so the same alias works
# for both Chinese and English text.
OPENAI_ALIASES = {
    "alloy":   "en-US-AvaMultilingualNeural",
    "echo":    "en-US-AndrewMultilingualNeural",
    "fable":   "en-US-BrianMultilingualNeural",
    "onyx":    "en-US-AndrewMultilingualNeural",
    "nova":    "en-US-EmmaMultilingualNeural",
    "shimmer": "en-US-AvaMultilingualNeural",
    "ash":     "en-US-BrianMultilingualNeural",
    "coral":   "en-US-EmmaMultilingualNeural",
    "sage":    "en-US-AvaMultilingualNeural",
    "verse":   "en-US-BrianMultilingualNeural",
    "ballad":  "en-US-AndrewMultilingualNeural",
    "marin":   "en-US-EmmaMultilingualNeural",
    "cedar":   "en-US-AndrewMultilingualNeural",
}

# Convenience aliases for the most common Chinese / multilingual voices.
EXTRA_ALIASES = {
    "xiaoxiao": "zh-CN-XiaoxiaoNeural",
    "xiaoyi":   "zh-CN-XiaoyiNeural",
    "yunjian":  "zh-CN-YunjianNeural",
    "yunxi":    "zh-CN-YunxiNeural",
    "yunxia":   "zh-CN-YunxiaNeural",
    "yunyang":  "zh-CN-YunyangNeural",
    "xiaobei":  "zh-CN-liaoning-XiaobeiNeural",
    "xiaoni":   "zh-CN-shaanxi-XiaoniNeural",
    "hiugaai":  "zh-HK-HiuGaaiNeural",
    "hiu maan": "zh-HK-HiuMaanNeural",
    "wanlung":  "zh-HK-WanLungNeural",
    "hsiaochen": "zh-TW-HsiaoChenNeural",
    "hsiaoyu":  "zh-TW-HsiaoYuNeural",
    "yunjhe":   "zh-TW-YunJheNeural",
    "ava":      "en-US-AvaMultilingualNeural",
    "andrew":   "en-US-AndrewMultilingualNeural",
    "brian":    "en-US-BrianMultilingualNeural",
    "emma":     "en-US-EmmaMultilingualNeural",
}

_FORMAT_MIME = {
    "mp3":  "audio/mpeg",
    "opus": "audio/ogg; codecs=opus",
    "aac":  "audio/aac",
    "flac": "audio/flac",
    "wav":  "audio/wav",
    "pcm":  "audio/pcm",
}

# ffmpeg output flags. Input is always the mp3 byte stream from Edge.
_FFMPEG_OUTPUT_ARGS = {
    "wav":  ["-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", "-f", "wav"],
    "pcm":  ["-ar", "24000", "-ac", "1", "-c:a", "pcm_s16le", "-f", "s16le"],
    "opus": ["-c:a", "libopus", "-b:a", "48k", "-f", "ogg"],
    "aac":  ["-c:a", "aac", "-b:a", "64k", "-f", "adts"],
    "flac": ["-c:a", "flac", "-f", "flac"],
}

# ---------------------------------------------------------------------------
# Voice catalog (in-memory + on-disk cache)
# ---------------------------------------------------------------------------

_voices: list[dict[str, Any]] = []
_voice_ids: set[str] = set()
_aliases: dict[str, str] = {**OPENAI_ALIASES, **EXTRA_ALIASES}
_voices_updated: Optional[str] = None
_voice_lock = asyncio.Lock()
_synth_sem = asyncio.Semaphore(MAX_CONCURRENCY)


def _install_voices(raw: list[dict[str, Any]], updated: Optional[str] = None) -> None:
    global _voices, _voice_ids, _aliases, _voices_updated

    voices = [v for v in raw if isinstance(v, dict) and v.get("ShortName")]
    ids = {v["ShortName"] for v in voices}

    aliases = {**OPENAI_ALIASES, **EXTRA_ALIASES}
    for short_name in ids:
        # zh-CN-XiaoxiaoNeural -> xiaoxiao
        parts = short_name.split("-")
        if len(parts) >= 3:
            key = "-".join(parts[2:]).lower()
            if key.endswith("neural") and key != "neural":
                key = key[: -len("neural")]
            aliases.setdefault(key, short_name)

    _voices = voices
    _voice_ids = ids
    _aliases = aliases
    _voices_updated = updated


def _load_cached_voices() -> None:
    if not VOICES_CACHE.is_file():
        return
    try:
        payload = json.loads(VOICES_CACHE.read_text(encoding="utf-8"))
        raw = payload.get("voices", payload) if isinstance(payload, dict) else payload
        updated = payload.get("updated") if isinstance(payload, dict) else None
        _install_voices(raw, updated)
        logger.info("Loaded %d cached Edge voices from %s", len(_voices), VOICES_CACHE)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to read voice cache %s: %s", VOICES_CACHE, exc)


def _save_cached_voices(raw: list[dict[str, Any]], updated: str) -> None:
    try:
        DATA_DIR.mkdir(parents=True, exist_ok=True)
        tmp = VOICES_CACHE.with_suffix(".json.tmp")
        tmp.write_text(
            json.dumps({"updated": updated, "voices": raw}, ensure_ascii=False),
            encoding="utf-8",
        )
        tmp.replace(VOICES_CACHE)
    except Exception as exc:  # noqa: BLE001
        logger.warning("Failed to write voice cache %s: %s", VOICES_CACHE, exc)


async def _refresh_voices() -> bool:
    global _voices_updated
    async with _voice_lock:
        try:
            raw = await asyncio.wait_for(
                edge_tts.list_voices(proxy=PROXY),
                timeout=CONNECT_TIMEOUT + 10,
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("Could not refresh Edge voice catalog: %s", exc)
            return False

        updated = None
        try:
            from datetime import datetime, timezone

            updated = datetime.now(timezone.utc).isoformat(timespec="seconds")
        except Exception:  # noqa: BLE001
            pass

        _install_voices(list(raw), updated)
        if updated:
            _save_cached_voices(list(raw), updated)
        logger.info("Refreshed Edge voice catalog: %d voices", len(_voices))
        return True


def _public_voice(v: dict[str, Any]) -> dict[str, Any]:
    tag = v.get("VoiceTag") or {}
    return {
        "id": v.get("ShortName"),
        "name": v.get("ShortName"),
        "short_name": v.get("ShortName"),
        "locale": v.get("Locale"),
        "locale_name": v.get("LocaleName"),
        "gender": v.get("Gender"),
        "friendly_name": v.get("FriendlyName"),
        "suggested_codec": v.get("SuggestedCodec"),
        "content_categories": tag.get("ContentCategories") or [],
        "voice_personalities": tag.get("VoicePersonalities") or [],
    }


def _resolve_voice(voice: Union[str, "VoiceReference", dict[str, Any]]) -> str:
    if isinstance(voice, VoiceReference):
        raw = voice.id
    elif isinstance(voice, dict) and "id" in voice:
        raw = str(voice["id"])
    else:
        raw = str(voice)

    raw = raw.strip()
    if not raw:
        raise HTTPException(
            status_code=400,
            detail="Voice must not be empty. Use GET /v1/voices to list voices.",
        )

    key = raw.lower()
    if raw in _voice_ids:
        return raw
    for short_name in _voice_ids:
        if short_name.lower() == key:
            return short_name
    if key in _aliases:
        return _aliases[key]

    # Allow a full voice name to pass through even if the catalog is cold.
    if "-" in raw and key.endswith("neural"):
        return raw

    raise HTTPException(
        status_code=400,
        detail=f"Unknown voice '{raw}'. Use GET /v1/voices to list voices.",
    )


# ---------------------------------------------------------------------------
# Edge synthesis helpers
# ---------------------------------------------------------------------------


def _rate_percent(speed: float) -> str:
    pct = int(round((speed - 1.0) * 100))
    pct = max(-100, min(500, pct))
    return f"{pct:+d}%"


def _volume_percent(multiplier: float) -> str:
    pct = int(round((multiplier - 1.0) * 100))
    pct = max(-100, min(100, pct))
    return f"{pct:+d}%"


def _pitch_hz(pitch: float) -> str:
    hz = int(round(pitch))
    hz = max(-200, min(200, hz))
    return f"{hz:+d}Hz"


async def _edge_audio_chunks(
    text: str,
    voice: str,
    rate: str,
    volume: str,
    pitch: str,
) -> AsyncIterator[bytes]:
    """Yield raw mp3 chunks from the Edge service, with a small retry budget."""
    last_error: Optional[Exception] = None

    async with _synth_sem:
        for attempt in range(1, RETRIES + 1):
            produced = False
            try:
                communicate = edge_tts.Communicate(
                    text,
                    voice,
                    rate=rate,
                    volume=volume,
                    pitch=pitch,
                    proxy=PROXY,
                    connect_timeout=CONNECT_TIMEOUT,
                    receive_timeout=RECEIVE_TIMEOUT,
                )
                async for chunk in communicate.stream():
                    if chunk.get("type") != "audio":
                        continue
                    data = chunk.get("data")
                    if data:
                        produced = True
                        yield data
                return
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # noqa: BLE001
                last_error = exc
                logger.warning(
                    "Edge synthesis attempt %d/%d failed (voice=%s): %s",
                    attempt, RETRIES, voice, exc,
                )
                # Never retry after audio was sent to the client.
                if produced or attempt >= RETRIES:
                    raise
                await asyncio.sleep(min(0.3 * attempt, 1.5))

    if last_error:
        raise last_error


def _ffmpeg_convert(mp3_bytes: bytes, fmt: str) -> bytes:
    if fmt == "mp3":
        return mp3_bytes

    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-f", "mp3", "-i", "pipe:0",
        *_FFMPEG_OUTPUT_ARGS[fmt],
        "-vn", "pipe:1",
    ]
    try:
        result = subprocess.run(
            cmd,
            input=mp3_bytes,
            capture_output=True,
            check=True,
            timeout=120,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"ffmpeg is required for response_format='{fmt}' but was not found."
        ) from exc
    except subprocess.CalledProcessError as exc:
        logger.error("ffmpeg conversion to %s failed: %s", fmt, exc.stderr.decode(errors="replace"))
        raise RuntimeError(f"Audio conversion to {fmt} failed.") from exc
    return result.stdout


async def _stream_converted(
    chunks: AsyncIterator[bytes],
    fmt: str,
) -> AsyncIterator[bytes]:
    """Convert the mp3 chunk stream to another format using ffmpeg."""
    if fmt == "mp3":
        async for chunk in chunks:
            yield chunk
        return

    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-f", "mp3", "-i", "pipe:0",
        *_FFMPEG_OUTPUT_ARGS[fmt],
        "-vn", "pipe:1",
    ]
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
    except FileNotFoundError as exc:
        raise RuntimeError(
            f"ffmpeg is required for response_format='{fmt}' but was not found."
        ) from exc

    queue: asyncio.Queue = asyncio.Queue(maxsize=8)

    async def reader() -> None:
        try:
            assert proc.stdout is not None
            while True:
                data = await proc.stdout.read(65536)
                if not data:
                    break
                await queue.put(data)
        finally:
            await queue.put(None)

    async def writer() -> None:
        try:
            assert proc.stdin is not None
            async for chunk in chunks:
                proc.stdin.write(chunk)
                await proc.stdin.drain()
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as exc:  # noqa: BLE001
            logger.warning("ffmpeg writer stopped: %s", exc)
        finally:
            try:
                if proc.stdin and not proc.stdin.is_closing():
                    proc.stdin.close()
            except Exception:  # noqa: BLE001
                pass

    reader_task = asyncio.create_task(reader())
    writer_task = asyncio.create_task(writer())
    try:
        while True:
            item = await queue.get()
            if item is None:
                break
            yield item
    finally:
        for task in (writer_task, reader_task):
            task.cancel()
        if proc.returncode is None:
            try:
                proc.kill()
            except ProcessLookupError:
                pass
            await proc.wait()


def _sse_audio_delta(audio_bytes: bytes) -> str:
    payload = json.dumps({
        "type": "speech.audio.delta",
        "audio": base64.b64encode(audio_bytes).decode("ascii"),
    })
    return f"data: {payload}\n\n"


async def _stream_sse(
    chunks: AsyncIterator[bytes],
    fmt: str,
) -> AsyncIterator[str]:
    try:
        async for chunk in _stream_converted(chunks, fmt):
            yield _sse_audio_delta(chunk)
        yield f'data: {json.dumps({"type": "speech.audio.done"})}\n\n'
        yield "data: [DONE]\n\n"
    except asyncio.CancelledError:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("SSE synthesis failed: %s", exc)
        payload = json.dumps({
            "error": {"type": "synthesis_error", "message": str(exc)}
        })
        yield f"data: {payload}\n\n"
        yield "data: [DONE]\n\n"


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------


@asynccontextmanager
async def _lifespan(app: FastAPI):
    _load_cached_voices()
    await _refresh_voices()
    logger.info(
        "Edge TTS ready | default_voice=%s voices=%d proxy=%s",
        DEFAULT_VOICE, len(_voices), PROXY or "none",
    )
    yield


app = FastAPI(
    title="Microsoft Edge Text-to-Speech",
    description=(
        "OpenAI-compatible text-to-speech API backed by Microsoft Edge "
        "online neural voices (edge-tts)."
    ),
    version="1.0.0",
    lifespan=_lifespan,
)


def _verify_api_key(authorization: Optional[str] = Header(default=None)) -> None:
    required = os.environ.get("EDGE_API_KEY", "").strip()
    if not required:
        return
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header.")
    parts = authorization.split(maxsplit=1)
    if len(parts) != 2 or parts[0].lower() != "bearer":
        raise HTTPException(
            status_code=401,
            detail="Invalid Authorization header. Expected: Bearer <key>",
        )
    if parts[1] != required:
        raise HTTPException(status_code=401, detail="Invalid API key.")


class VoiceReference(BaseModel):
    id: str = Field(..., description="Edge voice short name or supported alias.")


class SpeechRequest(BaseModel):
    model: str = Field(
        default="edge-tts",
        description="Model identifier. 'tts-1', 'tts-1-hd' and 'edge-tts' are accepted.",
    )
    input: str = Field(
        ...,
        max_length=MAX_CHARS,
        description=f"The text to synthesize. Maximum {MAX_CHARS} characters.",
    )
    voice: Union[str, VoiceReference] = Field(
        default=DEFAULT_VOICE,
        description=(
            "Edge voice short name (e.g. zh-CN-XiaoxiaoNeural), a short alias "
            "(xiaoxiao, yunxi), or an OpenAI alias (alloy, nova, ...). "
            "See GET /v1/voices."
        ),
    )
    instructions: Optional[str] = Field(
        default=None,
        max_length=4096,
        description="Accepted for OpenAI compatibility; ignored by Edge TTS.",
    )
    response_format: Optional[Literal["mp3", "opus", "aac", "flac", "wav", "pcm"]] = Field(
        default="mp3",
        description="Audio output format.",
    )
    speed: Optional[float] = Field(
        default=1.0,
        ge=0.25,
        le=4.0,
        description="Speech rate, 0.25-4.0 (1.0 = normal).",
    )
    volume_multiplier: float = Field(
        default=1.0,
        ge=0.1,
        le=2.0,
        description="Volume multiplier, 0.1-2.0 (1.0 = unchanged).",
    )
    pitch: float = Field(
        default=0.0,
        ge=-200.0,
        le=200.0,
        description="Pitch shift in Hz, -200 to +200 (0 = unchanged).",
    )
    stream_format: Optional[Literal["sse", "audio"]] = Field(
        default=None,
        description=(
            "Stream audio via chunked transfer ('audio') or OpenAI-style SSE "
            "speech.audio.delta events ('sse')."
        ),
    )


@app.get("/health", include_in_schema=False)
async def health():
    return {
        "status": "ok",
        "engine": "edge-tts",
        "voices": len(_voices),
        "voices_updated": _voices_updated,
    }


@app.get("/v1/models")
async def list_models(_auth: None = Depends(_verify_api_key)):
    return {
        "object": "list",
        "data": [
            {"id": "tts-1",    "object": "model", "created": 0, "owned_by": "microsoft-edge"},
            {"id": "tts-1-hd", "object": "model", "created": 0, "owned_by": "microsoft-edge"},
            {"id": "edge-tts", "object": "model", "created": 0, "owned_by": "microsoft-edge"},
        ],
    }


@app.get("/v1/voices")
async def list_voices(
    locale: Optional[str] = Query(
        default=None,
        description="Filter by locale prefix, e.g. zh-CN, zh, en-US.",
    ),
    refresh: bool = Query(default=False, description="Refresh the catalog from Microsoft."),
    _auth: None = Depends(_verify_api_key),
):
    refreshed = None
    if refresh:
        refreshed = await _refresh_voices()

    voices = _voices
    if locale:
        prefix = locale.strip().lower()
        voices = [
            v for v in voices
            if str(v.get("Locale", "")).lower().startswith(prefix)
        ]

    data = [_public_voice(v) for v in voices]
    return {
        "object": "list",
        "data": data,
        # Compatibility with the Kokoro server's response shape.
        "voices": [
            {
                "id": v["id"],
                "description": " / ".join(filter(None, [
                    v.get("locale_name") or v.get("locale"),
                    v.get("gender"),
                    ", ".join(v.get("voice_personalities") or []),
                ])),
            }
            for v in data
        ],
        "openai_aliases": OPENAI_ALIASES,
        "short_aliases": EXTRA_ALIASES,
        "updated": _voices_updated,
        "refreshed": refreshed,
    }


@app.post("/v1/audio/speech")
async def create_speech(
    req: SpeechRequest,
    _auth: None = Depends(_verify_api_key),
):
    if req.response_format not in _FORMAT_MIME:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid response_format '{req.response_format}'. "
                f"Must be one of: {', '.join(sorted(_FORMAT_MIME))}"
            ),
        )
    if not req.input.strip():
        raise HTTPException(status_code=400, detail="'input' must not be empty.")

    voice = _resolve_voice(req.voice)

    speed = req.speed if req.speed is not None and req.speed != 1.0 else DEFAULT_SPEED
    rate = _rate_percent(speed)
    volume = _volume_percent(req.volume_multiplier)
    pitch = _pitch_hz(req.pitch)

    logger.info(
        "Synthesizing %d chars | voice=%s rate=%s volume=%s pitch=%s "
        "format=%s stream_format=%s",
        len(req.input), voice, rate, volume, pitch,
        req.response_format, req.stream_format,
    )

    def _chunks() -> AsyncIterator[bytes]:
        return _edge_audio_chunks(req.input, voice, rate, volume, pitch)

    if req.stream_format == "sse":
        return StreamingResponse(
            _stream_sse(_chunks(), req.response_format),
            media_type="text/event-stream",
            headers={
                "X-Accel-Buffering": "no",
                "Cache-Control": "no-cache",
            },
        )

    if req.stream_format == "audio":
        return StreamingResponse(
            _stream_converted(_chunks(), req.response_format),
            media_type=_FORMAT_MIME[req.response_format],
            headers={
                "X-Accel-Buffering": "no",
                "Cache-Control": "no-cache",
            },
        )

    try:
        buf = bytearray()
        async for chunk in _chunks():
            buf.extend(chunk)
        if not buf:
            raise RuntimeError("Edge TTS returned no audio.")
        audio = await asyncio.get_running_loop().run_in_executor(
            None, _ffmpeg_convert, bytes(buf), req.response_format
        )
    except HTTPException:
        raise
    except Exception as exc:  # noqa: BLE001
        logger.exception("Speech synthesis failed: %s", exc)
        raise HTTPException(
            status_code=502,
            detail=f"Edge TTS synthesis failed: {exc}",
        ) from exc

    return Response(content=audio, media_type=_FORMAT_MIME[req.response_format])


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("EDGE_PORT", "8884"))
    uvicorn.run(
        "api_server:app",
        host="0.0.0.0",
        port=port,
        log_level=_log_level_str.lower(),
        workers=1,
    )
