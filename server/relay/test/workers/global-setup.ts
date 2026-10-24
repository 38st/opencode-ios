import { generateKeyPairSync } from "node:crypto";
import type { TestProject } from "vitest/node";
import { BUNDLE_ID, KEY_ID, TEAM_ID } from "../support/fixture.ts";
import { startMockApns } from "../support/mock-apns.ts";

declare module "vitest" {
  export interface ProvidedContext {
    mockURL: string;
    apnsPrivateKey: string;
  }
}

/** Runs in Node: a fresh ES256 test key and the mock APNs server the Worker sends to. */
export default async function setup(project: TestProject) {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const mock = await startMockApns({
    teamID: TEAM_ID,
    keyID: KEY_ID,
    publicKeyPEM: publicKey.export({ type: "spki", format: "pem" }).toString(),
    bundleIDs: [BUNDLE_ID],
  });
  project.provide("mockURL", mock.url);
  project.provide("apnsPrivateKey", privateKey.export({ type: "pkcs8", format: "pem" }).toString());
  return () => mock.close();
}
