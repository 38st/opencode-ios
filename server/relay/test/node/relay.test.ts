import { generateKeyPairSync } from "node:crypto";
import { afterAll, beforeAll } from "vitest";
import { CONTRACT } from "../../../contracts/src/constants.ts";
import { formatLog } from "../../src/log.ts";
import { startNodeRelay, type NodeRelay } from "../../src/node-server.ts";
import { BUNDLE_ID, KEY_ID, TEAM_ID, TEST_LIMITS } from "../support/fixture.ts";
import { startMockApns, type MockApns } from "../support/mock-apns.ts";
import { relaySuite } from "../support/suite.ts";

let relay: NodeRelay, mock: MockApns;
const logs: string[] = [];

beforeAll(async () => {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  mock = await startMockApns({ teamID: TEAM_ID, keyID: KEY_ID, publicKeyPEM: publicKey.export({ type: "spki", format: "pem" }).toString(), bundleIDs: [BUNDLE_ID] });
  relay = await startNodeRelay({
    env: {
      APNS_TEAM_ID: TEAM_ID,
      APNS_KEY_ID: KEY_ID,
      APNS_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      APNS_SANDBOX_URL: mock.h2URL,
      APNS_PRODUCTION_URL: mock.h2URL,
      ALLOWED_BUNDLE_IDS: BUNDLE_ID,
      RELAY_TEST_MODE: "1",
      RELAY_TEST_LIMITS: JSON.stringify(TEST_LIMITS),
    },
    database: ":memory:",
    trustProxy: "fly",
    log: (event, fields) => void logs.push(formatLog(event, fields)),
  });
});

afterAll(async () => {
  await relay?.close();
  await mock?.close();
});

relaySuite(() => ({
  relay(path, init = {}) {
    const { ip, ...rest } = init;
    const headers = new Headers(rest.headers);
    if (ip) headers.set("fly-client-ip", ip);
    return fetch(relay.url + path, { ...rest, headers });
  },
  mockURL: mock.url,
  bundleID: BUNDLE_ID,
  protocol: "h2",
  limits: { ...CONTRACT.limits, ...TEST_LIMITS },
  logs: () => logs,
}));
