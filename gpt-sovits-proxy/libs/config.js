export function envStr(name) {
  return (process.env[name] || "").trim();
}

export function envNum(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value.trim() === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function getProxyHost() {
  return envStr("DIGITALMAN_PROXY_HOST") || "0.0.0.0";
}

export function getProxyPort() {
  return envNum("DIGITALMAN_PROXY_PORT", 8883);
}

export function getRequestTimeoutMs() {
  return envNum("DIGITALMAN_TIMEOUT", 600) * 1000;
}

export function getUserServiceUrl() {
  return envStr("USER_SERVICE_URL") || "http://127.0.0.1:8080";
}

export function getUserServiceToken() {
  return envStr("USER_SERVICE_TOKEN");
}

export function getUserServiceTimeoutMs() {
  return envNum("USER_SERVICE_TIMEOUT", 10) * 1000;
}

export function getRedisUrl() {
  return envStr("REDIS_URL") || "redis://192.168.168.33:6379";
}

export function getVoiceScheme() {
  return envStr("VOICE_SCHEME") || "http";
}

export function getVoiceHost() {
  return envStr("VOICE_HOST") || "192.168.168.60";
}

export function getVoicePortFallback() {
  return envNum("VOICE_PORT", 60002);
}

export function getVoiceTtsPath() {
  const path = envStr("VOICE_TTS_PATH") || "/tts";
  return path.startsWith("/") ? path : `/${path}`;
}
