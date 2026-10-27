import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { SimulatorBridge } from './simulator-bridge.mjs';
test('simulator bridge preserves ciphertext and skips rejected APNs requests', async () => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'push-bridge-'));
  try {
    const body = { aps: { alert: { body: 'generic' }, 'mutable-content': 1, category: 'OPEN_ONLY' }, oc: { ct: 'opaque', kid: 'unknown' } };
    const accepted = { status: 200, problems: [], body, headers: { 'apns-topic': 'app.test', 'apns-push-type': 'alert' } };
    const calls = [];
    const bridge = new SimulatorBridge({ apns: { requests: [accepted, { ...accepted, status: 410 }] }, bundleID: 'app.test', device: 'booted', directory,
      run: async (command, args) => { calls.push([command, args]); assert.deepEqual(JSON.parse(await readFile(args.at(-1))), body); return { stdout: 'ok' }; } });
    await bridge.stop();
    assert.equal(calls.length, 1); assert.equal(bridge.deliveries.length, 1);
  } finally { await rm(directory, { recursive: true, force: true }); }
});
