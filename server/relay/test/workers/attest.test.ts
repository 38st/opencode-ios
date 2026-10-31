import { env } from "cloudflare:workers";
import { beforeAll } from "vitest";
import { createApp } from "../../src/app.ts";
import { readConfig, type RelayEnvironment } from "../../src/config.ts";
import { d1 } from "../../src/sql-d1.ts";
import { Store } from "../../src/store.ts";
import { attestFixture, type AttestFixture } from "../support/attest-fixture.ts";
import { attestSuite } from "../support/attest-suite.ts";
import { BUNDLE_ID, TEAM_ID } from "../support/fixture.ts";

// The routes and verification run in workerd against D1, with APP_ATTEST=required and the fixture's
// test root. The Worker's own bindings keep App Attest off (relay.test.ts covers that).
const bindings = env as unknown as RelayEnvironment & { DB: D1Database };
let fixture: AttestFixture, app: ReturnType<typeof createApp>;

beforeAll(async () => {
  fixture = await attestFixture(`${TEAM_ID}.${BUNDLE_ID}`);
  const config = readConfig({ ...bindings, APP_ATTEST: "required", APP_ATTEST_TEST_ROOTS: fixture.rootPEM });
  const counts = new Map<string, number>();
  const deps = {
    config,
    store: new Store(d1(bindings.DB)),
    limiter: {
      async hit(key: string, rules: readonly { max: number }[]) {
        const count = (counts.get(key) ?? 0) + 1;
        counts.set(key, count);
        return rules.every((rule) => count <= rule.max);
      },
    },
    sender: { send: async () => ({ status: 200 }) } as never,
    tokens: { token: async () => "token", reject: async () => {} },
    log: () => {},
    now: () => Math.floor(Date.now() / 1000),
  };
  app = createApp({ resolve: () => deps, clientIP: (c) => c.req.header("cf-connecting-ip") });
});

attestSuite(() => ({
  async relay(path, init = {}) {
    const { ip, ...rest } = init;
    const headers = new Headers(rest.headers);
    if (ip) headers.set("cf-connecting-ip", ip);
    return app.fetch(new Request(`https://relay.test${path}`, { ...rest, headers }));
  },
  fixture,
  bundleID: BUNDLE_ID,
}));
