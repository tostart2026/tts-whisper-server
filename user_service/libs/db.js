import { MongoClient } from "mongodb";
import { getMongoUri, getUserDbName, getVoiceDbName } from "./config.js";

export const USERS_COLLECTION = "User_Info";
export const CHARACTER_VOICE_COLLECTION = "AI_Character_Voice_Info";

let client = null;
let connecting = null;

export async function connectDb() {
  if (client) return client;
  if (!connecting) {
    const current = new MongoClient(getMongoUri(), { serverSelectionTimeoutMS: 10000 });
    connecting = current
      .connect()
      .then(() => {
        client = current;
        return client;
      })
      .catch(async (error) => {
        await current.close().catch(() => undefined);
        throw error;
      })
      .finally(() => {
        connecting = null;
      });
  }
  return connecting;
}

export function isDbConnected() {
  return client !== null;
}

export function getUserDb() {
  if (!client) throw new Error("MongoDB 尚未连接");
  return client.db(getUserDbName());
}

export function getVoiceDb() {
  if (!client) throw new Error("MongoDB 尚未连接");
  return client.db(getVoiceDbName());
}

export async function closeDb() {
  if (client) {
    await client.close().catch(() => undefined);
    client = null;
  }
}
