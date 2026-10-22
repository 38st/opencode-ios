import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startFaultProxy } from './fault-proxy.mjs';
import { run } from '../opencode-sandbox/process.mjs';

test('the harness redacts the fault proxy admin credential', async () => {
  const token = 'fixture-proxy-admin-secret';
  const output = await run(process.execPath, ['-e', 'process.stdout.write(process.env.TEST_RUNNER_OPENCODE_UI_PROXY_TOKEN)'],
    { env: { ...process.env, TEST_RUNNER_OPENCODE_UI_PROXY_TOKEN: token } });
  assert.equal(output, '[REDACTED]');
  assert.ok(!output.includes(token));
});

async function fixture(t) {
  const bodies = [];
  const events = new Set();
  const origin = http.createServer(async (req, res) => {
    if (req.url === '/events') {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write('data: first\n\n');
      events.add(res); res.once('close', () => events.delete(res));
      req.on('close', () => res.end()); return;
    }
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    bodies.push(Buffer.concat(chunks)); res.writeHead(200, { 'content-type': 'application/json' }).end('{"ok":true}');
  });
  await new Promise(resolve => origin.listen(0, '127.0.0.1', resolve));
  const proxy = await startFaultProxy(`http://127.0.0.1:${origin.address().port}`);
  t.after(async () => { await proxy.close(); origin.closeAllConnections(); await new Promise(resolve => origin.close(resolve)); });
  const admin = async body => {
    const response = await fetch(proxy.url + '/__fault', { method: body ? 'POST' : 'GET', headers: { 'x-fault-token': proxy.adminToken }, body: body && JSON.stringify(body) });
    assert.equal(response.status, 200); return response.json();
  };
  return { proxy, bodies, admin, emit: text => { for (const res of events) res.write(`data: ${text}\n\n`); } };
}
test('offline faults are reversible and admin requires the token', async t => {
  const { proxy, bodies, admin } = await fixture(t);
  assert.equal((await fetch(proxy.url + '/__fault')).status, 403);
  await admin({ blocked: true });
  await assert.rejects(fetch(proxy.url + '/api/session/s/prompt', { method: 'POST', body: '{}' }), TypeError);
  assert.equal(bodies.length, 0);
  await admin({ blocked: false });
  assert.equal((await fetch(proxy.url + '/api/session/s/prompt', { method: 'POST', body: '{}' })).status, 200);
  assert.equal(bodies.length, 1);
});
test('lost response reaches upstream once and records byte-identical retries', async t => {
  const { proxy, bodies, admin } = await fixture(t);
  await admin({ dropPrompts: 1 });
  const body = '{ "id": "msg_same", "text": "😀" }';
  await assert.rejects(fetch(proxy.url + '/api/session/s/prompt', { method: 'POST', body }));
  assert.equal((await fetch(proxy.url + '/api/session/s/prompt', { method: 'POST', body })).status, 200);
  assert.deepEqual(bodies.map(String), [body, body]);
  const { admissions } = await admin();
  assert.equal(admissions.length, 2);
  assert.equal(admissions[0].sha256, admissions[1].sha256);
  assert.deepEqual(admissions.map(x => x.dropped), [true, false]);
});
test('SSE first event is delivered while response remains open', async t => {
  const { proxy, admin } = await fixture(t);
  const abort = new AbortController(); t.after(() => abort.abort());
  const response = await fetch(proxy.url + '/events', { signal: abort.signal });
  const reader = response.body.getReader();
  const chunk = await reader.read();
  assert.equal(new TextDecoder().decode(chunk.value), 'data: first\n\n');
  await admin({ blocked: true });
  await assert.rejects(reader.read());
});
test('event suppression leaves SSE connected and resumes without replaying buffered events', async t => {
  const { proxy, admin, emit } = await fixture(t);
  const abort = new AbortController(); t.after(() => abort.abort());
  const response = await fetch(proxy.url + '/events', { signal: abort.signal });
  const reader = response.body.getReader(); await reader.read();
  await admin({ pauseEvents: true }); emit('hidden');
  await new Promise(resolve => setTimeout(resolve, 20));
  await admin({ pauseEvents: false }); emit('visible');
  assert.equal(new TextDecoder().decode((await reader.read()).value), 'data: visible\n\n');
});
