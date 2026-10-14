import {
  getRequestTimeoutMs,
  getVoiceHost,
  getVoicePortFallback,
  getVoiceScheme,
  getVoiceTtsPath,
} from "./config.js";

export class VoiceError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.name = "VoiceError";
    this.status = status;
  }
}

function toPort(value) {
  const parsed = typeof value === "number" ? value : Number(String(value ?? "").trim());
  return Number.isInteger(parsed) && parsed > 0 && parsed <= 65535 ? parsed : getVoicePortFallback();
}

export function voiceBase(doc) {
  const raw = String(doc.TtsBaseUrl ?? doc.TtsServerUrl ?? "").trim();
  if (!raw || /^\d+$/.test(raw)) {
    return `${getVoiceScheme()}://${getVoiceHost()}:${toPort(raw)}`;
  }
  if (/^https?:\/\//i.test(raw)) return raw.replace(/\/+$/, "");
  return `${getVoiceScheme()}://${raw.replace(/\/+$/, "")}`;
}

function authHeaders() {
  const header = (process.env.VOICE_AUTH_HEADER || "").trim();
  const token = (process.env.VOICE_AUTH_TOKEN || "").trim();
  if (header && token) return { [header]: token };
  return {};
}

function providerKind(doc) {
  const provider = String(doc.TtsProvider ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");
  if (provider.includes("kokoro")) return "kokoro";
  if (provider.includes("gpt") || provider.includes("sovits") || provider.includes("svoits")) {
    return "gptsovits";
  }
  return "";
}

function isUrlService(doc) {
  const kind = providerKind(doc);
  if (kind) return kind === "kokoro";
  const base = String(doc.TtsBaseUrl ?? doc.TtsServerUrl ?? "").trim();
  return /^https?:\/\//i.test(base);
}

function hasValue(value) {
  return value !== undefined && value !== null && String(value).trim() !== "";
}

function numeric(value) {
  const raw = String(value).trim();
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : raw;
}

function buildSovitsBody(doc, text) {
  const body = { text };
  if (hasValue(doc.TextLanguage)) body.text_lang = String(doc.TextLanguage).trim();
  if (hasValue(doc.InferenceVoicePath)) body.ref_audio_path = String(doc.InferenceVoicePath).trim();
  if (hasValue(doc.InferenceVoiceText)) body.prompt_text = String(doc.InferenceVoiceText).trim();
  if (hasValue(doc.InferenceLanguage)) body.prompt_lang = String(doc.InferenceLanguage).trim();
  if (hasValue(doc.TextSplitMethod)) body.text_split_method = String(doc.TextSplitMethod).trim();
  if (hasValue(doc.VoiceSpeed)) body.speed_factor = numeric(doc.VoiceSpeed);
  if (hasValue(doc.FragmentInterval)) body.fragment_interval = numeric(doc.FragmentInterval);
  if (hasValue(doc.Seed)) body.seed = numeric(doc.Seed);
  if (hasValue(doc.TtsFormat)) body.media_type = String(doc.TtsFormat).trim();
  return body;
}

function buildKokoroBody(doc, text) {
  const body = { input: text };
  if (hasValue(doc.TtsProvider)) body.model = String(doc.TtsProvider).trim();
  if (hasValue(doc.Model)) body.voice = String(doc.Model).trim();
  if (hasValue(doc.TtsFormat)) body.response_format = String(doc.TtsFormat).trim();
  if (hasValue(doc.VoiceSpeed)) body.speed = numeric(doc.VoiceSpeed);
  if (hasValue(doc.VoiceVolume)) body.volume_multiplier = numeric(doc.VoiceVolume);
  return body;
}

export function buildVoiceRequest(doc, text) {
  if (!isUrlService(doc)) {
    return {
      method: "POST",
      voiceUrl: `${voiceBase(doc).replace(/\/+$/, "")}${getVoiceTtsPath()}`,
      body: buildSovitsBody(doc, text),
    };
  }
  const rawPath = String(doc.TtsPath || "").trim();
  const path = rawPath ? (rawPath.startsWith("/") ? rawPath : `/${rawPath}`) : "";
  return {
    method: "POST",
    voiceUrl: `${voiceBase(doc).replace(/\/+$/, "")}${path}`,
    body: buildKokoroBody(doc, text),
  };
}

export async function callVoice(request) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), getRequestTimeoutMs());
  try {
    const headers = { ...authHeaders() };
    const init = { method: request.method, headers };
    if (request.body) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(request.body);
    }
    const response = await fetch(request.voiceUrl, { ...init, signal: controller.signal });
    const body = Buffer.from(await response.arrayBuffer());
    return {
      status: response.status,
      contentType: response.headers.get("content-type") || "application/octet-stream",
      body,
    };
  } catch (error) {
    if (error?.name === "AbortError") throw new VoiceError("声音服务响应超时", 504);
    throw new VoiceError(`声音服务调用失败：${error?.message ?? error}`, 502);
  } finally {
    clearTimeout(timer);
  }
}
