import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

const bindings = env as unknown as { DB: D1Database; TEST_MIGRATIONS: { name: string; queries: string[] }[] };
await applyD1Migrations(bindings.DB, bindings.TEST_MIGRATIONS);
