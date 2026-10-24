import type { Sql } from "./store.ts";

export const d1 = (db: D1Database): Sql => ({
  async run(query, params = []) {
    return (await db.prepare(query).bind(...params).run()).meta.changes ?? 0;
  },
  async first(query, params = []) {
    return (await db.prepare(query).bind(...params).first()) ?? undefined;
  },
  async batch(statements) {
    await db.batch(statements.map(([query, params]) => db.prepare(query).bind(...params)));
  },
});
