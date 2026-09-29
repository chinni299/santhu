// server/src/redisClient.js
//
// Lightweight Redis client wrapper for presence tracking.
// - Uses ioredis (free, open-source npm package).
// - If REDIS_URL is not set, the app runs fine without Redis: presence
//   simply falls back to the existing in-memory + Postgres behavior.
//
// Free Redis hosting options: Upstash (free tier), Render's own Redis addon,
// or a local `redis-server` during development.

let Redis = null;
try {
  Redis = require("ioredis");
} catch (e) {
  // ioredis not installed
}

let redis = null;
let isReady = false;

if (process.env.REDIS_URL && Redis) {
  try {
    redis = new Redis(process.env.REDIS_URL, {
      maxRetriesPerRequest: 2,
      retryStrategy: (times) => Math.min(times * 500, 5000),
      lazyConnect: false,
    });

    redis.on("connect", () => {
      isReady = true;
      console.log("Redis presence store connected ✅");
    });

    redis.on("error", (err) => {
      isReady = false;
      console.error("Redis connection error (presence tracking degraded):", err.message);
    });

    redis.on("close", () => {
      isReady = false;
    });
  } catch (err) {
    console.error("Failed to initialize Redis client:", err.message);
    redis = null;
  }
} else {
  console.warn(
    "⚠️ REDIS_URL not set. Presence tracking will use in-memory + Postgres only (no restart-safe presence)."
  );
}

function isRedisEnabled() {
  return redis !== null && isReady;
}

module.exports = { redis, isRedisEnabled };