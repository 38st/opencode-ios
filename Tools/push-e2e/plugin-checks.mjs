// Live checks of the push plugin inside the sandboxed opencode server, with the scripted model
// and a recording relay: plugin loading and RPC registration, one instance per location, what is pushed for
// requests, results, presence, Stop and Live Activities, and where ctx.storage keeps its data.
//   node Tools/push-e2e/plugin-checks.mjs [--version 2.x.y]
// Tools/contract/index.mjs runs the same checks.
import assert from 'node:assert/strict';
import path from 'node:path';
import { cp, mkdir, readFile, realpath, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { parseArgs } from 'node:util';
import { pathToFileURL } from 'node:url';
import { classify, CONTRACT, PACKAGE_NAME, permissionDigest } from '../../server/contracts/src/index.ts';
import { resolveVersion, startSandbox } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { run, stopAll } from '../opencode-sandbox/process.mjs';
import { startMock } from '../mock-llm/server.mjs';
import { Capture } from '../fixture-recorder/transport.mjs';
import { configureReview } from '../review-fixture/index.mjs';
import {
  configurePlugin, fakeDevice, openFor, pluginDirectory, registerDevice, repository, rpc, RpcFailure, sandboxedCLI,
  script, startRecordingRelay, storageNamespace, storedKeys, until,
} from './support.mjs';

const grace = CONTRACT.plugin.graceMilliseconds;
const quiet = grace + 2500;
const text = value => ({ deltas: [{ text: value }] });
const edit = { tools: [{ name: 'edit', arguments: { path: 'sample.txt', oldString: 'original', newString: 'edited' } }] };
const subagent = { tools: [{ name: 'subagent', arguments: { agent: 'general', prompt: 'Edit the fixture file.', description: 'Fixture child' } }] };
const sample = 'original fixture line\nsecond line\n';

/** Starts a scripted turn in a new session at `directory` and returns the session. */
async function turn(api, mock, directory, name, calls) {
  await writeFile(path.join(directory, 'sample.txt'), sample);
  await script(mock, name, calls);
  const session = (await api.request('POST', '/api/session', { title: `Push ${name}`, location: { directory }, model: { providerID: 'mock', id: 'mock-1' } })).data;
  await api.request('POST', `/api/session/${session.id}/prompt`, { text: `Run the ${name} push check.` });
  return session;
}
const wait = (api, id) => api.request('POST', `/api/experimental/session/${id}/wait`);
const reply = (api, request, decision) => api.request('POST', `/api/session/${request.sessionID}/permission/${request.id}/reply`, { decision });

/** The first permission.asked after `mark` (an index into the captured events) that matches. */
async function asked(api, mark, predicate = () => true) {
  const event = await api.event('permission.asked', item => api.events.indexOf(item) >= mark && predicate(item), 60000);
  return { event, seen: performance.now() };
}

/** The configuration install: the plugin directory in `plugins`. Returns what each check observed. */
async function configurationChecks({ version, mock, log }) {
  const results = {};
  const relay = await startRecordingRelay();
  let server, api;
  try {
    server = await startSandbox({ version, mockURL: mock.url, configure: configurePlugin });
    results.version = server.info.version;
    api = new Capture(server);
    await api.openSSE();
    const first = await realpath(server.project);
    const second = path.join(server.root, 'second-project');
    await mkdir(second);
    await writeFile(path.join(second, 'sample.txt'), sample);
    await run('/usr/bin/git', ['init', '--quiet', second], { env: server.env, cwd: server.root });
    const secondReal = await realpath(second);

    // RPC and rpc.register with `{}` schemas: the plugin answers on the default location.
    const status = await rpc(server, 'status');
    assert.equal(status.package, PACKAGE_NAME);
    assert.equal(status.rpcVersion, 1);
    assert.equal(status.devices, 0);
    assert.match(status.serverPublicKey, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(await realpath(status.instance.location), first);
    log('PASS plugin loads from the configuration, and rpc.register with {} schemas answers POST /api/rpc/mobilepush/status');

    // Storage is global: a device registered through one location is seen by the other's instance.
    const device = await fakeDevice('Live iPhone');
    const registered = await registerDevice(server, device, relay.url);
    assert.equal(registered.serverPublicKey, status.serverPublicKey);
    const statusB = await rpc(server, 'status', undefined, second);
    assert.equal(await realpath(statusB.instance.location), secondReal, 'One instance runs per location');
    assert.equal(statusB.devices, 1, 'ctx.storage is shared by every location');
    assert.equal(statusB.serverPublicKey, status.serverPublicKey);
    results.instances = 'one per location; storage global';
    log('PASS one plugin instance per location, and ctx.storage is global across them');

    // Every push the relay received, opened with the device key, in order.
    const decoded = [];
    const pushes = async () => {
      for (const item of relay.pushes().slice(decoded.length)) decoded.push({ ...item, payload: (await openFor(item.body.envelope, device, status.serverPublicKey)).payload });
      return decoded;
    };
    const pushOf = (match, label, timeout = grace + 20000) => until(async () => (await pushes()).find(item => Object.entries(match).every(([key, value]) => item.payload[key] === value)), label, timeout);
    const pushesOf = async match => (await pushes()).filter(item => Object.entries(match).every(([key, value]) => item.payload[key] === value));

    // A real permission request reaches the relay, sealed, with every field right.
    let mark = api.events.length;
    const plain = await turn(api, mock, server.project, 'permission', [edit, text('Edited.')]);
    const { event, seen } = await asked(api, mark, item => item.data.sessionID === plain.id);
    const request = event.data;
    const push = await pushOf({ kind: 'permission', requestID: request.id }, 'permission push');
    results.latency = { fromEventMilliseconds: Math.round(push.at - seen), graceMilliseconds: grace };
    assert.equal(push.token, device.sendToken);
    assert.equal(push.body.envelope.kid, device.keyID);
    assert.equal(push.body.priority, 10);
    const fresh = (await api.request('GET', `/api/session/${plain.id}/permission/${request.id}`)).data;
    assert.deepEqual(push.payload, {
      v: 1, kind: 'permission', server: 'srv_live_check', exp: push.body.expiresAt, pending: 1,
      sessionID: plain.id, rootSessionID: plain.id, title: (await api.request('GET', `/api/session/${plain.id}`)).data.title, project: path.basename(server.project),
      requestID: request.id, action: 'edit', summary: push.payload.summary,
      risk: classify('edit', fresh.resources).tier, digest: await permissionDigest(fresh),
    });
    assert.match(push.payload.summary, /sample\.txt/);
    results.permissionPayload = push.payload;
    log(`PASS a real permission request is pushed after the grace period (${results.latency.fromEventMilliseconds} ms after the event), sealed with the right fields and digest`);

    // The desktop answer sends the replacement under the same collapse ID.
    await reply(api, request, 'once');
    const replaced = await pushOf({ kind: 'resolved', requestID: request.id }, 'resolved push', 20000);
    assert.equal(replaced.body.collapse, push.body.collapse);
    assert.equal(replaced.body.priority, 5);
    assert.deepEqual(replaced.payload, { v: 1, kind: 'resolved', server: 'srv_live_check', exp: replaced.body.expiresAt, pending: 0, sessionID: plain.id, rootSessionID: plain.id, requestID: request.id, reply: 'once' });
    assert.ok(storedKeys(server).includes(`${storageNamespace}sent/${event.id}`), 'The push claimed its event ID');
    log('PASS the desktop answer replaces the alert with "once" under the same collapse ID');

    // The root's success arrives without a location in 2.1.3; the plugin places it by its session.
    await wait(api, plain.id);
    const finished = await pushOf({ kind: 'finished', sessionID: plain.id }, 'finished push', 20000);
    assert.equal(finished.payload.rootSessionID, plain.id);
    log('PASS a root session\'s success is pushed as finished, although opencode publishes it without a location');

    // An answer inside the grace period means no push for that request.
    mark = api.events.length;
    const quick = await turn(api, mock, server.project, 'answered-quickly', [edit, text('Edited.')]);
    const quickRequest = (await asked(api, mark, item => item.data.sessionID === quick.id)).event.data;
    await reply(api, quickRequest, 'once');
    await wait(api, quick.id);
    await delay(quiet);
    assert.deepEqual(await pushesOf({ requestID: quickRequest.id }), [], 'An answer inside the grace period sent a push');
    log('PASS an answer inside the grace period sends nothing for the request');

    // Presence: a valid foreground heartbeat suppresses the request's push and the session's result.
    assert.deepEqual(await rpc(server, 'setPresence', { keyID: device.keyID, foreground: true }), { validSeconds: 45, heartbeatSeconds: 30 });
    mark = api.events.length;
    const present = await turn(api, mock, server.project, 'present', [edit, text('Edited.')]);
    const presentRequest = (await asked(api, mark, item => item.data.sessionID === present.id)).event.data;
    await delay(quiet);
    await reply(api, presentRequest, 'reject');
    await wait(api, present.id);
    await delay(1500);
    assert.deepEqual(await pushesOf({ sessionID: present.id }), [], 'Presence did not suppress the pushes');
    await rpc(server, 'setPresence', { keyID: device.keyID, foreground: false });
    log('PASS a valid presence heartbeat suppresses the push');

    // A subagent's request carries the root session; the family comes from ctx.session.get.
    mark = api.events.length;
    const root = await turn(api, mock, server.project, 'child', [subagent, edit, text('Child edited.'), text('Root done.')]);
    const childAsk = (await asked(api, mark)).event.data;
    assert.notEqual(childAsk.sessionID, root.id, 'The request should come from the subagent session');
    const child = (await pushOf({ kind: 'permission', requestID: childAsk.id }, 'child push')).payload;
    assert.equal(child.sessionID, childAsk.sessionID);
    assert.equal(child.rootSessionID, root.id);
    // The activity registered with the child's ID follows the root.
    assert.deepEqual(await rpc(server, 'registerActivity', { keyID: device.keyID, activityRef: 'act_live_child', sessionID: childAsk.sessionID }), { registered: true });
    assert.ok(storedKeys(server).includes(`${storageNamespace}activity/${device.keyID}/act_live_child`));
    await reply(api, childAsk, 'once');
    await pushOf({ kind: 'resolved', requestID: childAsk.id }, 'child replacement', 20000);
    await wait(api, root.id);
    await pushOf({ kind: 'finished', sessionID: root.id }, 'root finished', 20000);
    await delay(1000);
    assert.deepEqual(await pushesOf({ kind: 'finished', sessionID: childAsk.sessionID }), [], 'A subagent\'s success was pushed');
    results.child = 'a subagent request carries sessionID = the child and rootSessionID = the root; only the root\'s success is pushed';
    log('PASS a subagent request carries its root session, read through ctx.session.get, and only the root\'s success is pushed');

    // A failure is pushed with its message.
    const failing = await turn(api, mock, server.project, 'failure', [{ error: { status: 400, message: 'Scripted terminal error' } }]);
    await wait(api, failing.id);
    const failed = await pushOf({ kind: 'failed', sessionID: failing.id }, 'failed push', 20000);
    assert.match(failed.payload.summary ?? '', /Scripted terminal error/);
    log('PASS a failed session is pushed with its error, although opencode publishes the failure without a location');

    // Stop: opencode drops the waiting request; the plugin replaces the alert once.
    mark = api.events.length;
    const stopped = await turn(api, mock, server.project, 'stop', [edit, text('Edited.')]);
    const stoppedRequest = (await asked(api, mark, item => item.data.sessionID === stopped.id)).event.data;
    await pushOf({ kind: 'permission', requestID: stoppedRequest.id }, 'stopped request push');
    const interrupted = await api.request('POST', `/api/session/${stopped.id}/interrupt`);
    assert.equal(interrupted.interrupted, true);
    const cancelled = await pushOf({ kind: 'resolved', requestID: stoppedRequest.id }, 'replacement after Stop', 20000);
    await delay(2500);
    assert.equal((await pushesOf({ requestID: stoppedRequest.id, kind: 'resolved' })).length, 1, 'Stop sent more than one replacement');
    results.stop = { reply: cancelled.payload.reply, repliedEvent: api.events.slice(mark).some(item => item.type === 'permission.replied' && item.data.requestID === stoppedRequest.id) };
    log(`PASS Stop replaces the pushed alert once (reply "${cancelled.payload.reply}"; permission.replied ${results.stop.repliedEvent ? 'was' : 'was not'} published)`);

    // A Live Activity follows the run: an update when it starts, the end at once with priority 10.
    const tracked = (await api.request('POST', '/api/session', { title: 'Push activity', location: { directory: server.project }, model: { providerID: 'mock', id: 'mock-1' } })).data;
    assert.deepEqual(await rpc(server, 'registerActivity', { keyID: device.keyID, activityRef: 'act_live_run', sessionID: tracked.id }), { registered: true });
    await script(mock, 'activity', [{ tools: [{ name: 'read', arguments: { path: 'sample.txt' } }] }, text('Read it.')]);
    await api.request('POST', `/api/session/${tracked.id}/prompt`, { text: 'Run the activity push check.' });
    await wait(api, tracked.id);
    const ended = await until(() => relay.activities().find(item => item.body.ref === 'act_live_run' && item.body.event === 'end'), 'activity end', 20000);
    const updates = relay.activities().filter(item => item.body.ref === 'act_live_run' && item.body.event === 'update');
    assert.ok(updates.length >= 1 && updates[0].body.state.phase === 'running' && updates[0].body.priority === 5, JSON.stringify(updates.map(item => item.body)));
    assert.equal(ended.body.state.phase, 'succeeded');
    assert.equal(ended.body.priority, 10);
    assert.ok(ended.body.dismissAt > ended.body.staleAt && ended.body.staleAt >= Math.floor(Date.now() / 1000) + CONTRACT.activity.staleSeconds - 30);
    results.activity = { updates: updates.map(item => item.body.state), end: ended.body.state };
    log(`PASS a Live Activity follows a live run: ${updates.length} update(s) from "running", then the end with priority 10`);

    // "Session not found" keeps its tag through the Promise adapter, so registerActivity answers not_found.
    const notFound = [];
    for (const sessionID of ['ses_0000000000000000000000000', 'typo_session']) {
      const failure = await rpc(server, 'registerActivity', { keyID: device.keyID, activityRef: 'act_live_missing', sessionID }).then(() => undefined, error => error);
      assert.ok(failure instanceof RpcFailure, `registerActivity(${sessionID}) succeeded`);
      assert.equal(failure.status, 400);
      assert.equal(failure.body?._tag, 'RpcError');
      assert.equal(failure.body?.type, 'not_found', JSON.stringify(failure.body));
      assert.deepEqual(failure.body?.data, { field: 'sessionID', retryable: false });
      notFound.push(failure.body);
    }
    results.notFound = notFound;
    log('PASS a missing session reaches the plugin with its tag, and registerActivity answers not_found (400 RpcError)');

    // Two locations: every instance receives every location's events, and only the event's own
    // location acts on it, so a request in the second location is pushed once, by its instance.
    mark = api.events.length;
    const away = await turn(api, mock, second, 'second-location', [edit, text('Edited.')]);
    const awayRequest = (await asked(api, mark, item => item.data.sessionID === away.id)).event.data;
    const awayPush = await pushOf({ kind: 'permission', requestID: awayRequest.id }, 'second location push');
    assert.equal(awayPush.payload.project, path.basename(second));
    await delay(2000);
    assert.equal((await pushesOf({ kind: 'permission', requestID: awayRequest.id })).length, 1, 'Two instances pushed one request');
    await reply(api, awayRequest, 'once');
    await wait(api, away.id);
    await pushOf({ kind: 'finished', sessionID: away.id }, 'second location finished', 20000);
    await delay(1000);
    assert.equal((await pushesOf({ kind: 'finished', sessionID: away.id })).length, 1, 'Two instances pushed one result');
    const delivered = (await rpc(server, 'status')).instance.events;
    assert.ok((delivered.other['permission.asked'] ?? 0) >= 1, `The first location's instance did not receive the second's events: ${JSON.stringify(delivered)}`);
    results.routing = 'every instance receives every location\'s events; the plugin acts only on its own location\'s, placing location-less session events by their session';
    log('PASS every instance receives every location\'s events, and a request and a result in a second location are pushed once, by its own instance');

    // session.moved reaches both instances like every event, and is never pushed.
    const moving = (await api.request('POST', '/api/session', { title: 'Push move', location: { directory: server.project }, model: { providerID: 'mock', id: 'mock-1' } })).data;
    const movedBefore = await Promise.all([rpc(server, 'status'), rpc(server, 'status', undefined, second)]);
    await api.request('POST', `/api/session/${moving.id}/move`, { directory: second });
    const moved = await api.event('session.moved', item => JSON.stringify(item.data).includes(moving.id), 30000);
    const target = moved.location?.directory;
    await until(async () => {
      const after = await Promise.all([rpc(server, 'status'), rpc(server, 'status', undefined, second)]);
      if (!target) return after[0].instance.events.none > movedBefore[0].instance.events.none;
      // The instance of the other location counts it under `other`.
      return after.some(item => item.instance.location !== target && (item.instance.events.other['session.moved'] ?? 0) >= 1);
    }, 'session.moved at the other location\'s instance', 20000);
    results.sessionMoved = { location: moved.location?.directory === secondReal || moved.location?.directory === second ? 'new location' : moved.location?.directory === first ? 'old location' : 'none', data: Object.keys(moved.data ?? {}).sort() };
    await delay(1000);
    assert.deepEqual(await pushesOf({ sessionID: moving.id }), [], 'session.moved sent a push');
    log(`PASS session.moved reaches both instances (event location: ${results.sessionMoved.location}) and sends nothing`);

    // ctx.storage is opencode's kv table, namespaced per plugin, holding the key pair and the claims.
    const stored = storedKeys(server);
    assert.ok(stored.length > 0 && stored.every(key => key.startsWith(storageNamespace)), JSON.stringify(stored));
    for (const key of ['key/server', `device/${device.keyID}`, `delivery/${device.keyID}`]) assert.ok(stored.includes(storageNamespace + key), key);
    results.storage = { namespace: storageNamespace, keys: stored.map(key => key.slice(storageNamespace.length).replace(/^(device|delivery|presence|activity|sent)\/.*/, '$1/…')).filter((key, index, all) => all.indexOf(key) === index) };
    const listed = await rpc(server, 'listDevices');
    assert.equal(listed.devices[0].lastDelivery.result, 'delivered');
    assert.ok(!JSON.stringify(listed).includes(device.sendToken), 'listDevices returned the send token');
    log(`PASS ctx.storage is opencode's kv table under ${storageNamespace}, and no RPC returns a token`);
    return results;
  } finally {
    // Each step runs even when an earlier one throws, so a failed assertion never leaves a server or the relay behind.
    try { await api?.closeSSE(); } finally {
      try { await server?.stop(); } finally { await relay.close(); }
    }
  }
}

/** The package install: `opencode plugin add` with a Git specifier, then a server that loads it. */
async function installChecks({ version, mock, log }) {
  let spec, output, configPath;
  const configure = async (config, dirs, env) => {
    const restrictions = configureReview(config, dirs, env);
    const root = path.dirname(dirs.project);
    const source = path.join(root, 'plugin-repo');
    // The package's `files`, as a Git repository with the package at its root.
    for (const name of ['package.json', 'package-lock.json', 'server.ts', 'src', 'contracts', 'LICENSE', 'README.md']) {
      await cp(path.join(pluginDirectory, name), path.join(source, name), { recursive: true });
    }
    const git = args => run('/usr/bin/git', args, { cwd: source, env });
    await git(['init', '--quiet', '--initial-branch=main']);
    await git(['add', '.']);
    await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Plugin package']);
    spec = `git+file://${source}`;
    // Run below the Git ceiling (the run root): from the root itself, Git's repository discovery
    // climbs into the checkout's .git, which the sandbox denies, and `git ls-remote` fails.
    output = await sandboxedCLI(version, ['plugin', 'add', spec], { env, cwd: dirs.project, root, deniedReads: restrictions.deniedReads });
    configPath = /added to (\S+)\s*$/m.exec(output)?.[1];
    assert.ok(configPath?.startsWith(dirs.config), `plugin add wrote outside the sandbox configuration: ${output}`);
    return restrictions;
  };
  const server = await startSandbox({ version, mockURL: mock.url, configure });
  try {
    assert.match(output, /installed and added to/, output);
    const global = JSON.parse(await readFile(configPath, 'utf8'));
    assert.deepEqual(global.plugins, [spec]);
    const status = await rpc(server, 'status');
    assert.equal(status.package, PACKAGE_NAME);
    log('PASS opencode plugin add installs a Git specifier into the global configuration, and the server loads it');
    return { command: 'opencode plugin add <npm or Git specifier>', scopeFlag: 'none', writes: 'the global configuration', output: output.trim().replaceAll(spec, '<spec>').replaceAll(configPath, '<config>/opencode.json') };
  } finally { await server.stop(); }
}

export async function runPluginChecks({ version, mock, log = console.log }) {
  const configuration = await configurationChecks({ version, mock, log });
  const install = await installChecks({ version, mock, log });
  return { ...configuration, install };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { values } = parseArgs({ options: { version: { type: 'string' } } });
  const version = await resolveVersion(values.version);
  const auditDir = path.join(repository, '.build/opencode-sandbox/audits', `push-plugin-${Date.now()}`);
  await audit(auditDir, async () => {
    const mock = await startMock();
    try {
      console.log(`Push plugin live checks against V2 ${version}; audit ${auditDir}`);
      const results = await runPluginChecks({ version, mock });
      await writeFile(path.join(auditDir, 'push-plugin.json'), JSON.stringify(results, null, 2) + '\n');
    } finally {
      try { await stopAll(); } finally { await mock.close(); }
    }
  });
  console.log('PASS process cleanup and isolation audit');
}
