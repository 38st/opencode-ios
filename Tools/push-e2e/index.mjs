// The local end-to-end for push: the sandboxed opencode with the plugin installed, the relay
// in the Workers local runtime (wrangler dev), and the mock APNs server. The plugin also sends
// straight to the mock in direct mode, with the same throwaway key. Nothing leaves this Mac.
//   node Tools/push-e2e/index.mjs [--version 2.x.y] [--no-swift]
// --no-swift skips the step that opens the captured pushes with OCPushCore in Swift.
import assert from 'node:assert/strict';
import path from 'node:path';
import net from 'node:net';
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { parseArgs } from 'node:util';
import { base64url, CONTRACT, formDigest, GENERIC_ALERTS, openEnvelope, permissionDigest } from '../../server/contracts/src/index.ts';
import { startMockApns } from '../../server/relay/test/support/mock-apns.ts';
import { resolveVersion, startSandbox } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { launch, run, stopAll } from '../opencode-sandbox/process.mjs';
import { startMock } from '../mock-llm/server.mjs';
import { Capture } from '../fixture-recorder/transport.mjs';
import { fakeDevice, openFor, pluginDirectory, registerDevice, repository, rpc, RpcFailure, script, until } from './support.mjs';
import { configureReview } from '../review-fixture/index.mjs';
import { changedWranglerHomes, isolatedEnvironment, snapshotWranglerHomes } from '../../server/relay/scripts/isolated.mjs';

const { values } = parseArgs({ options: { version: { type: 'string' }, simulator: { type: 'boolean' }, 'no-swift': { type: 'boolean' } } });
const version = await resolveVersion(values.version);
const runDirectory = path.join(repository, '.build/push-e2e', String(Date.now()));
const relayDirectory = path.join(repository, 'server/relay');
const TEAM_ID = 'TEAME2E001', KEY_ID = 'KEYE2E0001', BUNDLE_ID = 'com.example.opencode.e2e';
const LIMIT = 8;
const grace = CONTRACT.plugin.graceMilliseconds;
const quiet = grace + 2500;
const text = value => ({ deltas: [{ text: value }] });
const edit = { tools: [{ name: 'edit', arguments: { path: 'sample.txt', oldString: 'original', newString: 'edited' } }] };
const question = { tools: [{ name: 'question', arguments: { questions: [{ header: 'Color', question: 'Which color?', options: [{ label: 'Blue', description: 'Use blue' }, { label: 'Green', description: 'Use green' }] }] } }] };
const results = { version, measurements: {} };
const log = line => console.log(line);

async function freePort() {
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  await new Promise(resolve => server.close(resolve));
  return port;
}

/** The relay in workerd through `wrangler dev`, with local D1 and Durable Objects, sending to the mock. */
async function startRelay(mock, privateKeyPEM) {
  const state = path.join(runDirectory, 'relay-state');
  // wrangler's HOME, XDG and log directories point into this run, never at the account's own wrangler state.
  const env = { ...(await isolatedEnvironment(path.join(runDirectory, 'wrangler'))), CI: '1' };
  const variables = path.join(runDirectory, 'relay.env');
  // Secrets go in an env file, which wrangler hides, never on the command line.
  await writeFile(variables, [
    `APNS_TEAM_ID=${TEAM_ID}`, `APNS_KEY_ID=${KEY_ID}`, `APNS_PRIVATE_KEY="${privateKeyPEM.trim().replaceAll('\n', '\\n')}"`,
    `ALLOWED_BUNDLE_IDS=${BUNDLE_ID}`, `APNS_SANDBOX_URL=${mock.url}`, `APNS_PRODUCTION_URL=${mock.url}`,
    'RELAY_TEST_MODE=1', `RELAY_TEST_LIMITS='${JSON.stringify({ alertsPerMinute: LIMIT })}'`, '',
  ].join('\n'), { mode: 0o600 });
  const wrangler = path.join(relayDirectory, 'node_modules/.bin/wrangler');
  await run(wrangler, ['d1', 'migrations', 'apply', 'opencode-push-relay', '--local', '--persist-to', state], { cwd: relayDirectory, env });
  const port = await freePort(), url = `http://127.0.0.1:${port}`;
  const group = launch(wrangler, ['dev', '--local', '--ip', '127.0.0.1', '--port', String(port), '--persist-to', state,
    '--env-file', variables, '--show-interactive-dev-session=false', '--inspector-port', String(await freePort())], { cwd: relayDirectory, env });
  await until(async () => {
    group.check();
    try { return (await fetch(`${url}/v1/health`, { signal: AbortSignal.timeout(1000) })).ok; } catch { return false; }
  }, 'relay health', 120000);
  assert.equal((await (await fetch(`${url}/v1/health`)).json()).status, 'ok');
  return { url, group };
}

async function relayDevice(relay, apnsToken) {
  const created = await fetch(`${relay.url}/v1/devices`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ apnsToken, env: 'sandbox', bundleID: BUNDLE_ID }) });
  assert.equal(created.status, 201, await created.clone().text());
  const { deviceID, deviceSecret } = await created.json();
  const sender = await fetch(`${relay.url}/v1/devices/${deviceID}/senders`, { method: 'POST', headers: { authorization: `Bearer ${deviceSecret}` } });
  assert.equal(sender.status, 201, await sender.clone().text());
  return { deviceID, deviceSecret, apnsToken, ...(await sender.json()) };
}

async function turn(api, mock, server, name, calls) {
  await writeFile(path.join(server.project, 'sample.txt'), 'original fixture line\nsecond line\n');
  await script(mock, name, calls);
  const session = (await api.request('POST', '/api/session', { title: `E2E ${name}`, location: { directory: server.project }, model: { providerID: 'mock', id: 'mock-1' } })).data;
  await api.request('POST', `/api/session/${session.id}/prompt`, { text: `Run the ${name} end-to-end.` });
  return session;
}

/**
 * The first alert of `kind` the mock APNs recorded at or after index `from` whose sealed payload
 * matches `match`, and when this process saw it. Every session's end is pushed too, so alerts are
 * found by what they carry, not by position.
 */
async function nextAPNs(apns, phone, serverPublicKey, from, kind, match, label, timeout = grace + 20000, token = undefined) {
  const opened = new Map();
  const found = await until(async () => {
    for (const [index, request] of apns.requests.entries()) {
      if (index < from || request.body?.oc?.kind !== kind || (token && request.token !== token)) continue;
      if (!opened.has(index)) opened.set(index, (await openFor(request.body.oc, phone, serverPublicKey)).payload);
      const payload = opened.get(index);
      if (Object.entries(match).every(([key, value]) => payload[key] === value)) return { request, payload, index };
    }
  }, label, timeout);
  return { ...found, seen: performance.now() };
}

function checkAlert(request, kind, device) {
  assert.deepEqual(request.problems, [], `The mock APNs found problems: ${request.problems.join('; ')}`);
  assert.equal(request.status, 200);
  assert.equal(request.token, device.apnsToken);
  assert.equal(request.headers['apns-push-type'], 'alert');
  assert.equal(request.headers['apns-topic'], BUNDLE_ID);
  const policy = CONTRACT.kinds[kind];
  assert.equal(request.headers['apns-priority'], String(policy.priority));
  const aps = request.body.aps;
  assert.equal(aps.alert.body, GENERIC_ALERTS[kind], 'The alert must be the generic text');
  assert.equal(aps.category, CONTRACT.apns.category);
  assert.equal(aps['mutable-content'], 1);
  assert.equal(aps['interruption-level'], policy.interruptionLevel);
  assert.equal(request.body.oc.kind, kind);
  return request.body.oc;
}

/**
 * Direct mode: the same sealed pushes, sent by the plugin to the mock APNs over HTTP/2 with the
 * server owner's key, with no relay involved. The mock checks each request as it checks the relay's.
 */
async function directPass({ api, mock, server, apns, relayPhone }) {
  const status = await rpc(server, 'status');
  assert.deepEqual(status.direct, { available: true, bundleID: BUNDLE_ID, environment: 'sandbox' });
  // Only the direct phone from here on, so every alert below is the plugin's own.
  assert.deepEqual(await rpc(server, 'unregisterDevice', { keyID: relayPhone.keyID }), { removed: true });

  const phone = await fakeDevice('E2E direct iPhone');
  phone.apnsToken = '0' + randomBytes(32).toString('hex').slice(1);
  const direct = { transport: 'direct', apnsToken: phone.apnsToken, bundleID: BUNDLE_ID, environment: 'sandbox' };
  const refused = await registerDevice(server, phone, undefined, undefined, { ...direct, bundleID: 'com.example.other' }).catch(error => error);
  assert.ok(refused instanceof RpcFailure && refused.body?.data?.field === 'bundleID', `A mismatched bundle ID was not refused: ${refused}`);
  const { serverPublicKey } = await registerDevice(server, phone, undefined, undefined, direct);
  const listed = (await rpc(server, 'listDevices')).devices;
  assert.deepEqual(listed.map(device => [device.keyID, device.transport, device.relayURL]), [[phone.keyID, 'direct', undefined]]);
  assert.ok(!JSON.stringify([status, listed]).includes(phone.apnsToken), 'An RPC returned the APNs token');
  log('PASS direct mode is on from the plugin options; a direct device registered, and a mismatched bundle ID was refused');

  const next = (from, kind, match, label, timeout) => nextAPNs(apns, phone, serverPublicKey, from, kind, match, label, timeout, phone.apnsToken);
  const start = apns.requests.length;
  let mark = api.events.length;
  const session = await turn(api, mock, server, 'direct', [edit, text('Edited.')]);
  const asked = await api.event('permission.asked', item => api.events.indexOf(item) >= mark && item.data.sessionID === session.id, 60000);
  const alert = await next(start, 'permission', { requestID: asked.data.id }, 'direct permission alert');
  assert.equal(alert.request.protocol, 'h2', 'A direct push must arrive over HTTP/2');
  const envelope = checkAlert(alert.request, 'permission', phone);
  const fresh = (await api.request('GET', `/api/session/${session.id}/permission/${asked.data.id}`)).data;
  assert.equal((await openFor(envelope, phone, serverPublicKey)).payload.digest, await permissionDigest(fresh));
  await api.request('POST', `/api/session/${session.id}/permission/${asked.data.id}/reply`, { decision: 'once' });
  const replacement = await next(alert.index + 1, 'resolved', { requestID: asked.data.id }, 'direct replacement');
  checkAlert(replacement.request, 'resolved', phone);
  assert.equal(replacement.request.headers['apns-collapse-id'], alert.request.headers['apns-collapse-id']);
  await api.request('POST', `/api/experimental/session/${session.id}/wait`);
  checkAlert((await next(start, 'finished', { sessionID: session.id }, 'direct finished alert', 20000)).request, 'finished', phone);
  const providerTokens = new Set(apns.requests.slice(start).filter(request => request.protocol === 'h2').map(request => request.jwt));
  assert.equal(providerTokens.size, 1, 'The plugin minted more than one provider token');
  log('PASS the permission alert, its replacement under the same collapse ID and the session\'s end went straight to the mock APNs over HTTP/2, with one signed provider token');

  // A Live Activity: the push token is kept by the plugin, and the updates use the activity topic.
  await writeFile(path.join(server.project, 'sample.txt'), 'original fixture line\nsecond line\n');
  await script(mock, 'direct activity', [text('Done.')]);
  const activity = (await api.request('POST', '/api/session', { title: 'E2E direct activity', location: { directory: server.project }, model: { providerID: 'mock', id: 'mock-1' } })).data;
  const pushToken = '0' + randomBytes(40).toString('hex').slice(1);
  assert.deepEqual(await rpc(server, 'registerActivity', { keyID: phone.keyID, activityRef: 'act_direct', sessionID: activity.id, pushToken, expiresAt: Math.floor(Date.now() / 1000) + 3600 }), { registered: true });
  await api.request('POST', `/api/session/${activity.id}/prompt`, { text: 'Run the direct activity end-to-end.' });
  await api.request('POST', `/api/experimental/session/${activity.id}/wait`);
  const updates = await until(() => {
    const found = apns.requests.filter(request => request.token === pushToken);
    return found.some(request => request.body?.aps?.event === 'end') && found;
  }, 'direct Live Activity end', 30000);
  for (const request of updates) {
    assert.deepEqual(request.problems, [], request.problems.join('; '));
    assert.equal(request.headers['apns-topic'], `${BUNDLE_ID}.push-type.liveactivity`);
    assert.equal(request.headers['apns-push-type'], 'liveactivity');
  }
  assert.equal(updates.at(-1).headers['apns-priority'], '10');
  log(`PASS a Live Activity registered with its push token got ${updates.length} direct update(s) on the activity topic, ending with priority 10`);

  // gone: the mock answers 410 Unregistered for this token, and the plugin removes the registration.
  const lost = await fakeDevice('E2E direct lost iPhone');
  await registerDevice(server, lost, undefined, undefined, { ...direct, apnsToken: '410' + randomBytes(31).toString('hex').slice(0, 61) });
  assert.equal((await rpc(server, 'test', { keyID: lost.keyID })).result, 'gone');
  assert.deepEqual((await rpc(server, 'listDevices')).devices.map(device => device.keyID), [phone.keyID]);
  log('PASS APNs 410 on a direct push removed that registration');
}

await mkdir(runDirectory, { recursive: true });
const auditDir = path.join(repository, '.build/opencode-sandbox/audits', `push-e2e-${Date.now()}`);
// The account's own wrangler state must not change during the run; see server/relay/scripts/isolated.mjs.
const wranglerBefore = await snapshotWranglerHomes();
let serverRoot, privateKeyPEM;
await audit(auditDir, async () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  privateKeyPEM = privateKey.export({ type: 'pkcs8', format: 'pem' }).toString();
  const apns = await startMockApns({ teamID: TEAM_ID, keyID: KEY_ID, publicKeyPEM: publicKey.export({ type: 'spki', format: 'pem' }).toString(), bundleIDs: [BUNDLE_ID] });
  const mock = await startMock();
  /**
   * The plugin from this checkout, with direct mode on: the same throwaway key as the relay, in a
   * 600 file inside the sandbox, sending to the mock's cleartext HTTP/2 port instead of Apple.
   */
  const configurePlugin = async (config, dirs, env) => {
    const keyFile = path.join(dirs.config, 'apns', `AuthKey_${KEY_ID}.p8`);
    await mkdir(path.dirname(keyFile), { recursive: true, mode: 0o700 });
    await writeFile(keyFile, privateKeyPEM, { mode: 0o600 });
    config.plugins = [{ package: pluginDirectory, options: { apns: { keyFile, keyID: KEY_ID, teamID: TEAM_ID, bundleID: BUNDLE_ID, environment: 'sandbox', origin: apns.h2URL } } }];
    return configureReview(config, dirs, env);
  };
  let relay, server, api;
  try {
    log(`Push end-to-end against V2 ${version}; run ${path.relative(repository, runDirectory)}; audit ${path.relative(repository, auditDir)}`);
    relay = await startRelay(apns, privateKey.export({ type: 'pkcs8', format: 'pem' }).toString());
    log('PASS the relay runs in workerd (wrangler dev) with local D1 and Durable Objects');
    server = await startSandbox({ version, mockURL: mock.url, configure: configurePlugin });
    serverRoot = server.root;
    api = new Capture(server);
    await api.openSSE();

    // A fake phone: an APNs token and a sender at the relay, a raw X25519 key pair for this server.
    const phone = await fakeDevice('E2E iPhone');
    // The leading 0 keeps the token clear of every mock APNs failure prefix (410, 400b, 4290, 5000, 403e).
    phone.relay = await relayDevice(relay, '0' + randomBytes(32).toString('hex').slice(1));
    phone.sendToken = phone.relay.sendToken;
    const registered = await registerDevice(server, phone, relay.url);
    const serverPublicKey = registered.serverPublicKey;
    log('PASS the device registered at the relay and through the plugin RPC, with CryptoKit-format keys');

    const capture = { keyID: phone.keyID, recipientPrivateKey: base64url.encode(phone.keys.privateKey), senderPublicKey: serverPublicKey, pushes: [] };

    const next = (from, kind, match, label, timeout) => nextAPNs(apns, phone, serverPublicKey, from, kind, match, label, timeout);
    const alertsSince = (from, kind, match) => Promise.all(apns.requests.slice(from).filter(request => request.body?.oc?.kind === kind)
      .map(async request => (await openFor(request.body.oc, phone, serverPublicKey)).payload))
      .then(payloads => payloads.filter(payload => Object.entries(match).every(([key, value]) => payload[key] === value)));

    // A real permission request through the scripted model reaches the mock APNs as a generic alert.
    let mark = api.events.length;
    const session = await turn(api, mock, server, 'permission', [edit, text('Edited.')]);
    const asked = await api.event('permission.asked', item => api.events.indexOf(item) >= mark && item.data.sessionID === session.id, 60000);
    const askedAt = performance.now();
    const alert = await next(0, 'permission', { requestID: asked.data.id }, 'permission alert');
    results.measurements.permissionMilliseconds = Math.round(alert.seen - askedAt);
    const envelope = checkAlert(alert.request, 'permission', phone.relay);
    const opened = await openFor(envelope, phone, serverPublicKey);
    const fresh = (await api.request('GET', `/api/session/${session.id}/permission/${asked.data.id}`)).data;
    assert.equal(opened.payload.digest, await permissionDigest(fresh), 'The digest must match a fresh GET');
    capture.pushes.push({ envelope, payload: JSON.parse(new TextDecoder().decode(opened.plaintext)), request: fresh });
    log(`PASS a real permission request reached the mock APNs as a generic alert after ${results.measurements.permissionMilliseconds} ms (grace ${grace} ms), and its digest matches a fresh GET`);

    // Tampering is refused: the ciphertext, an authenticated header field, and a changed request.
    const flipped = base64url.decode(envelope.ct); flipped[0] ^= 1;
    await assert.rejects(openEnvelope({ ...envelope, ct: base64url.encode(flipped) }, { now: Math.floor(Date.now() / 1000), key: () => ({ recipientPrivateKey: phone.keys.privateKey, senderPublicKey: base64url.decode(serverPublicKey) }) }), { code: 'authentication' });
    await assert.rejects(openFor({ ...envelope, exp: envelope.exp + 1 }, phone, serverPublicKey), { code: 'authentication' });
    assert.notEqual(await permissionDigest({ ...fresh, resources: [...fresh.resources, 'other.txt'] }), opened.payload.digest);
    log('PASS a tampered envelope is refused, and a changed request no longer matches the digest');

    // The desktop answer replaces the alert, passively, under the same collapse ID.
    const answeredAt = performance.now();
    await api.request('POST', `/api/session/${session.id}/permission/${asked.data.id}/reply`, { decision: 'once' });
    const replacement = await next(alert.index + 1, 'resolved', { requestID: asked.data.id }, 'replacement');
    results.measurements.replacementMilliseconds = Math.round(replacement.seen - answeredAt);
    const replaced = checkAlert(replacement.request, 'resolved', phone.relay);
    assert.equal(replacement.request.headers['apns-collapse-id'], alert.request.headers['apns-collapse-id']);
    assert.equal(replacement.payload.reply, 'once');
    capture.pushes.push({ envelope: replaced, payload: replacement.payload });
    log(`PASS the desktop answer sent the passive replacement after ${results.measurements.replacementMilliseconds} ms, under the same collapse ID`);

    // The session's end, which opencode publishes without a location.
    await api.request('POST', `/api/experimental/session/${session.id}/wait`);
    const finished = await next(0, 'finished', { sessionID: session.id }, 'finished alert', 20000);
    capture.pushes.push({ envelope: checkAlert(finished.request, 'finished', phone.relay), payload: finished.payload });
    log('PASS the session\'s success reached the mock APNs as a "finished" alert');

    // A real question.
    mark = api.events.length;
    const asking = await turn(api, mock, server, 'question', [question, text('Blue selected.')]);
    const created = await api.event('form.created', item => api.events.indexOf(item) >= mark, 60000);
    const createdAt = performance.now();
    const form = created.data.form ?? created.data;
    const questionAlert = await next(0, 'question', { requestID: form.id }, 'question alert');
    results.measurements.questionMilliseconds = Math.round(questionAlert.seen - createdAt);
    const questionEnvelope = checkAlert(questionAlert.request, 'question', phone.relay);
    const freshForm = (await api.request('GET', `/api/session/${asking.id}/form/${form.id}`)).data;
    assert.equal(questionAlert.payload.digest, await formDigest(freshForm));
    assert.deepEqual(questionAlert.payload.options, ['Blue', 'Green']);
    capture.pushes.push({ envelope: questionEnvelope, payload: questionAlert.payload, form: freshForm });
    await api.request('POST', `/api/session/${asking.id}/form/${form.id}/reply`, { answer: { q0: 'Blue' } });
    const answered = await next(questionAlert.index + 1, 'resolved', { requestID: form.id }, 'question replacement');
    checkAlert(answered.request, 'resolved', phone.relay);
    assert.equal(answered.payload.reply, 'answered');
    await api.request('POST', `/api/experimental/session/${asking.id}/wait`);
    await next(0, 'finished', { sessionID: asking.id }, 'question session finished', 20000);
    log(`PASS a real question reached the mock APNs after ${results.measurements.questionMilliseconds} ms with its options and digest, and its answer replaced it`);

    // Nothing is sent for a request answered inside the grace period, or while the app is in the foreground.
    let count = apns.requests.length;
    mark = api.events.length;
    const quick = await turn(api, mock, server, 'quick', [edit, text('Edited.')]);
    const quickAsk = await api.event('permission.asked', item => api.events.indexOf(item) >= mark && item.data.sessionID === quick.id, 60000);
    await api.request('POST', `/api/session/${quick.id}/permission/${quickAsk.data.id}/reply`, { decision: 'once' });
    await api.request('POST', `/api/experimental/session/${quick.id}/wait`);
    await next(count, 'finished', { sessionID: quick.id }, 'quick session finished', 20000);
    await delay(quiet);
    assert.deepEqual([...await alertsSince(count, 'permission', { requestID: quickAsk.data.id }), ...await alertsSince(count, 'resolved', { requestID: quickAsk.data.id })], [],
      'A request answered within the grace period was pushed');
    log('PASS nothing is sent for a request answered within the grace period');
    await rpc(server, 'setPresence', { keyID: phone.keyID, foreground: true });
    count = apns.requests.length;
    mark = api.events.length;
    const present = await turn(api, mock, server, 'present', [edit, text('Edited.')]);
    const presentAsk = await api.event('permission.asked', item => api.events.indexOf(item) >= mark && item.data.sessionID === present.id, 60000);
    await delay(quiet);
    await api.request('POST', `/api/session/${present.id}/permission/${presentAsk.data.id}/reply`, { decision: 'reject' });
    await api.request('POST', `/api/experimental/session/${present.id}/wait`);
    await delay(1500);
    await rpc(server, 'setPresence', { keyID: phone.keyID, foreground: false });
    assert.equal(apns.requests.length, count, 'Presence did not suppress the pushes');
    log('PASS presence suppresses the request\'s push and the session\'s result');

    // The app's own code opens what reached the mock APNs.
    if (values['no-swift']) log('SKIP opening the captured pushes in Swift (--no-swift)');
    else {
    capture.now = Math.floor(Date.now() / 1000);
    const capturePath = path.join(runDirectory, 'swift-capture.json');
    await writeFile(capturePath, JSON.stringify(capture, null, 2) + '\n', { mode: 0o600 });
    const swift = await run('/usr/bin/xcrun', ['swift', 'test', '--package-path', 'Packages/OpencodeKit', '--filter', 'pushesFromTheEndToEndRunOpenInSwift'],
      { cwd: repository, env: { ...process.env, OPENCODE_PUSH_E2E_CAPTURE: capturePath } });
    await writeFile(path.join(runDirectory, 'swift.log'), swift);
    assert.equal((swift.match(/PASS Swift opened/g) ?? []).length, capture.pushes.length, swift.slice(-3000));
    log(`PASS OCPushCore opened all ${capture.pushes.length} captured pushes in Swift, recomputed both digests and refused tampered copies`);
    }

    // The relay's limit: test pushes until it answers throttled, without contacting APNs.
    count = apns.requests.length;
    let throttled, sent = 0;
    for (let attempt = 0; attempt < 2 * LIMIT + 2 && !throttled; attempt++) {
      const outcome = await rpc(server, 'test', { keyID: phone.keyID });
      if (outcome.result === 'throttled') throttled = outcome;
      else { assert.equal(outcome.result, 'delivered'); sent++; }
    }
    assert.ok(throttled, 'The relay never throttled');
    assert.equal(apns.requests.length, count + sent, 'A throttled push reached APNs');
    results.measurements.throttledAfter = sent;
    log(`PASS the relay answered throttled once the device's one-minute window held ${LIMIT} alerts (${sent} test pushes went first), without contacting APNs`);

    // gone: APNs answers 410 Unregistered for this token; the relay clears it and the plugin removes the device.
    const lost = await fakeDevice('E2E lost iPhone');
    lost.relay = await relayDevice(relay, '410' + randomBytes(31).toString('hex').slice(0, 61));
    lost.sendToken = lost.relay.sendToken;
    await registerDevice(server, lost, relay.url);
    assert.equal((await rpc(server, 'test', { keyID: lost.keyID })).result, 'gone');
    const listed = (await rpc(server, 'listDevices')).devices.map(device => device.keyID);
    assert.deepEqual(listed, [phone.keyID]);
    log('PASS APNs 410 becomes gone at the relay, and the plugin removed that registration');

    // No token, secret or envelope anywhere in the relay's output. Its own log lines (JSON, from
    // src/log.ts) carry counts and outcomes only; wrangler's dev access log adds request paths.
    const output = relay.group.output;
    for (const secret of [phone.relay.deviceSecret, phone.relay.sendToken, phone.relay.apnsToken, lost.relay.apnsToken, envelope.ct]) {
      assert.ok(!output.includes(secret), 'The relay output contains a token, secret or envelope');
    }
    const lines = output.split('\n').map(line => line.slice(line.indexOf('{'))).filter(line => line.startsWith('{"event"'));
    assert.ok(lines.length > 0, 'No relay log lines were captured');
    for (const line of lines) {
      assert.deepEqual(Object.keys(JSON.parse(line)).filter(key => !['event', 'route', 'kind', 'result', 'status', 'count'].includes(key)), [], line);
      assert.ok(!line.includes(phone.relay.deviceID) && !line.includes(phone.relay.senderID), line);
    }
    results.measurements.relayLogLines = lines.length;
    log(`PASS the relay's ${lines.length} log lines carry only event, route, kind, result, status and count, and its output no token, secret or envelope`);

    await directPass({ api, mock, server, apns, relayPhone: phone });
    await writeFile(path.join(runDirectory, 'report.json'), JSON.stringify(results, null, 2) + '\n');
    console.log(JSON.stringify(results.measurements));
  } finally {
    // Nested, so every step runs even when an earlier one throws; a hung teardown would stall the nightly.
    try { await api?.closeSSE(); } finally {
      try { await server?.stop(); } finally {
        try { await relay?.group.stop(); } finally {
          try { await stopAll(); } finally {
            try { await mock.close(); } finally {
              try { await apns.close(); } finally {
                // The env file holds this run's throwaway APNs test key.
                await rm(path.join(runDirectory, 'relay.env'), { force: true });
              }
            }
          }
        }
      }
    }
  }
});
// The server's own log: direct mode said it was on, and never printed the key.
const serverLog = await readFile(path.join(serverRoot, 'server.log'), 'utf8');
assert.match(serverLog, /\[mobilepush\] direct mode on: sending to APNs sandbox for /);
const keyBody = privateKeyPEM.split('\n').filter(line => line && !line.startsWith('-----'));
assert.ok(keyBody.every(line => !serverLog.includes(line)), 'The server log contains the APNs key');
console.log('PASS the server log shows direct mode on and never the APNs key');
const wranglerChanged = changedWranglerHomes(wranglerBefore, await snapshotWranglerHomes());
assert.deepEqual(wranglerChanged, [], `The account's wrangler state changed during the run: ${wranglerChanged.join(', ')}`);
console.log('PASS process cleanup, opencode isolation audit, and the account\'s wrangler state untouched');

if (values.simulator) console.log(await run(process.execPath, ['Tools/push-e2e/simulator.mjs', '--version', version], { cwd: repository }));
