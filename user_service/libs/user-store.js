import {
  CHARACTER_VOICE_COLLECTION,
  USERS_COLLECTION,
  connectDb,
  getUserDb,
  getVoiceDb,
} from "./db.js";

export const DEFAULT_DIGITAL_HUMAN = "dh0001";
export const DEFAULT_CHARACTER = "e2";
export const DEFAULT_ASSIST_CHARACTER = "zm_yunxi";

function toAuthUser(doc, token) {
  const role = (doc.role || "").toLowerCase();
  const isAdmin = role === "admin";
  const appCode = (doc.AppCode || "").trim();
  if (!isAdmin && !appCode) return null;
  return {
    level: role,
    appCode,
    isAdmin,
    permissions: {},
    name: doc.name || "",
    token,
  };
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

function allowedCharacters(user) {
  const digitalHuman = firstNonEmpty(user?.DigitalHumanCharacter) || DEFAULT_DIGITAL_HUMAN;
  const master = firstNonEmpty(user?.MasterCharacter) || DEFAULT_CHARACTER;
  const assist = firstNonEmpty(user?.AssistCharacter) || DEFAULT_ASSIST_CHARACTER;
  return { digitalHuman, master, assist };
}

async function findUserDoc(token, appCode) {
  await connectDb();
  const users = getUserDb().collection(USERS_COLLECTION);
  const byToken = await users.findOne({ Token: token });
  if (byToken) return byToken;
  if (appCode) return users.findOne({ AppCode: appCode });
  return null;
}

export async function verifyToken(token) {
  const value = token.trim();
  if (!value) return null;

  await connectDb();
  const doc = await getUserDb().collection(USERS_COLLECTION).findOne({ Token: value });
  if (!doc || doc.enabled === false) return null;
  return toAuthUser(doc, value);
}

export async function getUserVoiceDocs(token, appCode) {
  const user = await findUserDoc(token, appCode);
  if (!user) return null;

  const chars = allowedCharacters(user);
  const roles = [
    { role: "master", character: chars.master },
    { role: "assist", character: chars.assist },
  ];
  const seen = new Set();
  const voices = [];
  const voicesCollection = getVoiceDb().collection(CHARACTER_VOICE_COLLECTION);
  for (const entry of roles) {
    if (!entry.character || seen.has(entry.character)) continue;
    seen.add(entry.character);
    const doc = await voicesCollection.findOne({ Character: entry.character });
    if (doc) voices.push({ role: entry.role, doc });
  }
  return { characters: chars, voices };
}
