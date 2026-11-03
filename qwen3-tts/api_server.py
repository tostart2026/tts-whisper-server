#!/usr/bin/env python3
"""
Qwen3-TTS API Server
Provides an OpenAI-compatible /v1/audio/speech endpoint backed by the local
Qwen3-TTS models (CustomVoice / VoiceDesign / Base voice-clone).

The server loads exactly one model (selected with QWEN3_TTS_MODEL) and exposes
the task that model supports:

  * CustomVoice  -> generate_custom_voice()   (predefined speakers)
  * VoiceDesign  -> generate_voice_design()   (natural-language voice design)
  * Base         -> generate_voice_clone()    (3-second voice clone)

Notes
-----
* Model weights are loaded lazily at startup and cached. They can be downloaded
  ahead of time with download_models.sh.
* A GPU is strongly recommended. The default model is the 0.6B CustomVoice
  variant so it fits on 8 GB cards.
* Non-WAV formats and speed/volume post-processing require ffmpeg on PATH.
"""

import asyncio
import base64
import json
import logging
import os
import subprocess
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any, AsyncIterator, Literal, Optional, Union

import numpy as np
import uvicorn
from fastapi import (
    Depends,
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Query,
    UploadFile,
)
from fastapi.responses import Response, StreamingResponse
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_log_level_str = os.environ.get("QWEN3_TTS_LOG_LEVEL", "INFO").upper()
_log_level = getattr(logging, _log_level_str, logging.INFO)
logging.basicConfig(
    level=_log_level,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger("qwen3_tts_server")

HERE = Path(__file__).resolve().parent
DATA_DIR = Path(os.environ.get("QWEN3_TTS_DATA", str(HERE / "models")))
DATA_DIR.mkdir(parents=True, exist_ok=True)

MODEL_NAME = os.environ.get(
    "QWEN3_TTS_MODEL", "Qwen/Qwen3-TTS-12Hz-0.6B-CustomVoice"
)
DEVICE = os.environ.get("QWEN3_TTS_DEVICE", "auto").strip() or "auto"
DTYPE = os.environ.get("QWEN3_TTS_DTYPE", "").strip()
ATTN_IMPL = os.environ.get("QWEN3_TTS_ATTN", "").strip()
DEFAULT_LANGUAGE = os.environ.get("QWEN3_TTS_LANGUAGE", "Auto").strip() or "Auto"
DEFAULT_SPEAKER = os.environ.get("QWEN3_TTS_SPEAKER", "").strip()
DEFAULT_FORMAT = os.environ.get("QWEN3_TTS_FORMAT", "wav").strip().lower() or "wav"
MAX_CHARS = int(os.environ.get("QWEN3_TTS_MAX_CHARS", "4096"))
MAX_NEW_TOKENS = int(os.environ.get("QWEN3_TTS_MAX_NEW_TOKENS", "2048"))
MAX_CONCURRENCY = max(1, int(os.environ.get("QWEN3_TTS_MAX_CONCURRENCY", "1")))
FFMPEG_TIMEOUT = int(os.environ.get("QWEN3_TTS_FFMPEG_TIMEOUT", "300"))

_FORMAT_MIME = {
    "mp3": "audio/mpeg",
    "wav": "audio/wav",
    "flac": "audio/flac",
    "opus": "audio/ogg; codecs=opus",
    "aac": "audio/aac",
    "pcm": "audio/pcm",
}

_FFMPEG_OUTPUT_ARGS = {
    "mp3": ["-c:a", "libmp3lame", "-b:a", "128k", "-f", "mp3"],
    "wav": ["-c:a", "pcm_s16le", "-f", "wav"],
    "flac": ["-c:a", "flac", "-f", "flac"],
    "opus": ["-c:a", "libopus", "-b:a", "48k", "-f", "ogg"],
    "aac": ["-c:a", "aac", "-b:a", "128k", "-f", "adts"],
    "pcm": ["-f", "s16le"],
}

# Qwen3-TTS supported language names, plus ISO-code convenience mappings.
_LANGUAGE_NAMES = {
    "chinese": "Chinese",
    "english": "English",
    "japanese": "Japanese",
    "korean": "Korean",
    "german": "German",
    "french": "French",
    "russian": "Russian",
    "portuguese": "Portuguese",
    "spanish": "Spanish",
    "italian": "Italian",
}
_LANGUAGE_CODES = {
    "zh": "Chinese",
    "en": "English",
    "ja": "Japanese",
    "ko": "Korean",
    "de": "German",
    "fr": "French",
    "ru": "Russian",
    "pt": "Portuguese",
    "es": "Spanish",
    "it": "Italian",
}
_LANGUAGE_CODE_BY_NAME = {
    "chinese": "zh",
    "english": "en",
    "japanese": "ja",
    "korean": "ko",
    "german": "de",
    "french": "fr",
    "russian": "ru",
    "portuguese": "pt",
    "spanish": "es",
    "italian": "it",
}

# Canonical speaker names and descriptions (CustomVoice models).
_SPEAKER_INFO = {
    "vivian": ("Vivian", "Bright, slightly edgy young female voice.", "Chinese"),
    "serena": ("Serena", "Warm, gentle young female voice.", "Chinese"),
    "uncle_fu": ("Uncle_Fu", "Seasoned male voice with a low, mellow timbre.", "Chinese"),
    "dylan": ("Dylan", "Youthful Beijing male voice with a clear, natural timbre.", "Chinese (Beijing Dialect)"),
    "eric": ("Eric", "Lively Chengdu male voice with a slightly husky brightness.", "Chinese (Sichuan Dialect)"),
    "ryan": ("Ryan", "Dynamic male voice with strong rhythmic drive.", "English"),
    "aiden": ("Aiden", "Sunny American male voice with a clear midrange.", "English"),
    "ono_anna": ("Ono_Anna", "Playful Japanese female voice with a light, nimble timbre.", "Japanese"),
    "sohee": ("Sohee", "Warm Korean female voice with rich emotion.", "Korean"),
}

# ---------------------------------------------------------------------------
# Task / model helpers
# ---------------------------------------------------------------------------

_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="qwen3-tts")


def _detect_task(model_name: str) -> str:
    name = model_name.lower()
    if "voicedesign" in name or "voice_design" in name or "voice-design" in name:
        return "voice_design"
    if "customvoice" in name or "custom_voice" in name or "custom-voice" in name:
        return "custom_voice"
    if name.endswith("base") or "-base" in name:
        return "voice_clone"
    return "custom_voice"


TASK = (os.environ.get("QWEN3_TTS_TASK", "").strip().lower() or _detect_task(MODEL_NAME))
if TASK not in ("custom_voice", "voice_design", "voice_clone"):
    TASK = _detect_task(MODEL_NAME)

# The 0.6B CustomVoice checkpoints do not support instruction control.
INSTRUCT_SUPPORTED = not ("0.6b" in MODEL_NAME.lower() and TASK == "custom_voice")

# Global model handles.
_model: Any = None
_model_error: Optional[str] = None
_model_lock = threading.Lock()
_sample_rate: Optional[int] = None
_supported_speakers: list[str] = []
_supported_languages: list[str] = []
_model_dtype: Optional[str] = None


def _resolve_dtype():
    import torch

    if DTYPE:
        value = DTYPE.lower()
        mapping = {
            "float32": torch.float32,
            "fp32": torch.float32,
            "float16": torch.float16,
            "fp16": torch.float16,
            "bfloat16": torch.bfloat16,
            "bf16": torch.bfloat16,
        }
        if value not in mapping:
            raise ValueError(
                f"Unknown QWEN3_TTS_DTYPE '{DTYPE}'. "
                "Use float32, float16 or bfloat16."
            )
        return mapping[value]

    if DEVICE == "cpu":
        return torch.float32
    if DEVICE.startswith("cuda") or DEVICE == "auto":
        if torch.cuda.is_available():
            return torch.bfloat16
    return torch.float32


def _load_model() -> None:
    global _model, _model_error, _sample_rate, _supported_speakers
    global _supported_languages, _model_dtype

    with _model_lock:
        if _model is not None:
            return
        logger.info(
            "Loading Qwen3-TTS model=%s task=%s device=%s attn=%s",
            MODEL_NAME, TASK, DEVICE, ATTN_IMPL or "default",
        )
        try:
            from qwen_tts import Qwen3TTSModel

            kwargs: dict[str, Any] = {}
            if DEVICE != "auto":
                kwargs["device_map"] = DEVICE
            else:
                kwargs["device_map"] = "auto"
            dtype = _resolve_dtype()
            kwargs["dtype"] = dtype
            if ATTN_IMPL:
                kwargs["attn_implementation"] = ATTN_IMPL

            model = Qwen3TTSModel.from_pretrained(MODEL_NAME, **kwargs)
            _model = model
            _model_dtype = str(dtype)
            _model_error = None

            try:
                speakers = model.get_supported_speakers() or []
                _supported_speakers = [str(s) for s in speakers]
            except Exception as exc:  # noqa: BLE001
                logger.warning("Could not read supported speakers: %s", exc)
                _supported_speakers = []

            try:
                languages = model.get_supported_languages() or []
                _supported_languages = [str(s) for s in languages]
            except Exception as exc:  # noqa: BLE001
                logger.warning("Could not read supported languages: %s", exc)
                _supported_languages = []

            logger.info(
                "Qwen3-TTS ready | task=%s dtype=%s speakers=%d languages=%d",
                TASK, _model_dtype, len(_supported_speakers),
                len(_supported_languages),
            )
        except Exception as exc:  # noqa: BLE001
            _model_error = f"{type(exc).__name__}: {exc}"
            logger.exception("Failed to load Qwen3-TTS model: %s", exc)


def _canonical_speakers() -> list[dict[str, str]]:
    items: list[dict[str, str]] = []
    if _supported_speakers:
        for raw in _supported_speakers:
            key = raw.lower()
            if key in _SPEAKER_INFO:
                name, desc, lang = _SPEAKER_INFO[key]
            else:
                name, desc, lang = raw, "", ""
            items.append({"id": name, "description": desc, "language": lang})
        return items
    # Fall back to the documented list when the model does not report speakers.
    for name, desc, lang in _SPEAKER_INFO.values():
        items.append({"id": name, "description": desc, "language": lang})
    return items


def _canonical_languages() -> list[dict[str, str]]:
    if _supported_languages:
        out = []
        for raw in _supported_languages:
            key = raw.lower()
            name = _LANGUAGE_NAMES.get(key, raw)
            out.append({"code": _LANGUAGE_CODE_BY_NAME.get(name.lower(), ""), "name": name})
        return out
    return [
        {"code": code, "name": name}
        for name, code in _LANGUAGE_CODE_BY_NAME.items()
    ]


def _default_speaker() -> str:
    if DEFAULT_SPEAKER:
        return DEFAULT_SPEAKER
    speakers = _canonical_speakers()
    if speakers:
        return speakers[0]["id"]
    return "Vivian"


def _normalize_language(language: Optional[str]) -> str:
    if not language:
        return DEFAULT_LANGUAGE
    value = str(language).strip()
    if not value or value.lower() in ("auto", "automatic", "自动"):
        return "Auto"
    key = value.lower()
    if key in _LANGUAGE_NAMES:
        return _LANGUAGE_NAMES[key]
    if key in _LANGUAGE_CODES:
        return _LANGUAGE_CODES[key]
    return value


# ---------------------------------------------------------------------------
# Audio post-processing (numpy -> requested format)
# ---------------------------------------------------------------------------


def _atempo_filters(speed: float) -> list[str]:
    if abs(speed - 1.0) < 1e-3:
        return []
    filters: list[str] = []
    value = speed
    while value < 0.5 - 1e-9:
        filters.append("atempo=0.5")
        value /= 0.5
    while value > 2.0 + 1e-9:
        filters.append("atempo=2.0")
        value /= 2.0
    filters.append(f"atempo={value:.6f}")
    return filters


def _encode_audio(
    wav: np.ndarray,
    sample_rate: int,
    fmt: str,
    speed: float = 1.0,
    volume: float = 1.0,
) -> bytes:
    fmt = (fmt or DEFAULT_FORMAT).lower()
    if fmt not in _FORMAT_MIME:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid response_format '{fmt}'. "
                f"Must be one of: {', '.join(sorted(_FORMAT_MIME))}"
            ),
        )

    audio = np.asarray(wav, dtype=np.float32)
    if audio.ndim == 1:
        audio = audio.reshape(-1, 1)
    if audio.ndim != 2:
        raise HTTPException(status_code=500, detail="Unexpected audio array shape.")
    if audio.shape[1] > audio.shape[0]:
        audio = audio.T
    channels = max(1, int(audio.shape[1]))
    audio = np.clip(audio, -1.0, 1.0)
    pcm = (audio * 32767.0).astype("<i2", copy=False).tobytes()

    filters = _atempo_filters(speed)
    if abs(volume - 1.0) > 1e-3:
        filters.append(f"volume={volume:.4f}")

    cmd = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
        "-f", "s16le", "-ar", str(sample_rate), "-ac", str(channels),
        "-i", "pipe:0",
    ]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += _FFMPEG_OUTPUT_ARGS[fmt]
    cmd += ["pipe:1"]

    try:
        proc = subprocess.run(
            cmd, input=pcm, capture_output=True, timeout=FFMPEG_TIMEOUT
        )
    except FileNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail="ffmpeg is required for audio encoding but was not found on PATH.",
        ) from exc
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(status_code=504, detail="ffmpeg encoding timed out.") from exc

    if proc.returncode != 0:
        detail = proc.stderr.decode("utf-8", "replace").strip()
        raise HTTPException(
            status_code=500,
            detail=f"ffmpeg failed to encode '{fmt}': {detail[:500]}",
        )
    return proc.stdout


# ---------------------------------------------------------------------------
# Inference
# ---------------------------------------------------------------------------


def _run_inference(
    *,
    text: str,
    task: str,
    language: str,
    speaker: Optional[str],
    instruct: Optional[str],
    ref_audio: Optional[str],
    ref_text: Optional[str],
    x_vector_only_mode: bool,
    max_new_tokens: int,
) -> tuple[np.ndarray, int]:
    global _sample_rate

    if _model is None:
        raise HTTPException(
            status_code=503,
            detail=f"Qwen3-TTS model is not loaded. {_model_error or ''}".strip(),
        )

    kwargs: dict[str, Any] = {}
    if max_new_tokens:
        kwargs["max_new_tokens"] = int(max_new_tokens)

    with _model_lock:
        if task == "custom_voice":
            speaker_name = speaker or _default_speaker()
            instruction = instruct or None
            if instruction and not INSTRUCT_SUPPORTED:
                logger.warning(
                    "Model %s does not support instruction control; ignoring instruct.",
                    MODEL_NAME,
                )
                instruction = None
            wavs, sr = _model.generate_custom_voice(
                text=text,
                language=language,
                speaker=speaker_name,
                instruct=instruction,
                **kwargs,
            )
        elif task == "voice_design":
            if not instruct:
                raise HTTPException(
                    status_code=400,
                    detail="VoiceDesign models require a non-empty 'instruct' field.",
                )
            wavs, sr = _model.generate_voice_design(
                text=text,
                language=language,
                instruct=instruct,
                **kwargs,
            )
        elif task == "voice_clone":
            if not ref_audio:
                raise HTTPException(
                    status_code=400,
                    detail="VoiceClone models require 'ref_audio' (path/URL/base64).",
                )
            if not x_vector_only_mode and not ref_text:
                raise HTTPException(
                    status_code=400,
                    detail=(
                        "VoiceClone models require 'ref_text' unless "
                        "x_vector_only_mode=true."
                    ),
                )
            wavs, sr = _model.generate_voice_clone(
                text=text,
                language=language,
                ref_audio=ref_audio,
                ref_text=ref_text or None,
                x_vector_only_mode=bool(x_vector_only_mode),
                **kwargs,
            )
        else:
            raise HTTPException(status_code=400, detail=f"Unknown task '{task}'.")

    if not wavs:
        raise HTTPException(status_code=500, detail="Model returned no audio.")
    _sample_rate = int(sr)
    return np.asarray(wavs[0], dtype=np.float32), int(sr)


async def _synthesize(
    *,
    text: str,
    task: str,
    language: Optional[str],
    speaker: Optional[str],
    instruct: Optional[str],
    ref_audio: Optional[str],
    ref_text: Optional[str],
    x_vector_only_mode: bool,
    max_new_tokens: int,
) -> tuple[np.ndarray, int]:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        _executor,
        lambda: _run_inference(
            text=text,
            task=task,
            language=_normalize_language(language),
            speaker=speaker,
            instruct=instruct,
            ref_audio=ref_audio,
            ref_text=ref_text,
            x_vector_only_mode=x_vector_only_mode,
            max_new_tokens=max_new_tokens,
        ),
    )


# ---------------------------------------------------------------------------
# Streaming helpers
# ---------------------------------------------------------------------------


def _chunk_bytes(data: bytes, size: int = 32 * 1024) -> list[bytes]:
    return [data[i:i + size] for i in range(0, len(data), size)]


def _sse_audio_delta(audio_bytes: bytes) -> str:
    payload = json.dumps({
        "type": "speech.audio.delta",
        "audio": base64.b64encode(audio_bytes).decode("ascii"),
    })
    return f"data: {payload}\n\n"


async def _stream_audio(data: bytes) -> AsyncIterator[bytes]:
    for chunk in _chunk_bytes(data):
        yield chunk


async def _stream_sse(data: bytes) -> AsyncIterator[str]:
    for chunk in _chunk_bytes(data):
        yield _sse_audio_delta(chunk)
    yield f'data: {json.dumps({"type": "speech.audio.done"})}\n\n'
    yield "data: [DONE]\n\n"


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------


@asynccontextmanager
async def _lifespan(app: FastAPI):
    await asyncio.to_thread(_load_model)
    yield


app = FastAPI(
    title="Qwen3-TTS",
    description=(
        "OpenAI-compatible text-to-speech API backed by local Qwen3-TTS "
        "CustomVoice / VoiceDesign / Base models."
    ),
    version="1.0.0",
    lifespan=_lifespan,
)


def _verify_api_key(authorization: Optional[str] = Header(default=None)) -> None:
    required = os.environ.get("QWEN3_TTS_API_KEY", "").strip()
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
    id: str = Field(..., description="Speaker name for CustomVoice models.")


class SpeechRequest(BaseModel):
    model: str = Field(
        default="qwen3-tts",
        description="Model identifier. 'tts-1', 'tts-1-hd' and 'qwen3-tts' are accepted.",
    )
    input: str = Field(
        ...,
        max_length=MAX_CHARS,
        description=f"The text to synthesize. Maximum {MAX_CHARS} characters.",
    )
    voice: Union[str, VoiceReference, None] = Field(
        default=None,
        description=(
            "Speaker name for CustomVoice models (alias of 'speaker'). "
            "See GET /v1/voices."
        ),
    )
    speaker: Optional[str] = Field(
        default=None,
        description="Speaker name for CustomVoice models.",
    )
    language: Optional[str] = Field(
        default=None,
        description="Language name or ISO code (zh/en/ja/...). Default: Auto.",
    )
    instruct: Optional[str] = Field(
        default=None,
        max_length=4096,
        description=(
            "Natural-language style instruction. Required for VoiceDesign "
            "models; optional for CustomVoice (1.7B only)."
        ),
    )
    task: Optional[Literal["custom_voice", "voice_design", "voice_clone"]] = Field(
        default=None,
        description="Override the task of the loaded model (normally not needed).",
    )
    ref_audio: Optional[str] = Field(
        default=None,
        description=(
            "Reference audio for VoiceClone models: local path, URL, or base64. "
            "Use POST /v1/audio/clone to upload a file instead."
        ),
    )
    ref_text: Optional[str] = Field(
        default=None,
        description="Transcript of ref_audio (required for VoiceClone ICL mode).",
    )
    x_vector_only_mode: bool = Field(
        default=False,
        description="VoiceClone: use speaker embedding only (ref_text not needed).",
    )
    response_format: Optional[Literal["mp3", "wav", "flac", "opus", "aac", "pcm"]] = Field(
        default=DEFAULT_FORMAT,
        description="Audio output format.",
    )
    speed: float = Field(
        default=1.0,
        ge=0.25,
        le=4.0,
        description="Post-processing speech rate, 0.25-4.0 (1.0 = unchanged).",
    )
    volume_multiplier: float = Field(
        default=1.0,
        ge=0.1,
        le=2.0,
        description="Post-processing volume multiplier, 0.1-2.0.",
    )
    max_new_tokens: Optional[int] = Field(
        default=None,
        ge=1,
        le=8192,
        description="Maximum number of generated codec tokens.",
    )
    stream_format: Optional[Literal["sse", "audio"]] = Field(
        default=None,
        description=(
            "Return the synthesized audio as chunked transfer ('audio') or "
            "OpenAI-style SSE speech.audio.delta events ('sse')."
        ),
    )


@app.get("/health", include_in_schema=False)
async def health():
    return {
        "status": "ok" if _model is not None else "error",
        "engine": "qwen3-tts",
        "model": MODEL_NAME,
        "task": TASK,
        "device": DEVICE,
        "dtype": _model_dtype,
        "loaded": _model is not None,
        "error": _model_error,
        "sample_rate": _sample_rate,
        "speakers": len(_canonical_speakers()) if TASK == "custom_voice" else 0,
        "languages": len(_canonical_languages()),
        "instruct_supported": INSTRUCT_SUPPORTED if TASK == "custom_voice" else True,
    }


@app.get("/v1/models")
async def list_models(_auth: None = Depends(_verify_api_key)):
    return {
        "object": "list",
        "data": [
            {"id": "tts-1", "object": "model", "created": 0, "owned_by": "qwen"},
            {"id": "tts-1-hd", "object": "model", "created": 0, "owned_by": "qwen"},
            {
                "id": "qwen3-tts",
                "object": "model",
                "created": 0,
                "owned_by": "qwen",
                "task": TASK,
                "checkpoint": MODEL_NAME,
            },
        ],
    }


@app.get("/v1/voices")
async def list_voices(
    language: Optional[str] = Query(
        default=None,
        description="Filter speakers by language name or ISO code.",
    ),
    _auth: None = Depends(_verify_api_key),
):
    speakers = [] if TASK != "custom_voice" else _canonical_speakers()
    if language:
        wanted = _normalize_language(language).lower()
        speakers = [
            s for s in speakers
            if not s.get("language") or s["language"].lower().startswith(wanted)
        ]

    return {
        "object": "list",
        "task": TASK,
        "model": MODEL_NAME,
        "data": speakers,
        # Compatibility with the Kokoro/Edge server response shape.
        "voices": [
            {"id": s["id"], "description": s.get("description", "")}
            for s in speakers
        ],
        "languages": _canonical_languages(),
        "default_voice": _default_speaker() if TASK == "custom_voice" else None,
        "instruct_supported": INSTRUCT_SUPPORTED if TASK == "custom_voice" else True,
    }


async def _respond(
    *,
    text: str,
    task: str,
    fmt: str,
    stream_format: Optional[str],
    language: Optional[str],
    speaker: Optional[str],
    instruct: Optional[str],
    ref_audio: Optional[str],
    ref_text: Optional[str],
    x_vector_only_mode: bool,
    max_new_tokens: int,
    speed: float,
    volume_multiplier: float,
) -> Response:
    if task not in ("custom_voice", "voice_design", "voice_clone"):
        raise HTTPException(status_code=400, detail=f"Unknown task '{task}'.")

    wav, sample_rate = await _synthesize(
        text=text,
        task=task,
        language=language,
        speaker=speaker,
        instruct=instruct,
        ref_audio=ref_audio,
        ref_text=ref_text,
        x_vector_only_mode=x_vector_only_mode,
        max_new_tokens=max_new_tokens,
    )
    audio = await asyncio.to_thread(
        _encode_audio, wav, sample_rate, fmt, speed, volume_multiplier
    )

    headers = {
        "X-Model": MODEL_NAME,
        "X-Task": task,
        "X-Sample-Rate": str(sample_rate),
    }

    if stream_format == "audio":
        return StreamingResponse(
            _stream_audio(audio),
            media_type=_FORMAT_MIME[fmt],
            headers={**headers, "Cache-Control": "no-cache"},
        )
    if stream_format == "sse":
        return StreamingResponse(
            _stream_sse(audio),
            media_type="text/event-stream",
            headers={**headers, "X-Accel-Buffering": "no", "Cache-Control": "no-cache"},
        )
    return Response(content=audio, media_type=_FORMAT_MIME[fmt], headers=headers)


@app.post("/v1/audio/speech")
async def create_speech(
    req: SpeechRequest,
    _auth: None = Depends(_verify_api_key),
):
    if not req.input.strip():
        raise HTTPException(status_code=400, detail="'input' must not be empty.")

    task = (req.task or TASK).strip().lower()
    fmt = (req.response_format or DEFAULT_FORMAT).lower()
    if fmt not in _FORMAT_MIME:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid response_format '{fmt}'. "
                f"Must be one of: {', '.join(sorted(_FORMAT_MIME))}"
            ),
        )

    speaker = req.speaker
    if not speaker and isinstance(req.voice, str):
        speaker = req.voice
    elif not speaker and isinstance(req.voice, VoiceReference):
        speaker = req.voice.id

    return await _respond(
        text=req.input.strip(),
        task=task,
        fmt=fmt,
        stream_format=req.stream_format,
        language=req.language,
        speaker=speaker,
        instruct=req.instruct,
        ref_audio=req.ref_audio,
        ref_text=req.ref_text,
        x_vector_only_mode=req.x_vector_only_mode,
        max_new_tokens=req.max_new_tokens or MAX_NEW_TOKENS,
        speed=req.speed,
        volume_multiplier=req.volume_multiplier,
    )


@app.post("/v1/audio/clone")
async def create_speech_clone(
    file: UploadFile = File(..., description="Reference audio clip (wav/mp3/...)."),
    input: str = Form(..., description="Text to synthesize."),
    language: Optional[str] = Form(default=None),
    ref_text: Optional[str] = Form(default=None),
    x_vector_only_mode: bool = Form(default=False),
    response_format: Optional[str] = Form(default=DEFAULT_FORMAT),
    speed: float = Form(default=1.0),
    volume_multiplier: float = Form(default=1.0),
    max_new_tokens: Optional[int] = Form(default=None),
    stream_format: Optional[str] = Form(default=None),
    _auth: None = Depends(_verify_api_key),
):
    if TASK != "voice_clone":
        raise HTTPException(
            status_code=400,
            detail=f"Loaded model task is '{TASK}', not 'voice_clone'.",
        )
    if not input.strip():
        raise HTTPException(status_code=400, detail="'input' must not be empty.")
    if not x_vector_only_mode and not ref_text:
        raise HTTPException(
            status_code=400,
            detail="'ref_text' is required unless x_vector_only_mode=true.",
        )

    fmt = (response_format or DEFAULT_FORMAT).lower()
    if fmt not in _FORMAT_MIME:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Invalid response_format '{fmt}'. "
                f"Must be one of: {', '.join(sorted(_FORMAT_MIME))}"
            ),
        )

    suffix = Path(file.filename or "ref.wav").suffix or ".wav"
    tmp_path: Optional[str] = None
    try:
        contents = await file.read()
        with tempfile.NamedTemporaryFile(
            delete=False, suffix=suffix, dir=str(DATA_DIR)
        ) as tmp:
            tmp.write(contents)
            tmp_path = tmp.name

        return await _respond(
            text=input.strip(),
            task="voice_clone",
            fmt=fmt,
            stream_format=stream_format,
            language=language,
            speaker=None,
            instruct=None,
            ref_audio=tmp_path,
            ref_text=ref_text,
            x_vector_only_mode=x_vector_only_mode,
            max_new_tokens=max_new_tokens or MAX_NEW_TOKENS,
            speed=speed,
            volume_multiplier=volume_multiplier,
        )
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass


@app.get("/v1/languages")
async def list_languages(_auth: None = Depends(_verify_api_key)):
    return {
        "task": TASK,
        "languages": _canonical_languages(),
        "default": DEFAULT_LANGUAGE,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    port = int(os.environ.get("QWEN3_TTS_PORT", "8885"))
    uvicorn.run(
        "api_server:app",
        host="0.0.0.0",
        port=port,
        log_level=_log_level_str.lower(),
        workers=1,
    )
