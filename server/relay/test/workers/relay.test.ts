import { exports } from "cloudflare:workers";
import { inject, vi } from "vitest";
import { CONTRACT } from "../../../contracts/src/constants.ts";
import { BUNDLE_ID, TEST_LIMITS } from "../support/fixture.ts";
import { relaySuite } from "../support/suite.ts";

// The Worker runs in this isolate, so its console output can be captured here.
const logs: string[] = [];
vi.spyOn(console, "log").mockImplementation((...items: unknown[]) => void logs.push(items.join(" ")));
const worker = (exports as unknown as { default: Fetcher }).default;

relaySuite(() => ({
  relay(path, init = {}) {
    const { ip, ...rest } = init;
    const headers = new Headers(rest.headers);
    if (ip) headers.set("cf-connecting-ip", ip);
    return worker.fetch(new Request(`https://relay.test${path}`, { ...rest, headers }));
  },
  mockURL: inject("mockURL"),
  bundleID: BUNDLE_ID,
  protocol: "h1",
  limits: { ...CONTRACT.limits, ...TEST_LIMITS },
  logs: () => logs,
}));
