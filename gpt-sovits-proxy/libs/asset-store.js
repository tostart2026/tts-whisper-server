import { CHARACTER_VOICE_COLLECTION, USERS_COLLECTION, connectDb, getDigitalmanDb } from "./db.js";

export const DEFAULT_DIGITAL_HUMAN = "dh0001";
export const DEFAULT_CHARACTER = "e2";
export const DEFAULT_ASSIST_CHARACTER = "zm_yunxi";

function firstNonEmpty(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) return value.trim();
    if (typeof value === "number" && Number.isFinite(value)) return String(value);
  }
  return "";
}

async function findUserDoc(token, appCode) {
  await connectDb();
  const users = getDigitalmanDb().collection(USERS_COLLECTION);
  const byToken = await users.findOne({ Token: token });
  if (byToken) return byToken;
  if (appCode) return users.findOne({ AppCode: appCode });
  return null;
}

function allowedCharacters(user) {
  const digitalHuman = firstNonEmpty(user?.DigitalHumanCharacter) || DEFAULT_DIGITAL_HUMAN;
  const master = firstNonEmpty(user?.MasterCharacter) || DEFAULT_CHARACTER;
  const assist = firstNonEmpty(user?.AssistCharacter) || DEFAULT_ASSIST_CHARACTER;
  return { digitalHuman, master, assist };
}

export async function getUserVoiceDocs(token, appCode) {
  const user = await findUserDoc(token, appCode);
  const chars = allowedCharacters(user);
  const roles = [
    { role: "master", character: chars.master },
    { role: "assist", character: chars.assist },
  ];
  const seen = new Set();
  const voices = [];
  const voicesCollection = getDigitalmanDb().collection(CHARACTER_VOICE_COLLECTION);
  for (const entry of roles) {
    if (!entry.character || seen.has(entry.character)) continue;
    seen.add(entry.character);
    const doc = await voicesCollection.findOne({ Character: entry.character });
    if (doc) voices.push({ role: entry.role, doc });
  }
  return { characters: chars, voices };
}
