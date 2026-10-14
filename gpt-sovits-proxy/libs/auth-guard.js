import { getRedis } from "./redis.js";

export const AUTH_MAX_FAILURES = 5;
export const AUTH_LOCK_SECONDS = 10 * 60;

const KEY_PREFIX = "digitalman:auth";

function truthy(value) {
  const normalized = (value || "").trim().toLowerCase();
  return normalized === "true" || normalized === "1" || normalized === "yes" || normalized === "on";
}

export function trustProxy() {
  return truthy(process.env.TRUST_PROXY);
}

export function clientIp(req) {
  if (trustProxy()) {
    const header = req.headers["x-forwarded-for"];
    const raw = Array.isArray(header) ? header[0] : header;
    if (typeof raw === "string" && raw.trim()) {
      return raw.split(",")[0].trim();
    }
  }
  return req.socket.remoteAddress || "unknown";
}

function failKey(ip) {
  return `${KEY_PREFIX}:fail:${ip}`;
}

function lockKey(ip) {
  return `${KEY_PREFIX}:lock:${ip}`;
}

function warn(error) {
  console.warn(`[auth-guard] redis 操作失败（fail-open）：${error?.message ?? error}`);
}

export async function getLockSeconds(ip) {
  const redis = getRedis();
  if (!redis) return 0;
  try {
    const ttl = await redis.pTTL(lockKey(ip));
    return ttl > 0 ? Math.ceil(ttl / 1000) : 0;
  } catch (error) {
    warn(error);
    return 0;
  }
}

export async function registerAuthFailure(ip) {
  const redis = getRedis();
  if (!redis) return false;
  try {
    const key = failKey(ip);
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, AUTH_LOCK_SECONDS);
    if (count >= AUTH_MAX_FAILURES) {
      await redis.set(lockKey(ip), String(count), { EX: AUTH_LOCK_SECONDS });
      await redis.del(key);
      return true;
    }
    return false;
  } catch (error) {
    warn(error);
    return false;
  }
}

export async function clearAuthFailures(ip) {
  const redis = getRedis();
  if (!redis) return;
  try {
    await redis.del(failKey(ip));
  } catch (error) {
    warn(error);
  }
}
