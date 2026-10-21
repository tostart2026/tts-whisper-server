import { getCommonServiceTimeoutMs, getCommonServiceUrl } from "./config.js";

export class CommonServiceError extends Error {
  constructor(message, status = 502, payload = null) {
    super(message);
    this.name = "CommonServiceError";
    this.status = status;
    this.payload = payload;
  }
}

const DEFAULT_CHARACTERS = {
  digitalHuman: "dh0001",
  master: "e2",
  assist: "zm_yunxi",
};

function serviceBase() {
  return getCommonServiceUrl();
}

function authHeaders(token) {
  const headers = { Accept: "application/json" };
  const value = String(token ?? "").trim();
  if (value) {
    headers.Authorization = `Bearer ${value}`;
    headers.Cookie = `common_token=${value}`;
  }
  return headers;
}

function parseJson(text) {
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch {
    return {};
  }
}

async function request(path, { method = "GET", token, body } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), getCommonServiceTimeoutMs());
  try {
    const headers = authHeaders(token);
    const init = { method, headers, signal: controller.signal };
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
      init.body = JSON.stringify(body);
    }

    const response = await fetch(`${serviceBase()}${path}`, init);
    const data = parseJson(await response.text());
    if (!response.ok) {
      const message = data.error || data.message || `公共服务返回 ${response.status}`;
      throw new CommonServiceError(message, response.status, data);
    }
    return data;
  } catch (error) {
    if (error instanceof CommonServiceError) throw error;
    if (error?.name === "AbortError") throw new CommonServiceError("公共服务响应超时", 504);
    throw new CommonServiceError(`公共服务调用失败：${error?.message ?? error}`, 502);
  } finally {
    clearTimeout(timer);
  }
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

function hasUserFields(value) {
  return [
    "appCode",
    "AppCode",
    "app_code",
    "level",
    "role",
    "Role",
    "isAdmin",
    "name",
    "nickname",
    "username",
    "permissions",
  ].some((key) => key in value);
}

function extractUser(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return null;
  const nested = payload.data && typeof payload.data === "object" ? payload.data : null;
  const candidates = [
    payload.user,
    nested?.user,
    payload.profile,
    nested?.profile,
    payload.data,
    payload,
  ];
  for (const candidate of candidates) {
    if (candidate && typeof candidate === "object" && !Array.isArray(candidate) && hasUserFields(candidate)) {
      return candidate;
    }
  }
  return null;
}

function normalizeUser(raw, token) {
  if (!raw) return null;
  const role = String(raw.level ?? raw.role ?? raw.Role ?? "").trim().toLowerCase();
  const isAdmin = raw.isAdmin === true || raw.admin === true || role === "admin";
  const appCode = firstNonEmpty(raw.appCode, raw.AppCode, raw.app_code);
  if (!isAdmin && !appCode) return null;
  return {
    level: role,
    appCode,
    isAdmin,
    permissions: raw.permissions && typeof raw.permissions === "object" ? raw.permissions : {},
    name: firstNonEmpty(raw.name, raw.nickname, raw.username),
    token,
    raw,
  };
}

function normalizeCharacters(input) {
  const source = input && typeof input === "object" ? input : {};
  return {
    digitalHuman:
      firstNonEmpty(
        source.digitalHuman,
        source.DigitalHumanCharacter,
        source.digitalHumanCharacter,
      ) || DEFAULT_CHARACTERS.digitalHuman,
    master:
      firstNonEmpty(source.master, source.MasterCharacter, source.masterCharacter) ||
      DEFAULT_CHARACTERS.master,
    assist:
      firstNonEmpty(source.assist, source.AssistCharacter, source.assistCharacter) ||
      DEFAULT_CHARACTERS.assist,
  };
}

function normalizeVoices(input) {
  if (!Array.isArray(input)) return [];
  const voices = [];
  for (const entry of input) {
    if (!entry || typeof entry !== "object") continue;
    const role = firstNonEmpty(entry.role, entry.Role).toLowerCase();
    const doc =
      entry.doc && typeof entry.doc === "object"
        ? entry.doc
        : entry.document && typeof entry.document === "object"
          ? entry.document
          : entry;
    if (role && doc) voices.push({ role, doc });
  }
  return voices;
}

export async function verifyToken(token) {
  const value = String(token ?? "").trim();
  if (!value) return null;
  try {
    const data = await request("/api/auth/verify", {
      method: "POST",
      body: { token: value },
    });
    return normalizeUser(extractUser(data), value);
  } catch (error) {
    if (error instanceof CommonServiceError && (error.status === 401 || error.status === 403)) {
      return null;
    }
    throw error;
  }
}

export async function getUserInfo(token) {
  const value = String(token ?? "").trim();
  if (!value) return null;
  const data = await request("/api/auth/me", { token: value });
  return normalizeUser(extractUser(data), value);
}

export async function getUserVoiceDocs(token, appCode) {
  const value = String(token ?? "").trim();
  const query = appCode ? `?appCode=${encodeURIComponent(appCode)}` : "";
  const data = await request(`/api/user/voices${query}`, { token: value });
  const source =
    data.data && typeof data.data === "object" && !Array.isArray(data.data) ? data.data : data;
  return {
    characters: normalizeCharacters(source.characters ?? source.Characters),
    voices: normalizeVoices(source.voices ?? source.Voices),
  };
}

export async function checkCommonService() {
  try {
    const response = await fetch(`${serviceBase()}/health`, {
      signal: AbortSignal.timeout(3000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
