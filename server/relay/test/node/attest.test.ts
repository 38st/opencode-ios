import { generateKeyPairSync } from "node:crypto";
import { afterAll, beforeAll } from "vitest";
import { startNodeRelay, type NodeRelay } from "../../src/node-server.ts";
import { attestFixture, type AttestFixture } from "../support/attest-fixture.ts";
import { attestSuite } from "../support/attest-suite.ts";
import { BUNDLE_ID, KEY_ID, TEAM_ID, TEST_LIMITS } from "../support/fixture.ts";

let relay: NodeRelay, fixture: AttestFixture;

beforeAll(async () => {
  fixture = await attestFixture(`${TEAM_ID}.${BUNDLE_ID}`);
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  relay = await startNodeRelay({
    env: {
      APNS_TEAM_ID: TEAM_ID,
      APNS_KEY_ID: KEY_ID,
      APNS_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      ALLOWED_BUNDLE_IDS: BUNDLE_ID,
      APP_ATTEST: "required",
      APP_ATTEST_TEST_ROOTS: fixture.rootPEM,
      RELAY_TEST_MODE: "1",
      RELAY_TEST_LIMITS: JSON.stringify(TEST_LIMITS),
    },
    database: ":memory:",
    trustProxy: "fly",
    log: () => {},
  });
});

afterAll(async () => {
  await relay?.close();
});

attestSuite(() => ({
  relay(path, init = {}) {
    const { ip, ...rest } = init;
    const headers = new Headers(rest.headers);
    if (ip) headers.set("fly-client-ip", ip);
    return fetch(relay.url + path, { ...rest, headers });
  },
  fixture,
  bundleID: BUNDLE_ID,
}));
