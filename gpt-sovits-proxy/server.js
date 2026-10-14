import http from "node:http";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { getUserVoiceDocs } from "./libs/asset-store.js";
import { verifyToken } from "./libs/auth.js";
import {
  AUTH_LOCK_SECONDS,
  clearAuthFailures,
  clientIp,
  getLockSeconds,
  registerAuthFailure,
} from "./libs/auth-guard.js";
import {
  getAuthDbName,
  getDigitalmanDbName,
  getMongoUri,
  getProxyHost,
  getProxyPort,
  getRedisUrl,
  getVoiceHost,
  getVoicePortFallback,
  getVoiceScheme,
} from "./libs/config.js";
import { closeDb, connectDb, isDbConnected } from "./libs/db.js";
import { closeRedis, connectRedis, isRedisReady } from "./libs/redis.js";
import { VoiceError, buildVoiceRequest, callVoice } from "./libs/voice-service.js";

const here = dirname(fileURLToPath(import.meta.url));
try {
  process.loadEnvFile(resolve(here, ".env"));
} catch {}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "*",
  "Access-Control-Allow-Headers": "*",
};

function log(level, message) {
  const line = `[digitalman-proxy] ${message}`;
  if (level === "warn") console.warn(line);
  else console.log(line);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function parseMultipart(buffer, boundary) {
  const data = {};
  const delim = Buffer.from(`--${boundary}`);
  let start = buffer.indexOf(delim);
  while (start !== -1) {
    const next = buffer.indexOf(delim, start + delim.length);
    if (next === -1) break;
    let part = buffer.subarray(start + delim.length, next);
    if (part.subarray(0, 2).toString("latin1") === "\r\n") part = part.subarray(2);
    if (part.subarray(-2).toString("latin1") === "\r\n") part = part.subarray(0, -2);
    const sep = part.indexOf("\r\n\r\n");
    if (sep !== -1) {
      const rawHeaders = part.subarray(0, sep).toString("utf-8");
      const name = /name="([^"]*)"/i.exec(rawHeaders);
      const isFile = /filename=/i.test(rawHeaders);
      if (name && !isFile) data[name[1]] = part.subarray(sep + 4).toString("utf-8");
    }
    start = next;
  }
  return data;
}

async function readParams(req) {
  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
  const data = Object.fromEntries(url.searchParams);
  const ctype = req.headers["content-type"] ?? "";
  const ctypeLower = ctype.toLowerCase();
  const raw = await readBody(req);
  if (ctypeLower.includes("application/json")) {
    try {
      const payload = JSON.parse(raw.toString("utf-8"));
      if (payload && typeof payload === "object" && !Array.isArray(payload)) {
        Object.assign(data, payload);
      }
    } catch {}
  } else if (ctypeLower.includes("form")) {
    if (ctypeLower.includes("multipart/form-data")) {
      const boundary = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(ctype);
      if (boundary) Object.assign(data, parseMultipart(raw, (boundary[1] || boundary[2]).trim()));
    } else {
      for (const [key, value] of new URLSearchParams(raw.toString("utf-8"))) data[key] = value;
    }
  }
  return data;
}

function firstString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function normalizeRole(value) {
  const role = String(value || "").trim().toLowerCase();
  return role === "assist" || role === "assit" ? "assist" : "master";
}

function sanitizeHeaderValue(value) {
  return String(value ?? "").replace(/[^\t\x20-\x7e\x80-\xff]/g, "");
}

function metaHeaders(url, params, status) {
  const headers = {
    "Access-Control-Expose-Headers": "X-DIGITALMAN-Url, X-DIGITALMAN-Params, X-DIGITALMAN-Status",
    "X-DIGITALMAN-Url": sanitizeHeaderValue(url).slice(0, 1024),
    "X-DIGITALMAN-Params": Buffer.from(JSON.stringify(params ?? {}), "utf-8").toString("base64"),
  };
  if (status !== undefined && status !== null) headers["X-DIGITALMAN-Status"] = String(status);
  return headers;
}

function sendJson(res, status, payload, extraHeaders = {}) {
  const body = Buffer.from(JSON.stringify(payload), "utf-8");
  res.writeHead(status, { ...CORS_HEADERS, ...extraHeaders, "Content-Type": "application/json" });
  res.end(body);
}

function sendMessage(res, status, message, extraHeaders = {}) {
  sendJson(res, status, { message }, extraHeaders);
}

function sendApiError(res, message, status = 400) {
  sendJson(res, status, { success: false, error: message });
}

function sendTooMany(res, retryAfter) {
  sendJson(
    res,
    429,
    { success: false, error: `尝试次数过多，请 ${retryAfter} 秒后再试` },
    { "Retry-After": String(retryAfter) },
  );
}

async function resolveUser(req, res, token) {
  const ip = clientIp(req);
  const lockedSeconds = await getLockSeconds(ip);
  if (lockedSeconds > 0) {
    sendTooMany(res, lockedSeconds);
    return null;
  }
  const user = await verifyToken(token);
  if (!user) {
    const locked = await registerAuthFailure(ip);
    if (locked) {
      sendTooMany(res, AUTH_LOCK_SECONDS);
      return null;
    }
    return undefined;
  }
  await clearAuthFailures(ip);
  return user;
}

async function handleGptsovit(req, res) {
  let incoming;
  try {
    incoming = await readParams(req);
  } catch {
    incoming = {};
  }

  const token = String(incoming.token || "").trim();
  const voiceText = String(incoming.voiceText || incoming.text || "").trim();
  const role = normalizeRole(incoming.role || incoming.type);

  if (!token) {
    sendMessage(res, 400, "token is required");
    return;
  }
  if (!voiceText) {
    sendMessage(res, 400, "voiceText is required");
    return;
  }

  let user;
  try {
    user = await resolveUser(req, res, token);
  } catch (error) {
    log("warn", `gptsovit auth error=${error?.message ?? error}`);
    sendMessage(res, 502, `数据查询失败：${error?.message ?? error}`);
    return;
  }
  if (user === null) return;
  if (user === undefined) {
    sendMessage(res, 401, "token 无效、已停用或无应用权限");
    return;
  }

  let docs;
  try {
    docs = await getUserVoiceDocs(token, user.appCode);
  } catch (error) {
    log("warn", `gptsovit voice lookup error=${error?.message ?? error}`);
    sendMessage(res, 502, `数据查询失败：${error?.message ?? error}`);
    return;
  }

  const byRole = new Map(docs.voices.map((entry) => [entry.role, entry.doc]));
  const doc = byRole.get(role);
  if (!doc) {
    const message = docs.voices.length
      ? `该用户未配置 ${role} 音色`
      : `未找到该用户的可用音色：${docs.characters.master} / ${docs.characters.assist}`;
    sendMessage(res, 404, message);
    return;
  }

  const request = buildVoiceRequest(doc, voiceText);
  log(
    "info",
    `digitalman role=${role} character=${String(doc.Character || "").trim()} url=${request.voiceUrl} body=${JSON.stringify(request.body)}`,
  );

  let upstream;
  try {
    upstream = await callVoice(request);
  } catch (error) {
    const status = error instanceof VoiceError ? error.status : 502;
    log("warn", `digitalman url=${request.voiceUrl} error=${error?.message ?? error}`);
    sendMessage(res, status, error?.message ?? String(error), metaHeaders(request.voiceUrl, request.body));
    return;
  }

  log("info", `digitalman url=${request.voiceUrl} status=${upstream.status} bytes=${upstream.body.length}`);
  if (upstream.status !== 200) {
    sendJson(
      res,
      upstream.status,
      { message: "upstream error", detail: upstream.body.toString("utf-8").slice(0, 2000) },
      metaHeaders(request.voiceUrl, request.body, upstream.status),
    );
    return;
  }

  let mediaType = upstream.contentType || "audio/wav";
  if (mediaType.includes("application/json")) mediaType = "audio/wav";
  res.writeHead(200, {
    ...CORS_HEADERS,
    ...metaHeaders(request.voiceUrl, request.body, upstream.status),
    "Content-Type": mediaType,
  });
  res.end(upstream.body);
}

async function handleVoiceAddress(req, res) {
  let incoming;
  try {
    incoming = await readParams(req);
  } catch {
    sendApiError(res, "无效的 JSON 请求体", 400);
    return;
  }

  const token = firstString(incoming.token);
  const voiceText = firstString(incoming.voiceText) || firstString(incoming.text);
  if (!token) {
    sendApiError(res, "缺少 token", 400);
    return;
  }
  if (!voiceText) {
    sendApiError(res, "缺少 voiceText", 400);
    return;
  }

  const ip = clientIp(req);
  const lockedSeconds = await getLockSeconds(ip);
  if (lockedSeconds > 0) {
    sendTooMany(res, lockedSeconds);
    return;
  }

  let user;
  try {
    user = await verifyToken(token);
  } catch (error) {
    sendApiError(res, `数据库查询失败：${error?.message ?? error}`, 502);
    return;
  }
  if (!user) {
    const locked = await registerAuthFailure(ip);
    if (locked) {
      sendTooMany(res, AUTH_LOCK_SECONDS);
      return;
    }
    sendApiError(res, "token 无效、已停用或无应用权限", 401);
    return;
  }
  await clearAuthFailures(ip);

  let docs;
  try {
    docs = await getUserVoiceDocs(token, user.appCode);
  } catch (error) {
    sendApiError(res, `数据库查询失败：${error?.message ?? error}`, 502);
    return;
  }

  if (!docs.voices.length) {
    sendApiError(
      res,
      `未找到该用户的可用音色：${docs.characters.master} / ${docs.characters.assist}`,
      404,
    );
    return;
  }

  const byRole = new Map(docs.voices.map((entry) => [entry.role, entry.doc]));
  const toEntry = (role) => {
    const doc = byRole.get(role);
    if (!doc) return null;
    const request = buildVoiceRequest(doc, voiceText);
    const { _id, ...fields } = doc;
    const entry = {
      role,
      character: String(doc.Character || "").trim(),
      name: String(firstString(doc.Model) || doc.Character || "").trim(),
      provider: String(doc.TtsProvider || "").trim(),
      method: request.method,
      voiceUrl: request.voiceUrl,
      fields,
    };
    if (request.body) entry.body = request.body;
    return entry;
  };

  sendJson(res, 200, {
    success: true,
    digitalHuman: docs.characters.digitalHuman,
    voiceText,
    master: toEntry("master"),
    assist: toEntry("assist"),
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
  const pathname = url.pathname.replace(/\/+$/, "") || "/";

  if (req.method === "OPTIONS") {
    res.writeHead(204, CORS_HEADERS);
    res.end();
    return;
  }

  if (req.method === "GET" && pathname === "/health") {
    sendJson(res, 200, {
      status: "ok",
      service: "gpt-sovits-proxy",
      mongo: isDbConnected(),
      mongodb_db: getAuthDbName(),
      digitalman_db: getDigitalmanDbName(),
      redis: isRedisReady(),
    });
    return;
  }

  if (req.method === "POST" && (pathname === "/gptsovit" || pathname === "/v1/gptsovit")) {
    handleGptsovit(req, res).catch((error) => {
      log("warn", `gptsovit error=${error?.message ?? error}`);
      if (!res.headersSent) sendMessage(res, 500, "Internal Server Error");
      else res.end();
    });
    return;
  }

  if (
    req.method === "POST" &&
    (pathname === "/api/voice/address" || pathname === "/v1/voice/address")
  ) {
    handleVoiceAddress(req, res).catch((error) => {
      log("warn", `voice/address error=${error?.message ?? error}`);
      if (!res.headersSent) sendApiError(res, "Internal Server Error", 500);
      else res.end();
    });
    return;
  }

  sendJson(res, 404, { detail: "Not Found" });
});

async function bootstrap() {
  const host = getProxyHost();
  const port = getProxyPort();

  console.log("Starting Digital Man voice proxy (Node.js)");
  console.log(`  Listen:     ${host}:${port}`);
  console.log(`  MongoDB:    ${getMongoUri()}`);
  console.log(`  DB:         ${getAuthDbName()} / ${getDigitalmanDbName()}`);
  console.log(`  Redis:      ${getRedisUrl()}`);
  console.log(
    `  Voice:      ${getVoiceScheme()}://${getVoiceHost()}:{TtsBaseUrl|${getVoicePortFallback()}}`,
  );

  try {
    await connectDb();
    console.log("MongoDB 已连接");
  } catch (error) {
    console.warn(`MongoDB 连接失败（将在请求时重试）：${error?.message ?? error}`);
  }

  const redisOk = await connectRedis();
  console.log(redisOk ? "Redis 就绪（token 限流启用）" : "Redis 不可用，token 限流 fail-open");

  server.listen(port, host, () => {
    console.log(`✅ 服务就绪，监听 ${host}:${port}`);
  });
}

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  await closeRedis();
  await closeDb();
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 3000).unref();
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => {
    void shutdown();
  });
}

bootstrap().catch((error) => {
  console.error(`启动失败：${error?.message ?? error}`);
  process.exit(1);
});
