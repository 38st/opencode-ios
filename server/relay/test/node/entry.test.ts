import { spawn } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "vitest";
import { BUNDLE_ID, KEY_ID, TEAM_ID } from "../support/fixture.ts";

// The documented start command, `node src/node.ts`, with a temporary database.
test("node src/node.ts serves the relay", async () => {
  const directory = await mkdtemp(path.join(tmpdir(), "relay-entry-"));
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  const child = spawn(process.execPath, [fileURLToPath(new URL("../../src/node.ts", import.meta.url))], {
    env: {
      PATH: process.env.PATH,
      PORT: "0",
      HOST: "127.0.0.1",
      RELAY_DATABASE: path.join(directory, "relay.sqlite"),
      APNS_TEAM_ID: TEAM_ID,
      APNS_KEY_ID: KEY_ID,
      APNS_PRIVATE_KEY: privateKey.export({ type: "pkcs8", format: "pem" }).toString(),
      ALLOWED_BUNDLE_IDS: BUNDLE_ID,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  try {
    const url = await new Promise<string>((resolve, reject) => {
      let output = "";
      child.stdout.on("data", (chunk: Buffer) => {
        output += chunk;
        const line = output.split("\n").find((item) => item.includes('"listening"'));
        if (line) resolve((JSON.parse(line) as { url: string }).url);
      });
      child.stderr.on("data", (chunk: Buffer) => (output += chunk));
      child.on("exit", (code) => reject(new Error(`exited ${code}: ${output}`)));
    });
    const health = await fetch(`${url}/v1/health`);
    expect(health.status).toBe(200);
    expect(await health.json()).toMatchObject({ status: "ok" });
  } finally {
    child.kill("SIGTERM");
    await new Promise((resolve) => child.once("exit", resolve));
    await rm(directory, { recursive: true, force: true });
  }
});
