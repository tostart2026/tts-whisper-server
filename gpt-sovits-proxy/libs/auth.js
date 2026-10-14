import { connectDb, getDigitalmanDb, USERS_COLLECTION } from "./db.js";

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

export async function verifyToken(token) {
  const value = token.trim();
  if (!value) return null;

  await connectDb();
  const doc = await getDigitalmanDb()
    .collection(USERS_COLLECTION)
    .findOne({ Token: value });
  if (!doc || doc.enabled === false) return null;
  return toAuthUser(doc, value);
}
