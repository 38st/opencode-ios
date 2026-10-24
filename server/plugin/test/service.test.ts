import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { base64url, classify, CONTRACT, formDigest, kindPolicy, permissionDigest } from "../contracts/src/index.ts";
import { collapseForRequest, threadFor } from "../src/hashing.ts";
import type { PushService } from "../src/service.ts";
import { createSharedState } from "../src/shared.ts";
import { FakeHost, fakeDevice, MemoryStorage, open, register, sleep, startFakeRelay, startService, until, type FakeDevice, type FakeRelay } from "./fakes.ts";

let relay: FakeRelay;
const services: PushService[] = [];
beforeEach(async () => {
  relay = await startFakeRelay();
});
afterEach(async () => {
  for (const service of services.splice(0)) await service.stop();
  await relay.close();
});

async function setup(options: Parameters<typeof startService>[1] = {}, host = new FakeHost()) {
  const harness = await startService(host, options);
  services.push(harness.service);
  const device = await fakeDevice();
  const { serverPublicKey } = await register(host, relay, device);
  return { ...harness, device, serverPublicKey };
}

let serial = 0;
function permission(host: FakeHost, sessionID = "ses_root", resources = ["git push --force origin main"]) {
  const id = `per_${++serial}`;
  host.permissions.set(id, sessionID);
  const data = { id, sessionID, action: "shell", resources, save: ["git push *"], source: { type: "tool", messageID: "msg_1", id: "call_1" } };
  host.emit({ id: `evt_asked_${id}`, type: "permission.asked", created: Date.now(), data });
  return data;
}
function reply(host: FakeHost, data: { id: string; sessionID: string }, decision = "once") {
  host.permissions.delete(data.id);
  host.emit({ id: `evt_replied_${data.id}`, type: "permission.replied", created: Date.now(), data: { sessionID: data.sessionID, requestID: data.id, reply: decision } });
}
function question(host: FakeHost, sessionID = "ses_root") {
  const form = {
    id: `frm_${++serial}`,
    sessionID,
    title: "Questions",
    metadata: { kind: "question" },
    fields: [{ key: "q0", type: "string", title: "Color", description: "Which color?", custom: true, options: [{ value: "Blue", label: "Blue" }, { value: "Green", label: "Green" }] }],
  };
  host.emit({ id: `evt_form_${form.id}`, type: "form.created", created: Date.now(), data: { form } });
  return form;
}
const opened = (push: { body: { envelope: never } }, device: FakeDevice, serverPublicKey: string) => open(push.body.envelope, device, serverPublicKey);

describe("permission requests", () => {
  test("push after the grace period, with every payload field", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_root", { title: "Release prep" });
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    const [push] = relay.pushes();
    expect(push!.token).toBe(device.sendToken);
    const now = Math.floor(Date.now() / 1000);
    expect(push!.body).toMatchObject({
      kind: "permission",
      priority: 10,
      collapse: await collapseForRequest(device.keyID, request.id),
      thread: await threadFor(device.keyID, "ses_root"),
    });
    expect(push!.body.expiresAt).toBeGreaterThanOrEqual(now + kindPolicy("permission").ttlSeconds - 2);
    const { payload } = await opened(push!, device, serverPublicKey);
    expect(payload).toEqual({
      v: 1,
      kind: "permission",
      server: "srv_home_mac",
      exp: push!.body.expiresAt,
      pending: 1,
      sessionID: "ses_root",
      rootSessionID: "ses_root",
      title: "Release prep",
      project: "project",
      requestID: request.id,
      action: "shell",
      summary: "git push --force origin main",
      risk: classify("shell", request.resources).tier,
      digest: await permissionDigest(request),
    });
    expect(payload.risk).toBe("high");
  });

  test("an answer inside the grace period cancels the push", async () => {
    const { host } = await setup({ graceMilliseconds: 150 });
    const request = permission(host);
    await sleep(30);
    reply(host, request);
    await sleep(300);
    expect(relay.pushes()).toEqual([]);
  });

  test("a request no longer pending when the grace period ends is not pushed, and stops counting as pending", async () => {
    const { host, device, serverPublicKey } = await setup();
    const request = permission(host);
    host.permissions.delete(request.id); // answered by an automatic rule, without a reply event reaching this instance
    await sleep(200);
    expect(relay.pushes()).toEqual([]);
    permission(host);
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload.pending).toBe(1);
  });

  test("a request repeated under another event ID is still pushed once", async () => {
    const { host } = await setup();
    const request = permission(host);
    host.emit({ id: `evt_again_${request.id}`, type: "permission.asked", data: request });
    await until(() => relay.pushes().length === 1);
    await sleep(200);
    expect(relay.pushes().length).toBe(1);
  });

  for (const type of ["session.execution.interrupted", "session.deleted"]) {
    test(`a pushed request dropped by ${type} is replaced and stops counting as pending`, async () => {
      const { host, device, serverPublicKey } = await setup();
      const stopped = permission(host);
      await until(() => relay.pushes().length === 1);
      host.permissions.delete(stopped.id); // core/src/permission.ts removes it without permission.replied
      host.emit({ id: `evt_${type}_${stopped.id}`, type, data: { sessionID: "ses_root", reason: "user" } });
      await until(() => relay.pushes().length === 2);
      const replacement = relay.pushes()[1]!;
      expect(replacement.body).toMatchObject({ kind: "resolved", collapse: relay.pushes()[0]!.body.collapse });
      expect((await opened(replacement, device, serverPublicKey)).payload).toMatchObject({ requestID: stopped.id, reply: "cancelled", pending: 0 });
      permission(host, "ses_other");
      await until(() => relay.pushes().length === 3);
      expect((await opened(relay.pushes()[2]!, device, serverPublicKey)).payload.pending).toBe(1);
    });
  }

  test("an interruption keeps requests the server still holds, and looks again shortly after", async () => {
    const { host, device, serverPublicKey } = await setup({ recheckMilliseconds: 100 });
    const kept = permission(host);
    await until(() => relay.pushes().length === 1);
    host.emit({ id: "evt_interrupt_early", type: "session.execution.interrupted", data: { sessionID: "ses_root", reason: "user" } });
    await sleep(50);
    expect(relay.pushes().length).toBe(1);
    host.permissions.delete(kept.id); // the run removes it just after the event
    await until(() => relay.pushes().length === 2);
    expect((await opened(relay.pushes()[1]!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: kept.id, reply: "cancelled" });
  });

  test("when the family cannot be read (after one retry), requests and failures go out under their own session, and finished is skipped", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_lost_child", { parentID: "ses_lost_root" });
    host.unavailable.add("ses_lost_root");
    host.emit({ id: "evt_lost_done", type: "session.execution.succeeded", data: { sessionID: "ses_lost_child" } });
    const request = permission(host, "ses_lost_child");
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "permission", requestID: request.id, sessionID: "ses_lost_child", rootSessionID: "ses_lost_child" });
    host.emit({ id: "evt_lost_fail", type: "session.execution.failed", data: { sessionID: "ses_lost_child", error: { type: "x", message: "boom" } } });
    await until(() => relay.pushes().length === 2);
    expect((await opened(relay.pushes()[1]!, device, serverPublicKey)).payload).toMatchObject({ kind: "failed", rootSessionID: "ses_lost_child" });
    await sleep(150);
    expect(relay.pushes().every((push) => push.body.kind !== "finished")).toBe(true);
    expect(host.lookups.get("ses_lost_root")).toBeGreaterThanOrEqual(2);
  });

  test("a child session's request carries its root session", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_child", { title: "Fixture child", parentID: "ses_root" });
    host.sessions.set("ses_root", { title: "Parent" });
    permission(host, "ses_child");
    await until(() => relay.pushes().length === 1);
    const { payload } = await opened(relay.pushes()[0]!, device, serverPublicKey);
    expect(payload).toMatchObject({ sessionID: "ses_child", rootSessionID: "ses_root", title: "Fixture child" });
    expect(relay.pushes()[0]!.body.thread).toBe(await threadFor(device.keyID, "ses_root"));
  });

  test("events without a location are ignored", async () => {
    const { host } = await setup();
    host.permissions.set("per_nowhere", "ses_root");
    host.emit({ id: "evt_nowhere", type: "permission.asked", location: null, data: { id: "per_nowhere", sessionID: "ses_root", action: "shell", resources: ["ls"] } });
    await sleep(200);
    expect(relay.pushes()).toEqual([]);
  });

  test("the pending count spans every location in the process", async () => {
    const shared = createSharedState(), storage = new MemoryStorage();
    const first = await setup({ shared }, new FakeHost("/work/one", storage));
    const second = await startService(new FakeHost("/work/two", storage), { shared });
    services.push(second.service);
    second.host.permissions.set("per_other", "ses_two");
    second.host.emit({ id: "evt_other", type: "permission.asked", data: { id: "per_other", sessionID: "ses_two", action: "read", resources: ["a"] } });
    await until(() => relay.pushes().length === 1);
    permission(first.host);
    await until(() => relay.pushes().length === 2);
    const pendings = await Promise.all(relay.pushes().map(async (push) => (await opened(push, first.device, first.serverPublicKey)).payload.pending));
    expect(pendings).toEqual([1, 2]);
  });
});

describe("replacements", () => {
  const replied = (host: FakeHost, data: { id: string; sessionID: string }, decision: string, eventID = `evt_late_${data.id}`) =>
    host.emit({ id: eventID, type: "permission.replied", data: { sessionID: data.sessionID, requestID: data.id, reply: decision } });
  const replies = async (pushes: { body: { envelope: never } }[], device: FakeDevice, serverPublicKey: string) =>
    Object.fromEntries(await Promise.all(pushes.map(async (push) => {
      const { payload } = await opened(push, device, serverPublicKey);
      return [payload.requestID, payload.reply];
    })));

  test("a reply event that arrives within the window replaces a cancelled re-check before it is sent", async () => {
    const { host, device, serverPublicKey, shared } = await setup({ replyWindowMilliseconds: 500 });
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    host.permissions.delete(request.id); // replied and removed, but permission.replied is still queued
    host.emit({ id: "evt_interrupt_race", type: "session.execution.interrupted", data: { sessionID: "ses_root", reason: "user" } });
    await until(() => !shared.pending.has(request.id)); // the re-check settled it as cancelled
    await sleep(50);
    replied(host, request, "once");
    await until(() => relay.pushes().length === 2);
    await sleep(600);
    expect(relay.pushes().length).toBe(2);
    const [original, replacement] = relay.pushes();
    expect(replacement!.body.collapse).toBe(original!.body.collapse);
    expect((await opened(replacement!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: request.id, reply: "once" });
  });

  test("a reply event that arrives while the cancelled replacement is in flight is sent after it, and only once", async () => {
    const { host, device, serverPublicKey } = await setup({ replyWindowMilliseconds: 20 });
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    relay.script(device.sendToken, { status: 200, body: { result: "delivered" }, delay: 300 });
    host.permissions.delete(request.id);
    host.emit({ id: "evt_interrupt_flight", type: "session.execution.interrupted", data: { sessionID: "ses_root", reason: "user" } });
    await until(() => relay.pushes().length === 2); // the cancelled replacement, which the relay holds for 300 ms
    replied(host, request, "once");
    await until(() => relay.pushes().length === 3);
    const [original, cancelled, corrected] = relay.pushes();
    // The correction waited for the answer to the push it corrects, so the device ends on the reply.
    expect(corrected!.received).toBeGreaterThanOrEqual(cancelled!.answered!);
    expect((await opened(cancelled!, device, serverPublicKey)).payload.reply).toBe("cancelled");
    expect((await opened(corrected!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: request.id, reply: "once" });
    expect(new Set([original, cancelled, corrected].map((push) => push!.body.collapse)).size).toBe(1);
    // The same reply seen again, by a second instance say, sends nothing more.
    replied(host, request, "once", `evt_again_${request.id}`);
    await sleep(150);
    expect(relay.pushes().length).toBe(3);
  });

  test("a request answered while its push is in flight is replaced once that push has been answered", async () => {
    const { host, device, serverPublicKey } = await setup();
    relay.script(device.sendToken, { status: 200, body: { result: "delivered" }, delay: 200 });
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    reply(host, request, "always");
    await until(() => relay.pushes().length === 2);
    const [original, replacement] = relay.pushes();
    expect(replacement!.received).toBeGreaterThanOrEqual(original!.answered!);
    expect((await opened(replacement!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: request.id, reply: "always" });
    await sleep(200);
    expect(relay.pushes().length).toBe(2);
  });

  test("location.shutdown handled before the location's rejections sends one replacement per request, with the rejection", async () => {
    const { host, device, serverPublicKey } = await setup({ replyWindowMilliseconds: 500 });
    const first = permission(host), second = permission(host, "ses_other");
    await until(() => relay.pushes().length === 2);
    // core/src/location-lifecycle.ts rejects every pending request and then publishes
    // location.shutdown; the plugin sees them the other way round here, and a little later.
    host.emit({ id: "evt_shutdown_first", type: "location.shutdown", data: {} });
    await sleep(50);
    reply(host, first, "reject");
    reply(host, second, "reject");
    await until(() => relay.pushes().length === 4);
    await sleep(600);
    expect(relay.pushes().length).toBe(4);
    expect(await replies(relay.pushes().slice(2), device, serverPublicKey)).toEqual({ [first.id]: "reject", [second.id]: "reject" });
  });

  test("location.shutdown after the rejections sends nothing more, and cancels a request it ends without one", async () => {
    const { host, device, serverPublicKey } = await setup();
    const answered = permission(host), dropped = permission(host, "ses_other");
    await until(() => relay.pushes().length === 2);
    reply(host, answered, "reject");
    host.emit({ id: "evt_shutdown_last", type: "location.shutdown", data: {} });
    await until(() => relay.pushes().length === 4);
    await sleep(250);
    expect(relay.pushes().length).toBe(4);
    expect(await replies(relay.pushes().slice(2), device, serverPublicKey)).toEqual({ [answered.id]: "reject", [dropped.id]: "cancelled" });
  });

  test("stopping sends a cancelled replacement that is still waiting for its window", async () => {
    const { host, device, serverPublicKey, service, shared } = await setup({ replyWindowMilliseconds: 60_000 });
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    host.permissions.delete(request.id);
    host.emit({ id: "evt_interrupt_stop", type: "session.execution.interrupted", data: { sessionID: "ses_root", reason: "user" } });
    await until(() => !shared.pending.has(request.id));
    expect(relay.pushes().length).toBe(1);
    await service.stop();
    expect(relay.pushes().length).toBe(2);
    expect((await opened(relay.pushes()[1]!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: request.id, reply: "cancelled" });
  });

  test("a reply after the push sends a passive replacement with the same collapse ID", async () => {
    const { host, device, serverPublicKey } = await setup();
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    reply(host, request, "reject");
    await until(() => relay.pushes().length === 2);
    const [original, replacement] = relay.pushes();
    expect(replacement!.body).toMatchObject({ kind: "resolved", priority: 5, collapse: original!.body.collapse, thread: original!.body.thread });
    const { payload } = await opened(replacement!, device, serverPublicKey);
    expect(payload).toMatchObject({ kind: "resolved", requestID: request.id, reply: "reject", pending: 0, sessionID: "ses_root", rootSessionID: "ses_root" });
  });
});

describe("presence", () => {
  test("a valid heartbeat suppresses pushes, an expired or background one does not", async () => {
    let now = Date.now();
    const { host, device } = await setup({ now: () => now });
    await host.call("setPresence", { keyID: device.keyID, foreground: true, sessionID: "ses_root" });
    permission(host);
    await sleep(200);
    expect(relay.pushes()).toEqual([]);
    now += CONTRACT.presence.validSeconds * 1000 + 1;
    permission(host);
    await until(() => relay.pushes().length === 1);
    await host.call("setPresence", { keyID: device.keyID, foreground: true });
    await host.call("setPresence", { keyID: device.keyID, foreground: false });
    permission(host);
    await until(() => relay.pushes().length === 2);
  });

  test("the replacement is sent even while the app is in the foreground", async () => {
    const { host, device } = await setup();
    const request = permission(host);
    await until(() => relay.pushes().length === 1);
    await host.call("setPresence", { keyID: device.keyID, foreground: true });
    reply(host, request);
    await until(() => relay.pushes().length === 2);
    expect(relay.pushes()[1]!.body.kind).toBe("resolved");
  });

  test("unknown presence sends", async () => {
    const { host } = await setup();
    permission(host);
    await until(() => relay.pushes().length === 1);
  });
});

describe("two locations", () => {
  /** opencode 2.1.3 delivers every location's events to every instance, each with its one location. */
  const everywhere = (hosts: FakeHost[], event: Parameters<FakeHost["emit"]>[0]) => { for (const host of hosts) host.emit(event); };
  async function pair() {
    const shared = createSharedState(), storage = new MemoryStorage();
    const first = await setup({ shared }, new FakeHost("/work/one", storage));
    const second = await startService(new FakeHost("/work/two", storage), { shared });
    services.push(second.service);
    return { first, second, storage };
  }

  test("only the instance of an event's location acts on it, so an event every instance receives is pushed once", async () => {
    const { first, second, storage } = await pair();
    const event = { id: "evt_everywhere", type: "session.execution.failed", location: { directory: "/work/two" }, data: { sessionID: "ses_root", error: { type: "provider", message: "Rate limited" } } };
    everywhere([first.host, second.host], event);
    await until(() => relay.pushes().length === 1);
    await sleep(150);
    expect(relay.pushes().length).toBe(1);
    expect((await opened(relay.pushes()[0]!, first.device, first.serverPublicKey)).payload.project).toBe("two");
    expect(storage.values.has("sent/evt_everywhere")).toBe(true);
  });

  test("a permission request is checked and pushed by its own location's instance, even when another sees it first", async () => {
    const { first, second } = await pair();
    // Only the second location's permission service holds it, as in opencode.
    second.host.permissions.set("per_two", "ses_two");
    everywhere([first.host, second.host], { id: "evt_asked_two", type: "permission.asked", location: { directory: "/work/two" }, data: { id: "per_two", sessionID: "ses_two", action: "edit", resources: ["a.txt"] } });
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, first.device, first.serverPublicKey)).payload).toMatchObject({ requestID: "per_two", project: "two" });
    // The reply also reaches both instances, and replaces the alert once.
    everywhere([first.host, second.host], { id: "evt_replied_two", type: "permission.replied", location: { directory: "/work/two" }, data: { sessionID: "ses_two", requestID: "per_two", reply: "once" } });
    await until(() => relay.pushes().length === 2);
    await sleep(150);
    expect(relay.pushes().map((push) => push.body.kind)).toEqual(["permission", "resolved"]);
  });

  test("a reply of a location whose instance stopped is settled by another instance", async () => {
    const { first, second } = await pair();
    second.host.permissions.set("per_left", "ses_two");
    everywhere([first.host, second.host], { id: "evt_asked_left", type: "permission.asked", location: { directory: "/work/two" }, data: { id: "per_left", sessionID: "ses_two", action: "edit", resources: ["a.txt"] } });
    await until(() => relay.pushes().length === 1);
    await second.service.stop();
    first.host.emit({ id: "evt_replied_left", type: "permission.replied", location: { directory: "/work/two" }, data: { sessionID: "ses_two", requestID: "per_left", reply: "reject" } });
    await until(() => relay.pushes().length === 2);
    expect((await opened(relay.pushes()[1]!, first.device, first.serverPublicKey)).payload).toMatchObject({ kind: "resolved", requestID: "per_left", reply: "reject" });
  });

  test("a Live Activity changes once for an event every instance receives", async () => {
    const { first, second } = await pair();
    await first.host.call("registerActivity", { keyID: first.device.keyID, activityRef: "act_two", sessionID: "ses_root" });
    everywhere([first.host, second.host], { id: "evt_done_everywhere", type: "session.execution.succeeded", location: { directory: "/work/one" }, data: { sessionID: "ses_root" } });
    await until(() => relay.activities().length === 1);
    await sleep(200);
    expect(relay.activities().map((call) => call.body.event)).toEqual(["end"]);
  });

  test("a session event without a location is placed by its session's location, learned from its other events", async () => {
    const { first, second } = await pair();
    // opencode 2.1.3 publishes session.execution.* without a location (seen live).
    everywhere([first.host, second.host], { id: "evt_created_far", type: "session.created", location: { directory: "/work/two" }, data: { sessionID: "ses_far" } });
    everywhere([first.host, second.host], { id: "evt_failed_far", type: "session.execution.failed", location: null, data: { sessionID: "ses_far", error: { type: "x", message: "boom" } } });
    await until(() => relay.pushes().length === 1);
    await sleep(150);
    expect(relay.pushes().length).toBe(1);
    expect((await opened(relay.pushes()[0]!, first.device, first.serverPublicKey)).payload).toMatchObject({ kind: "failed", sessionID: "ses_far", project: "two" });
  });

  test("a session first seen without a location is looked up, and acted on by its location's instance once", async () => {
    const { first, second } = await pair();
    for (const host of [first.host, second.host]) host.sessions.set("ses_older", { title: "Older", directory: "/work/one" });
    await first.host.call("registerActivity", { keyID: first.device.keyID, activityRef: "act_older", sessionID: "ses_older" });
    everywhere([first.host, second.host], { id: "evt_done_older", type: "session.execution.succeeded", location: null, data: { sessionID: "ses_older" } });
    await until(() => relay.pushes().length === 1 && relay.activities().length === 1);
    await sleep(150);
    expect((await opened(relay.pushes()[0]!, first.device, first.serverPublicKey)).payload).toMatchObject({ kind: "finished", sessionID: "ses_older", title: "Older", project: "one" });
    expect(relay.activities().map((call) => call.body.event)).toEqual(["end"]);
  });

  test("each instance reports the events it received by location", async () => {
    const { host } = await setup({}, new FakeHost("/work/own"));
    host.emit({ id: "evt_own", type: "session.execution.started", data: { sessionID: "ses_x" } });
    host.emit({ id: "evt_other", type: "session.moved", location: { directory: "/work/elsewhere" }, data: { sessionID: "ses_x" } });
    host.emit({ id: "evt_none", type: "installation.updated", location: null, data: {} });
    await until(async () => (await host.call("status")).instance.events.none === 1);
    expect((await host.call("status")).instance).toEqual({ location: "/work/own", events: { own: 1, other: { "session.moved": 1 }, none: 1 } });
  });

  test("a separate process serving the same location and store also skips a claimed event", async () => {
    const storage = new MemoryStorage();
    const first = await setup({}, new FakeHost("/work/one", storage));
    const second = await startService(new FakeHost("/work/one", storage), { shared: createSharedState() });
    services.push(second.service);
    const event = { id: "evt_shared_store", type: "session.execution.failed", data: { sessionID: "ses_root", error: { type: "x", message: "boom" } } };
    first.host.emit(event);
    await until(() => relay.pushes().length === 1);
    second.host.emit(event);
    await sleep(150);
    expect(relay.pushes().length).toBe(1);
  });
});

describe("questions", () => {
  test("a form is pushed with its digest, options and free-text flag, and its cancellation replaces it", async () => {
    const { host, device, serverPublicKey } = await setup();
    const form = question(host);
    await until(() => relay.pushes().length === 1);
    const { payload } = await opened(relay.pushes()[0]!, device, serverPublicKey);
    expect(payload).toMatchObject({ kind: "question", requestID: form.id, summary: "Which color?", options: ["Blue", "Green"], freeText: true, digest: await formDigest(form) });
    host.emit({ id: "evt_cancel", type: "form.cancelled", data: { id: form.id, sessionID: form.sessionID } });
    await until(() => relay.pushes().length === 2);
    expect((await opened(relay.pushes()[1]!, device, serverPublicKey)).payload).toMatchObject({ kind: "resolved", reply: "cancelled" });
  });

  test("a form answered within the grace period is not pushed", async () => {
    const { host } = await setup({ graceMilliseconds: 150 });
    const form = question(host);
    host.emit({ id: "evt_answer", type: "form.replied", data: { id: form.id, sessionID: form.sessionID, answer: { q0: "Blue" } } });
    await sleep(300);
    expect(relay.pushes()).toEqual([]);
  });
});

describe("execution results", () => {
  test("a root session's success is pushed; a child's is not", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_root", { title: "Refactor" });
    host.sessions.set("ses_kid", { parentID: "ses_root" });
    host.emit({ id: "evt_child_done", type: "session.execution.succeeded", data: { sessionID: "ses_kid" } });
    host.emit({ id: "evt_root_done", type: "session.execution.succeeded", data: { sessionID: "ses_root" } });
    await until(() => relay.pushes().length === 1);
    await sleep(100);
    expect(relay.pushes().length).toBe(1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "finished", sessionID: "ses_root", title: "Refactor" });
  });

  test("a single-step run whose start waits on a session lookup is still pushed as finished", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_fresh", { title: "Fresh", directory: host.location.directory });
    // Seen live: started and succeeded come without a location, the step with one. The plugin has not
    // placed ses_fresh yet, so the start waits for ctx.session.get; the step must still count.
    host.emit({ id: "evt_fresh_started", type: "session.execution.started", location: null, data: { sessionID: "ses_fresh" } });
    host.emit({ id: "evt_fresh_step", type: "session.step.started", data: { sessionID: "ses_fresh" } });
    host.emit({ id: "evt_fresh_done", type: "session.execution.succeeded", location: null, data: { sessionID: "ses_fresh" } });
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "finished", sessionID: "ses_fresh", title: "Fresh" });
  });

  test("a run that took no step, such as applying a move, finishes without a push", async () => {
    const { host, device, serverPublicKey } = await setup();
    // opencode applies a move through the inbox: started, delivered, moved, succeeded, and no step (seen live).
    host.emit({ id: "evt_move_started", type: "session.execution.started", data: { sessionID: "ses_root" } });
    host.emit({ id: "evt_move_done", type: "session.execution.succeeded", data: { sessionID: "ses_root" } });
    await sleep(150);
    expect(relay.pushes()).toEqual([]);
    host.emit({ id: "evt_run_started", type: "session.execution.started", data: { sessionID: "ses_root" } });
    host.emit({ id: "evt_run_step", type: "session.step.started", data: { sessionID: "ses_root" } });
    host.emit({ id: "evt_run_done", type: "session.execution.succeeded", data: { sessionID: "ses_root" } });
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "finished", sessionID: "ses_root" });
  });

  test("a failure is pushed with its message, including a child's, under its root", async () => {
    const { host, device, serverPublicKey } = await setup();
    host.sessions.set("ses_kid", { parentID: "ses_root" });
    host.emit({ id: "evt_fail", type: "session.execution.failed", data: { sessionID: "ses_kid", error: { type: "api", message: "Provider returned 500" } } });
    await until(() => relay.pushes().length === 1);
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "failed", sessionID: "ses_kid", rootSessionID: "ses_root", summary: "Provider returned 500" });
  });

  test("preferences turn kinds off per device", async () => {
    const { host, device } = await setup();
    await register(host, relay, device, { prefs: { finished: false } });
    host.emit({ id: "evt_done_pref", type: "session.execution.succeeded", data: { sessionID: "ses_root" } });
    await sleep(150);
    expect(relay.pushes()).toEqual([]);
  });
});

describe("delivery", () => {
  test("transient failures are retried three times with backoff", async () => {
    const { host, device, delays, service } = await setup();
    relay.script(device.sendToken, { status: 503 }, { status: 200, body: { result: "rejected" } }, { status: 502 });
    host.emit({ id: "evt_retry", type: "session.execution.failed", data: { sessionID: "ses_root", error: { type: "x", message: "y" } } });
    await until(() => relay.pushes().length === 4);
    await service.settled();
    expect(delays).toEqual([1000, 2000, 4000]);
    expect((await host.call("listDevices")).devices[0].lastDelivery).toMatchObject({ kind: "failed", result: "delivered", attempts: 4 });
  });

  test("gone, from the relay or a revoked sender, removes the registration", async () => {
    for (const answer of [{ status: 200, body: { result: "gone" } }, { status: 401 }]) {
      const { host, device, service } = await setup();
      relay.script(device.sendToken, answer);
      host.emit({ id: `evt_gone_${answer.status}`, type: "session.execution.failed", data: { sessionID: "ses_root", error: { type: "x", message: "y" } } });
      await until(() => relay.pushes().some((push) => push.token === device.sendToken));
      await service.settled();
      expect((await host.call("listDevices")).devices).toEqual([]);
      await service.stop();
    }
  });

  test("throttled is recorded, not retried, and keeps the registration", async () => {
    const { host, device, service, delays } = await setup();
    relay.script(device.sendToken, { status: 200, body: { result: "throttled" } });
    host.emit({ id: "evt_throttle", type: "session.execution.failed", data: { sessionID: "ses_root", error: { type: "x", message: "y" } } });
    await until(() => relay.pushes().length === 1);
    await service.settled();
    expect(delays).toEqual([]);
    const [listed] = (await host.call("listDevices")).devices;
    expect(listed.lastDelivery).toMatchObject({ result: "throttled", attempts: 1 });
  });

  test("the test push ignores presence and preferences", async () => {
    const { host, device, serverPublicKey } = await setup();
    await register(host, relay, device, { prefs: { permission: false, question: false, finished: false, failed: false } });
    await host.call("setPresence", { keyID: device.keyID, foreground: true });
    expect(await host.call("test", { keyID: device.keyID })).toEqual({ result: "delivered", attempts: 1 });
    expect((await opened(relay.pushes()[0]!, device, serverPublicKey)).payload).toMatchObject({ kind: "test", server: "srv_home_mac" });
  });
});

describe("Live Activities", () => {
  async function withActivity(options: Parameters<typeof setup>[0] = {}) {
    const harness = await setup({ activityIntervalMilliseconds: 250, ...options });
    harness.host.sessions.set("ses_kid", { parentID: "ses_root" });
    await harness.host.call("registerActivity", { keyID: harness.device.keyID, activityRef: "act_1", sessionID: "ses_root" });
    return harness;
  }
  const start = (host: FakeHost, sessionID = "ses_root") => host.emit({ id: `evt_start_${++serial}`, type: "session.execution.started", created: Date.now(), data: { sessionID } });
  const done = (host: FakeHost, sessionID = "ses_root") => host.emit({ id: `evt_done_${++serial}`, type: "session.execution.succeeded", data: { sessionID } });
  const step = (host: FakeHost, sessionID = "ses_root") => host.emit({ id: `evt_step_${++serial}`, type: "session.step.started", data: { sessionID } });

  test("progress is throttled to priority 5 with a trailing update, and the end goes at once with priority 10", async () => {
    const { host } = await withActivity();
    start(host);
    await until(() => relay.activities().length === 1);
    step(host);
    host.emit({ id: "evt_tool", type: "session.tool.input.started", data: { sessionID: "ses_root", name: "shell" } });
    step(host);
    await sleep(100);
    expect(relay.activities().length).toBe(1);
    await until(() => relay.activities().length === 2);
    const [first, trailing] = relay.activities();
    expect(first!.body).toMatchObject({ ref: "act_1", event: "update", priority: 5, state: { phase: "running", step: 0, toolGlyph: "none" } });
    expect(trailing!.body).toMatchObject({ priority: 5, state: { phase: "running", step: 2, toolGlyph: "shell" } });
    expect(trailing!.body.staleAt).toBeGreaterThanOrEqual(Math.floor(Date.now() / 1000) + CONTRACT.activity.staleSeconds - 2);
    done(host);
    await until(() => relay.activities().length === 3);
    const end = relay.activities()[2]!.body;
    expect(end).toMatchObject({ event: "end", priority: 10, state: { phase: "succeeded", step: 2 } });
    expect(end.dismissAt - end.staleAt).toBe(CONTRACT.activity.dismissSeconds - CONTRACT.activity.staleSeconds);
    step(host);
    await sleep(350);
    expect(relay.activities().length).toBe(3);
  });

  test("a subagent starting and finishing during the root's run leaves the root's activity running", async () => {
    const { host } = await withActivity();
    start(host);
    await until(() => relay.activities().length === 1);
    step(host);
    start(host, "ses_kid");
    step(host, "ses_kid");
    host.emit({ id: "evt_kid_tool", type: "session.tool.input.started", data: { sessionID: "ses_kid", name: "read" } });
    done(host, "ses_kid");
    await until(() => relay.activities().length === 2);
    await sleep(300);
    expect(relay.activities().length).toBe(2);
    expect(relay.activities()[1]!.body).toMatchObject({ event: "update", state: { phase: "running", step: 2, toolGlyph: "read" } });
    expect(relay.activities()[1]!.body.state.startedAt).toBe(relay.activities()[0]!.body.state.startedAt);
    done(host);
    await until(() => relay.activities().length === 3);
    expect(relay.activities()[2]!.body).toMatchObject({ event: "end", state: { phase: "succeeded" } });
  });

  test("needs input waits for the grace period, and the answer returns to running at once", async () => {
    const { host } = await withActivity({ graceMilliseconds: 150 });
    start(host);
    await until(() => relay.activities().length === 1);
    const quick = permission(host, "ses_kid");
    await sleep(30);
    reply(host, quick);
    await sleep(250);
    expect(relay.activities().length).toBe(1);
    const slow = permission(host, "ses_kid");
    await until(() => relay.activities().length === 2);
    expect(relay.activities()[1]!.body).toMatchObject({ event: "update", priority: 10, state: { phase: "needsInput" } });
    reply(host, slow);
    await until(() => relay.activities().length === 3);
    expect(relay.activities()[2]!.body).toMatchObject({ event: "update", priority: 5, state: { phase: "running" } });
  });

  test("a reply that lands while the grace check is reading the request leaves the activity running and sends no push", async () => {
    const { host } = await withActivity({ graceMilliseconds: 60 });
    start(host);
    await until(() => relay.activities().length === 1);
    let release!: () => void;
    host.permissionGate = new Promise((resolve) => (release = resolve));
    const request = permission(host, "ses_kid");
    await sleep(120); // the grace period ended and #graceEnded is waiting on permission.get
    // opencode publishes permission.replied before it deletes the request, so the read still finds it.
    host.emit({ id: `evt_race_reply_${request.id}`, type: "permission.replied", data: { sessionID: "ses_kid", requestID: request.id, reply: "once" } });
    await sleep(30);
    release();
    host.permissionGate = undefined;
    host.permissions.delete(request.id);
    await sleep(300);
    step(host);
    await until(() => relay.activities().length === 2);
    expect(relay.activities().map((call) => call.body.state.phase)).toEqual(["running", "running"]);
    expect(relay.pushes().filter((push) => push.body.kind === "permission")).toEqual([]);
  });

  test("registering an activity for a session whose family cannot be read fails with a retryable error", async () => {
    const harness = await setup();
    harness.host.unavailable.add("ses_unknown");
    await expect(harness.host.call("registerActivity", { keyID: harness.device.keyID, activityRef: "act_lost", sessionID: "ses_unknown" }))
      .rejects.toMatchObject({ type: "unavailable", data: { field: "sessionID", retryable: true } });
    expect(harness.host.lookups.get("ses_unknown")).toBe(2);
    expect([...harness.host.storage.values.keys()].filter((key) => key.startsWith("activity/"))).toEqual([]);
  });

  test("registering an activity for a session opencode does not have fails with not_found, without a retry", async () => {
    const harness = await setup();
    harness.host.missing.add("ses_deleted");
    harness.host.sessions.set("ses_orphan", { parentID: "ses_deleted" });
    // Deleted, a child of a deleted session, and an ID opencode cannot decode.
    for (const sessionID of ["ses_deleted", "ses_orphan", "typo_0123"]) {
      await expect(harness.host.call("registerActivity", { keyID: harness.device.keyID, activityRef: "act_gone", sessionID }))
        .rejects.toMatchObject({ type: "not_found", data: { field: "sessionID", retryable: false } });
    }
    expect([harness.host.lookups.get("ses_deleted"), harness.host.lookups.get("typo_0123")]).toEqual([2, 1]); // once directly and once as the parent
    expect([...harness.host.storage.values.keys()].filter((key) => key.startsWith("activity/"))).toEqual([]);
  });

  test("an activity registered with a subagent's ID follows the root's run", async () => {
    const harness = await setup({ activityIntervalMilliseconds: 250 });
    harness.host.sessions.set("ses_kid", { parentID: "ses_root" });
    await harness.host.call("registerActivity", { keyID: harness.device.keyID, activityRef: "act_kid", sessionID: "ses_kid" });
    done(harness.host, "ses_kid");
    await sleep(100);
    expect(relay.activities()).toEqual([]);
    done(harness.host);
    await until(() => relay.activities().length === 1);
    expect(relay.activities()[0]!.body).toMatchObject({ ref: "act_kid", event: "end" });
  });

  test("the defaults are the contract's 3-second grace and 30-second activity interval", () => {
    expect(CONTRACT.plugin.graceMilliseconds).toBe(3000);
    expect(CONTRACT.activity.updateIntervalSeconds).toBe(30);
    expect(CONTRACT.activity.staleSeconds).toBe(300);
  });
});

describe("the server key", () => {
  test("is created once, even by instances starting together, and only its public half leaves storage", async () => {
    const shared = createSharedState(), storage = new MemoryStorage();
    const hosts = [new FakeHost("/a", storage), new FakeHost("/b", storage), new FakeHost("/c", storage)];
    const harnesses = await Promise.all(hosts.map((host) => startService(host, { shared })));
    services.push(...harnesses.map((harness) => harness.service));
    const keys = await Promise.all(harnesses.map(async (harness) => base64url.encode((await harness.service.serverKeys()).publicKey)));
    expect(new Set(keys).size).toBe(1);
    const stored = storage.values.get("key/server") as { privateKey: string; publicKey: string };
    expect(stored.publicKey).toBe(keys[0]);
    const status = await hosts[0]!.call("status");
    expect(status).toMatchObject({ package: CONTRACT.names.package, rpcVersion: 1, serverPublicKey: keys[0], devices: 0 });
    const device = await fakeDevice();
    const outputs = JSON.stringify([status, await register(hosts[1]!, relay, device), await hosts[2]!.call("listDevices")]);
    expect(outputs).not.toContain(stored.privateKey);
    expect(outputs).not.toContain(device.sendToken);
  });
});
