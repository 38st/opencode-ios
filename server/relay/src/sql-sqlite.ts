import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import type { DatabaseSync } from "node:sqlite";
import { bucketName, type Limiter, type LimitRule } from "./limiter.ts";
import type { Sql } from "./store.ts";

/** node:sqlite runs each statement synchronously, so a batch is a plain transaction. */
export const sqlite = (db: DatabaseSync): Sql => ({
  async run(query, params = []) {
    return Number(db.prepare(query).run(...params).changes);
  },
  async first(query, params = []) {
    return (db.prepare(query).get(...params) as never) ?? undefined;
  },
  async batch(statements) {
    db.exec("BEGIN IMMEDIATE");
    try {
      for (const [query, params] of statements) db.prepare(query).run(...params);
      db.exec("COMMIT");
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  },
});

/** Applies migrations/*.sql in name order, recording them in the same table Wrangler uses for D1. */
export function migrate(db: DatabaseSync, directory: string): string[] {
  db.exec("CREATE TABLE IF NOT EXISTS d1_migrations (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE, applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)");
  const applied = new Set((db.prepare("SELECT name FROM d1_migrations").all() as { name: string }[]).map((row) => row.name));
  const pending = readdirSync(directory).filter((name) => name.endsWith(".sql") && !applied.has(name)).sort();
  for (const name of pending) {
    db.exec("BEGIN IMMEDIATE");
    try {
      db.exec(readFileSync(path.join(directory, name), "utf8"));
      db.prepare("INSERT INTO d1_migrations (name) VALUES (?)").run(name);
      db.exec("COMMIT");
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  }
  return pending;
}

/** The Node limiter. Each hit is one synchronous transaction, so concurrent requests cannot overshoot. */
export class SqliteLimiter implements Limiter {
  readonly #db: DatabaseSync;
  #hits = 0;
  constructor(db: DatabaseSync) {
    this.#db = db;
    db.exec("CREATE TABLE IF NOT EXISTS rate_limits (key TEXT NOT NULL, bucket TEXT NOT NULL, count INTEGER NOT NULL, expires_at INTEGER NOT NULL, PRIMARY KEY (key, bucket))");
  }

  async hit(key: string, rules: readonly LimitRule[], now: number): Promise<boolean> {
    const db = this.#db;
    db.exec("BEGIN IMMEDIATE");
    try {
      if (++this.#hits % 500 === 0) db.prepare("DELETE FROM rate_limits WHERE expires_at <= ?").run(now);
      const read = db.prepare("SELECT count FROM rate_limits WHERE key = ? AND bucket = ?");
      const counts = rules.map((rule) => (read.get(key, bucketName(rule, now)) as { count: number } | undefined)?.count ?? 0);
      const allowed = rules.every((rule, index) => counts[index]! < rule.max);
      if (allowed) {
        const write = db.prepare(
          "INSERT INTO rate_limits (key, bucket, count, expires_at) VALUES (?, ?, 1, ?) ON CONFLICT (key, bucket) DO UPDATE SET count = count + 1",
        );
        for (const rule of rules) write.run(key, bucketName(rule, now), (Math.floor(now / rule.windowSeconds) + 1) * rule.windowSeconds);
      }
      db.exec("COMMIT");
      return allowed;
    } catch (error) {
      db.exec("ROLLBACK");
      throw error;
    }
  }
}
