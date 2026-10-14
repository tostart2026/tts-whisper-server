import { createClient } from "redis";
import { getRedisUrl } from "./config.js";

function createAppClient() {
  return createClient({ url: getRedisUrl(), socket: { reconnectStrategy: false } });
}

let client = null;
let ready = false;

export async function connectRedis() {
  if (client && ready) return true;
  try {
    const next = createAppClient();
    next.on("error", (error) => {
      console.warn(`[redis] client error: ${error?.message ?? error}`);
    });
    await next.connect();
    client = next;
    ready = true;
    return true;
  } catch (error) {
    console.warn(`[redis] 连接失败，token 限流将 fail-open：${error?.message ?? error}`);
    client = null;
    ready = false;
    return false;
  }
}

export function isRedisReady() {
  return ready && client !== null;
}

export function getRedis() {
  return ready && client ? client : null;
}

export async function closeRedis() {
  if (!client) return;
  const current = client;
  client = null;
  ready = false;
  await current.close().catch(() => undefined);
}
