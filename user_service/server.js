import http from "node:http";
import { timingSafeEqual } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  getHost,
  getInternalToken,
  getMongoUri,
  getPort,
  getUserDbName,
  getVoiceDbName,
} from "./libs/config.js";
import { closeDb, connectDb, isDbConnected } from "./libs/db.js";
import { getUserVoiceDocs, verifyToken } from "./libs/user-store.js";

const here = dirname(fileURLToPath(import.meta.url));
try {
  process.loadEnvFile(resolve(here, ".env"));
} catch {}

const MAX_BODY_BYTES = 1024 * 1024;

function log(level, message) {
  const line = `[user-service] ${message}`;
  if (level === "warn") console.warn(line);
  else console.log(line);
}

function sendJson(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload), "utf-8");
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": String(body.length),
  });
  res.end(body);
}

function sendError(res, status, message) {
  sendJson(res, status, { success: false, error: message });
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(new Error("请求体过大"));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      const raw = Buffer.concat(chunks).toString("utf-8").trim();
      if (!raw) {
        resolve({});
        return;
      }
      try {
        const payload = JSON.parse(raw);
        resolve(payload && typeof payload === "object" && !Array.isArray(payload) ? payload : {});
      } catch {
        reject(new Error("无效的 JSON 请求体"));
      }
    });
    req.on("error", reject);
  });
}

function tokensEqual(provided, expected) {
  const a = Buffer.from(String(provided ?? ""), "utf-8");
  const b = Buffer.from(String(expected ?? ""), "utf-8");
  return a.length === b.length && timingSafeEqual(a, b);
}

function authorized(req) {
  const expected = getInternalToken();
  if (!expected) return true;
  const header = req.headers["x-service-token"];
  const provided = Array.isArray(header) ? header[0] : header;
  return tokensEqual(provided, expected);
}

async function handleVerifyToken(req, res) {
  const body = await readJson(req);
  const token = String(body.token ?? "").trim();
  if (!token) {
    sendError(res, 400, "token is required");
    return;
  }
  const user = await verifyToken(token);
  sendJson(res, 200, { success: true, user });
}

async function handleUserVoices(req, res) {
  const body = await readJson(req);
  const token = String(body.token ?? "").trim();
  const appCode = String(body.appCode ?? "").trim();
  if (!token) {
    sendError(res, 400, "token is required");
    return;
  }
  const docs = await getUserVoiceDocs(token, appCode);
  if (!docs) {
    sendError(res, 404, "用户不存在");
    return;
  }
  sendJson(res, 200, { success: true, ...docs });
}

function handleHealth(res) {
  sendJson(res, 200, {
    status: "ok",
    service: "user-service",
    mongo: isDbConnected(),
    user_db: getUserDbName(),
    voice_db: getVoiceDbName(),
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host ?? "localhost"}`);
  const pathname = url.pathname.replace(/\/+$/, "") || "/";

  if (req.method === "GET" && pathname === "/health") {
    handleHealth(res);
    return;
  }

  if (pathname === "/internal/verify-token" || pathname === "/internal/user/voices") {
    if (req.method !== "POST") {
      sendError(res, 405, "Method Not Allowed");
      return;
    }
    if (!authorized(req)) {
      sendError(res, 401, "无效的服务凭证");
      return;
    }
    const handler = pathname === "/internal/verify-token" ? handleVerifyToken : handleUserVoices;
    handler(req, res).catch((error) => {
      log("warn", `${pathname} error=${error?.message ?? error}`);
      if (!res.headersSent) sendError(res, 500, `数据查询失败：${error?.message ?? error}`);
      else res.end();
    });
    return;
  }

  sendError(res, 404, "Not Found");
});

async function bootstrap() {
  const host = getHost();
  const port = getPort();

  console.log("Starting user service (Node.js)");
  console.log(`  Listen:     ${host}:${port}`);
  console.log(`  MongoDB:    ${getMongoUriSafe()}`);
  console.log(`  User DB:    ${getUserDbName()}`);
  console.log(`  Voice DB:   ${getVoiceDbName()}`);
  console.log(`  Service auth: ${getInternalToken() ? "enabled" : "disabled"}`);

  try {
    await connectDb();
    console.log("MongoDB 已连接");
  } catch (error) {
    console.warn(`MongoDB 连接失败（将在请求时重试）：${error?.message ?? error}`);
  }

  server.listen(port, host, () => {
    console.log(`✅ 用户服务就绪，监听 ${host}:${port}`);
  });
}

function getMongoUriSafe() {
  return getMongoUri().replace(/\/\/[^@/]+@/, "//***@");
}

let shuttingDown = false;
async function shutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
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
