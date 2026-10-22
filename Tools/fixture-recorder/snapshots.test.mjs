import test from 'node:test';
import assert from 'node:assert/strict';
import { captureSnapshot } from './scenarios.mjs';

test('session snapshots capture every page and all five read collections', async () => {
  const requests = [];
  const capture = {
    events: [{ type: 'server.connected' }],
    async request(method, path) {
      assert.equal(method, 'GET'); requests.push(path);
      if (path.includes('/message?')) return path.includes('cursor=')
        ? { data: [{ id: 'second' }], cursor: {} }
        : { data: [{ id: 'first' }], cursor: { next: 'opaque/+' } };
      return { data: path === '/api/session/s' ? { id: 's' } : [] };
    },
  };
  await captureSnapshot(capture, 's', 'end');
  assert.deepEqual(capture.snapshots, [{ phase: 'end', sessionID: 's', eventOffset: 1,
    session: { id: 's' }, messages: [{ id: 'first' }, { id: 'second' }], inbox: [], permissions: [], forms: [] }]);
  assert.deepEqual(requests, ['/api/session/s', '/api/session/s/message?limit=200&order=asc',
    '/api/session/s/message?limit=200&cursor=opaque%2F%2B', '/api/session/s/inbox', '/api/session/s/permission', '/api/session/s/form']);
});

test('a repeated message cursor fails recording rather than publishing an incomplete snapshot', async () => {
  const capture = { events: [], async request(_method, path) {
    return path.includes('/message?') ? { data: [], cursor: { next: 'same' } } : { data: { id: 's' } };
  } };
  await assert.rejects(captureSnapshot(capture, 's', 'end'), /repeated its cursor/);
  assert.equal(capture.snapshots, undefined);
});
