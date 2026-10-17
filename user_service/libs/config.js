export function envStr(name) {
  return (process.env[name] || "").trim();
}

export function envNum(name, fallback) {
  const value = process.env[name];
  if (value === undefined || value.trim() === "") return fallback;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function getHost() {
  return envStr("USER_SERVICE_HOST") || "127.0.0.1";
}

export function getPort() {
  return envNum("USER_SERVICE_PORT", 8080);
}

export function getMongoUri() {
  return (
    envStr("MONGODB_URI") ||
    "mongodb://192.168.168.33:27017,192.168.168.33:27018,192.168.168.33:27019/?replicaSet=rs0"
  );
}

export function getUserDbName() {
  return envStr("USER_DB") || "base_db";
}

export function getVoiceDbName() {
  return envStr("DIGITALMAN_DB") || "digitalman_db";
}

export function getInternalToken() {
  return envStr("USER_SERVICE_TOKEN");
}
