import { readFile } from "node:fs/promises";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { base64url, PACKAGE_NAME } from "../contracts/src/index.ts";
import { definition, PLUGIN_VERSION } from "../src/rpc.ts";
import type { PushService } from "../src/service.ts";
import plugin from "../server.ts";
import { FakeHost, fakeDevice, register, RpcError, startFakeRelay, startService, type FakeRelay } from "./fakes.ts";

let relay: FakeRelay;
const services: PushService[] = [];
beforeEach(async () => {
  relay = await startFakeRelay();
});
afterEach(async () => {
  for (const service of services.splice(0)) await service.stop();
  await relay.close();
});

async function host() {
  const harness = await startService(new FakeHost());
  services.push(harness.service);
  return harness.host;
}

describe("the mobilepush RPC", () => {
  test("defines the seven methods of ARCHITECTURE §4.2 under one RPC ID", () => {
    expect(definition.id).toBe("mobilepush");
    expect(Object.keys(definition.methods).sort()).toEqual(["listDevices", "registerActivity", "registerDevice", "setPresence", "status", "test", "unregisterDevice"]);
  });

  test("registerDevice returns the pinned key and the plugin version, and re-registering replaces the entry", async () => {
    const server = await host();
    const device = await fakeDevice();
    const first = await register(server, relay, device);
    expect(first.pluginVersion).toBe(PLUGIN_VERSION);
    expect(base64url.decode(first.serverPublicKey)?.length).toBe(32);
    expect(await register(server, relay, device, { label: "Renamed" })).toEqual(first);
    const { devices } = await server.call("listDevices");
    expect(devices).toEqual([{ keyID: device.keyID, transport: "relay", label: "Renamed", appServerRef: "srv_home_mac", relayURL: relay.url, prefs: { permission: true, question: true, finished: true, failed: true }, registeredAt: expect.any(Number) }]);
  });

  test("registerDevice rejects bad input with the offending field", async () => {
    const server = await host();
    const device = await fakeDevice();
    const cases: [Record<string, unknown>, string][] = [
      [{ keyID: "short" }, "keyID"],
      [{ sendToken: "x" }, "sendToken"],
      [{ devicePublicKey: "AAAA" }, "devicePublicKey"],
      [{ relayURL: "http://relay.example.com" }, "relayURL"],
      [{ relayURL: "https://user:pw@relay.example.com" }, "relayURL"],
      [{ relayURL: "ftp://relay.example.com" }, "relayURL"],
      [{ appServerRef: "" }, "appServerRef"],
      [{ appServerRef: "x".repeat(129) }, "appServerRef"],
      [{ label: 7 }, "label"],
      [{ prefs: { finished: "no" } }, "prefs.finished"],
    ];
    for (const [change, field] of cases) {
      await expect(register(server, relay, device, change)).rejects.toMatchObject({ type: "invalid", data: { field } });
    }
    await expect(server.call("registerDevice", [])).rejects.toBeInstanceOf(RpcError);
  });

  test("allows https relays anywhere and plain http only on this machine", async () => {
    const server = await host();
    const device = await fakeDevice();
    await register(server, relay, device, { relayURL: "https://relay.example.com/prefix/" });
    expect((await server.call("listDevices")).devices[0].relayURL).toBe("https://relay.example.com/prefix");
    await register(server, relay, device, { relayURL: "http://localhost:8787" });
  });

  test("unregisterDevice removes the device and its presence and activities", async () => {
    const server = await host();
    const device = await fakeDevice();
    await register(server, relay, device);
    await server.call("setPresence", { keyID: device.keyID, foreground: true });
    await server.call("registerActivity", { keyID: device.keyID, activityRef: "act_9", sessionID: "ses_1" });
    expect(await server.call("unregisterDevice", { keyID: device.keyID })).toEqual({ removed: true });
    expect(await server.call("unregisterDevice", { keyID: device.keyID })).toEqual({ removed: false });
    expect([...server.storage.values.keys()].filter((key) => key !== "key/server")).toEqual([]);
  });

  test("methods for one device need it to be registered", async () => {
    const server = await host();
    for (const method of ["test", "setPresence", "registerActivity"]) {
      await expect(server.call(method, { keyID: "kid_unknown_device_00", foreground: true, activityRef: "a", sessionID: "s" })).rejects.toMatchObject({ type: "not_found", data: { field: "keyID", retryable: false } });
    }
    const device = await fakeDevice();
    await register(server, relay, device);
    await expect(server.call("setPresence", { keyID: device.keyID })).rejects.toMatchObject({ type: "invalid", data: { field: "foreground" } });
    expect(await server.call("setPresence", { keyID: device.keyID, foreground: true })).toEqual({ validSeconds: 45, heartbeatSeconds: 30 });
  });

  test("status needs no input", async () => {
    const server = await host();
    expect(await server.call("status")).toMatchObject({ package: PACKAGE_NAME, pluginVersion: PLUGIN_VERSION, devices: 0 });
  });
});

describe("the package", () => {
  test("exports a default { id, setup } plugin from server.ts, as opencode's loader expects", () => {
    expect(plugin.id).toBe("mobilepush");
    expect(typeof plugin.setup).toBe("function");
  });

  test("its name is the contract's package name, and its version is the plugin version", async () => {
    const manifest = JSON.parse(await readFile(new URL("../package.json", import.meta.url), "utf8"));
    expect(manifest.name).toBe(PACKAGE_NAME);
    expect(manifest.version).toBe(PLUGIN_VERSION);
    expect(manifest.license).toBe("MIT");
    expect(manifest.exports).toEqual({ ".": "./server.ts", "./server": "./server.ts" });
  });

  test("setup registers the RPC and the cleanup stops it", async () => {
    const server = new FakeHost();
    const cleanup = await plugin.setup(server);
    expect(server.handlers?.status).toBeTypeOf("function");
    await cleanup();
    expect(server.handlers).toBeUndefined();
  });
});
