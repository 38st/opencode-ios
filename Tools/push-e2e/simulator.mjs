// Local M5b simulator harness. No APNs connection, account, or simulator configuration.
import assert from 'node:assert/strict';
import http from 'node:http';
import path from 'node:path';
import { generateKeyPairSync, randomBytes } from 'node:crypto';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { execFile } from 'node:child_process';
import { promisify, parseArgs } from 'node:util';
import { startNodeRelay } from '../../server/relay/src/node-server.ts';
import { startMockApns } from '../../server/relay/test/support/mock-apns.ts';
import { startMock } from '../mock-llm/server.mjs';
import { Capture } from '../fixture-recorder/transport.mjs';
import { repository, resolveVersion, startSandbox } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { stopAll } from '../opencode-sandbox/process.mjs';
import { configurePlugin, script } from './support.mjs';
import { startRequestProxy } from './request-proxy.mjs';
import { SimulatorBridge } from './simulator-bridge.mjs';
const exec = promisify(execFile);
const { values } = parseArgs({ options: { version: { type: 'string' } } });
const version = await resolveVersion(values.version), runID = `ui-push-${Date.now()}`;
const directory = path.join(repository, '.build/push-e2e', runID);
await mkdir(directory, { recursive: true });
const signing = await readFile(path.join(repository, 'Config/Signing.xcconfig'), 'utf8');
const prefix = /^BUNDLE_ID_PREFIX\s*=\s*([A-Za-z0-9.-]+)\s*$/m.exec(signing)?.[1];
assert.ok(prefix, 'Signing.xcconfig must supply the bundle prefix');
const bundleID = `${prefix}.client`;
// simctl can print installer notices before its JSON (an Xcode update waiting for an administrator); skip them.
const listing = (await exec('xcrun', ['simctl', 'list', 'devices', 'available', '--json'])).stdout;
const devices = JSON.parse(listing.slice(listing.indexOf('{')));
const device = Object.values(devices.devices).flat().find(item => item.name === 'iPhone 17 Pro' && item.isAvailable);
assert.ok(device, 'The existing iPhone 17 Pro simulator is required; this harness never creates or configures simulators');
// Boot the existing device when a previous xcodebuild shut it down; `simctl push` needs a booted device.
if (device.state !== 'Booted') { await exec('xcrun', ['simctl', 'boot', device.udid]); await exec('xcrun', ['simctl', 'bootstatus', device.udid, '-b']); }
const help = await exec('xcrun', ['simctl', 'help', 'push']);
await writeFile(path.join(directory, 'simctl-push-help.txt'), help.stdout + help.stderr);
await audit(path.join(repository, '.build/opencode-sandbox/audits', runID), async () => {
  const keys = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const apns = await startMockApns({ teamID: 'TEAMLOCAL1', keyID: 'KEYLOCAL01', publicKeyPEM: keys.publicKey.export({ type: 'spki', format: 'pem' }).toString(), bundleIDs: [bundleID] });
  const relay = await startNodeRelay({ database: path.join(directory, 'relay.sqlite'), env: {
    APNS_TEAM_ID: 'TEAMLOCAL1', APNS_KEY_ID: 'KEYLOCAL01', APNS_PRIVATE_KEY: keys.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString(),
    APNS_SANDBOX_URL: apns.h2URL, APNS_PRODUCTION_URL: apns.h2URL, ALLOWED_BUNDLE_IDS: bundleID,
  }, log: () => {} });
  const mock = await startMock(), commands = [], reports = [], operations = [];
  let server, control, proxy, capture;
  const bridge = new SimulatorBridge({ apns, bundleID, device: device.udid, directory: path.join(directory, 'bridge') });
  try {
    server = await startSandbox({ version, mockURL: mock.url, configure: configurePlugin });
    capture = new Capture(server); await capture.openSSE();
    proxy = await startRequestProxy(server.baseURL);
    bridge.start();
    control = http.createServer(async (request, response) => {
      try {
        let text = ''; for await (const chunk of request) text += chunk;
        const body = text ? JSON.parse(text) : {};
        let output = {};
        if (request.url === '/next') { const next = commands.shift(); if (!next) { response.writeHead(204).end(); return; } output = next; }
        else if (request.url === '/command') { commands.push(body); }
        else if (request.url === '/report') {
          if (body.event === 'notificationShown') {
            const asked = capture.events.find(event => event.type === 'permission.asked' && event.data.id === body.requestID);
            assert.ok(asked, 'The visible notification must have a real permission event');
            body.shownAt = Date.now(); body.askedAt = asked.created; body.requestToShownMS = body.shownAt - asked.created;
            // The simulator does not run the NSE, so the push's arrival on the device is `simctl push` returning.
            const delivered = bridge.deliveries.find(item => item.index === body.index);
            if (delivered?.forwardedAt) body.requestToDeliveredMS = delivered.forwardedAt - asked.created;
          }
          if (body.event === 'actionReply') {
            const replied = await capture.event('permission.replied', event => event.data.requestID === body.requestID);
            body.replyAt = replied.created; body.actionToReplyMS = replied.created - body.startedAt;
          }
          reports.push(body); await writeFile(path.join(directory, 'reports.json'), JSON.stringify(reports, null, 2)); }
        else if (request.url === '/state') {
          output = { sample: await readFile(path.join(server.project, 'sample.txt'), 'utf8').catch(() => ''), rewrites: proxy.rewritten, reports, alerts: apns.requests.map((item, index) => ({ index, payload: item.body, type: item.headers['apns-push-type'], collapse: item.headers['apns-collapse-id'], status: item.status })), operations, deliveries: bridge.deliveries };
        } else if (request.url === '/activity-probe') {
          const payload = { aps: { timestamp: Math.floor(Date.now() / 1000), event: 'update', 'content-state': {
            phase: 'needsInput', step: 99, toolGlyph: 'question', startedAt: Date.now() / 1000, updatedAt: Date.now() / 1000,
          }, 'stale-date': Math.floor(Date.now() / 1000) + 300 } };
          const file = path.join(directory, 'liveactivity.apns'); await writeFile(file, JSON.stringify(payload));
          try { const result = await exec('xcrun', ['simctl', 'push', device.udid, bundleID, file]); output = { stdout: result.stdout }; }
          catch (error) { output = { error: error.stderr || error.message }; }
          reports.push({ event: 'simctlActivity', ...output });
        } else if (request.url === '/change') { proxy.changes.add(body.requestID);
        } else if (request.url === '/scenario') {
          await writeFile(path.join(server.project, 'sample.txt'), 'original fixture line\nsecond line\n');
          // `plain` completes without a tool (no permission); `hold` never answers until the session is interrupted.
          await script(mock, body.name, body.hold ? [{ deltas: [{ text: 'Holding for the stop check.' }], waitForAbort: true }]
            : body.plain ? [{ deltas: [{ text: 'Completed the activity check.' }] }]
            : [{ tools: [{ name: 'edit', arguments: { path: 'sample.txt', oldString: 'original', newString: 'edited' } }] }, { deltas: [{ text: 'Completed the edit.' }] }]);
          operations.push({ event: 'scenario', name: body.name, at: Date.now() });
        } else { response.writeHead(404).end(); return; }
        response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(output));
      } catch { response.writeHead(500).end('{"error":"harness failure"}'); }
    });
    await new Promise(resolve => control.listen(0, '127.0.0.1', resolve));
    const controlURL = `http://127.0.0.1:${control.address().port}`;
    const env = { ...process.env, TEST_RUNNER_OPENCODE_UI_TEST_ID: runID,
      TEST_RUNNER_OPENCODE_UI_URL: proxy.url, TEST_RUNNER_OPENCODE_UI_PASSWORD: server.password,
      TEST_RUNNER_OPENCODE_UI_DIRECTORY: server.project, TEST_RUNNER_OC_TEST_RELAY_URL: relay.url,
      TEST_RUNNER_OC_TEST_PUSH_CONTROL_URL: controlURL, TEST_RUNNER_OC_TEST_APNS_TOKEN: '0' + randomBytes(32).toString('hex').slice(1) }; // never a mock APNs failure prefix
    let failure;
    const outputLog = createWriteStream(path.join(directory, 'test.log'), { mode: 0o600 });
    console.log(`Simulator push tests: ${path.relative(repository, directory)}`);
    try {
      const running = exec('xcodebuild', ['-project', 'Opencode.xcodeproj', '-scheme', 'Opencode', '-destination', `platform=iOS Simulator,id=${device.udid}`,
        '-derivedDataPath', '.build/DerivedData', '-skipPackagePluginValidation', '-resultBundlePath', path.join(directory, 'tests.xcresult'),
        // A hung test fails at its execution time allowance instead of holding the run, as in the UI stages.
        '-parallel-testing-enabled', 'NO', '-test-timeouts-enabled', 'YES', '-only-testing:OpencodeUITests/PushSmokeTests', '-collect-test-diagnostics', 'never', 'test'], { cwd: repository, env, maxBuffer: 64 * 1024 * 1024 });
      running.child.stdout.pipe(outputLog, { end: false });
      running.child.stderr.pipe(outputLog, { end: false });
      await running;
    } catch (error) { failure = error; }
    finally { await new Promise(resolve => outputLog.end(resolve)); }
    await bridge.stop();
    const nseLogs = await exec('xcrun', ['simctl', 'spawn', device.udid, 'log', 'show', '--style', 'compact', '--last', '20m', '--predicate', 'eventMessage CONTAINS "OPENCODE_NSE_DID_RECEIVE"'], { maxBuffer: 1024 * 1024 }).catch(error => ({ stdout: '', stderr: error.message }));
    await writeFile(path.join(directory, 'nse-log.txt'), nseLogs.stdout + nseLogs.stderr);
    await writeFile(path.join(directory, 'results.json'), JSON.stringify({ version, reports, operations, deliveries: bridge.deliveries }, null, 2));
    if (failure) throw new Error(`Simulator push tests failed: ${path.relative(repository, directory)}/test.log`);
    console.log(`PASS simulator push checks: ${path.relative(repository, directory)}`);
  } finally {
    await bridge.stop(); control?.closeAllConnections(); await new Promise(resolve => control ? control.close(resolve) : resolve());
    await proxy?.close(); await capture?.closeSSE(); await server?.stop(); await stopAll(); await mock.close(); await relay.close(); await apns.close();
  }
});
