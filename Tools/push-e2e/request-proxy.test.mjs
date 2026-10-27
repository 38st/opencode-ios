import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { startRequestProxy } from './request-proxy.mjs';

test('changed-request fault changes only the selected permission GET', async () => {
  const calls = [];
  const upstream = http.createServer((request, response) => {
    calls.push({ method: request.method, authorization: request.headers.authorization });
    response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ data: { id: 'per_1', resources: ['file'] } }));
  });
  await new Promise(resolve => upstream.listen(0, '127.0.0.1', resolve));
  const proxy = await startRequestProxy(`http://127.0.0.1:${upstream.address().port}`);
  try {
    const route = '/api/session/ses_1/permission/per_1';
    const read = async (suffix, method = 'GET') => (await fetch(proxy.url + suffix, { method, headers: { authorization: 'Bearer fixture' } })).json();
    assert.deepEqual((await read(route)).data.resources, ['file']);
    proxy.changes.add('per_1');
    assert.deepEqual((await read(route)).data.resources, ['file', 'changed-after-notification']);
    assert.deepEqual((await read(route + '/reply', 'POST')).data.resources, ['file']);
    assert.equal(proxy.rewritten.length, 1);
    assert.ok(calls.every(call => call.authorization === 'Bearer fixture'));
  } finally {
    await proxy.close(); upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
  }
});
