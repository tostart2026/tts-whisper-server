import {
  getUserServiceTimeoutMs,
  getUserServiceToken,
  getUserServiceUrl,
} from "./config.js";

export class UserServiceError extends Error {
  constructor(message, status = 502) {
    super(message);
    this.name = "UserServiceError";
    this.status = status;
  }
}

function serviceBase() {
  return getUserServiceUrl().replace(/\/+$/, "");
}

async function post(path, payload) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), getUserServiceTimeoutMs());
  try {
    const headers = { "Content-Type": "application/json" };
    const token = getUserServiceToken();
    if (token) headers["X-Service-Token"] = token;

    const response = await fetch(`${serviceBase()}${path}`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const text = await response.text();
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch {
        data = {};
      }
    }

    if (!response.ok) {
      if (response.status === 401 || response.status === 403) {
        throw new UserServiceError("用户服务鉴权失败", 502);
      }
      const message = data.error || data.message || `用户服务返回 ${response.status}`;
      throw new UserServiceError(message, response.status);
    }
    return data;
  } catch (error) {
    if (error instanceof UserServiceError) throw error;
    if (error?.name === "AbortError") throw new UserServiceError("用户服务响应超时", 504);
    throw new UserServiceError(`用户服务调用失败：${error?.message ?? error}`, 502);
  } finally {
    clearTimeout(timer);
  }
}

export async function verifyToken(token) {
  const data = await post("/internal/verify-token", { token });
  return data.user ?? null;
}

export async function getUserVoiceDocs(token, appCode) {
  const data = await post("/internal/user/voices", { token, appCode });
  return {
    characters: data.characters ?? {},
    voices: Array.isArray(data.voices) ? data.voices : [],
  };
}

export async function checkUserService() {
  try {
    const response = await fetch(`${serviceBase()}/health`, {
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}
