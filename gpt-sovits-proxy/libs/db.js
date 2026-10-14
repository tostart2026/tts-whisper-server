import { MongoClient } from "mongodb";
import { getAuthDbName, getDigitalmanDbName, getMongoUri } from "./config.js";

export const USERS_COLLECTION = "User_Info";
export const DIGITAL_HUMAN_COLLECTION = "AI_Digital_Human_Info";
export const CHARACTER_VOICE_COLLECTION = "AI_Character_Voice_Info";

let client = null;
let db = null;
let connecting = null;

export async function connectDb() {
  if (db) return db;
  if (!connecting) {
    const current = client ?? new MongoClient(getMongoUri(), { serverSelectionTimeoutMS: 10000 });
    client = current;
    connecting = current
      .connect()
      .then(() => {
        db = current.db(getAuthDbName());
        return db;
      })
      .catch(async (error) => {
        if (client === current) client = null;
        db = null;
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
  return db !== null;
}

export function getDigitalmanDb() {
  if (!client || !db) throw new Error("MongoDB 尚未连接");
  return client.db(getDigitalmanDbName());
}

export async function closeDb() {
  if (client) {
    await client.close().catch(() => undefined);
    client = null;
    db = null;
  }
}
