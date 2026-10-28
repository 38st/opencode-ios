import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { vcsProvider, waitForNoProvider } from './vcs-reset.mjs';

const clock = () => {
  let time = 0;
  return { now: () => time, sleep: async ms => { time += ms; } };
};

test('the reset passes once the server reports no provider', async () => {
  const answers = ['git', 'git', undefined];
  let calls = 0;
  await waitForNoProvider(async () => answers[calls++], { timeout: 1000, interval: 100, ...clock() });
  assert.equal(calls, 3);
});

test('a server that keeps the repository fails the reset at the deadline', async () => {
  let calls = 0;
  await assert.rejects(waitForNoProvider(async () => { calls++; return 'git'; }, { timeout: 500, interval: 100, ...clock() }),
    /still reports a git repository/);
  assert.equal(calls, 6, 'Asked at 0, 100, 200, 300, 400 and at the 500 ms deadline');
});

test('no provider at the first answer needs no wait', async () => {
  let calls = 0;
  await waitForNoProvider(async () => { calls++; return undefined; }, { ...clock() });
  assert.equal(calls, 1);
});

test('an answer without its data object is an error, not "no provider"', async () => {
  const bodies = [{ data: { provider: 'git', branch: {} } }, { data: { branch: {} } }, {}, { data: null }];
  const http = createServer((_, response) => { response.setHeader('content-type', 'application/json'); response.end(JSON.stringify(bodies.shift())); });
  await new Promise(resolve => http.listen(0, '127.0.0.1', resolve));
  const server = { baseURL: `http://127.0.0.1:${http.address().port}`, password: 'test' };
  try {
    assert.equal(await vcsProvider(server, '/fixture'), 'git');
    assert.equal(await vcsProvider(server, '/fixture'), undefined);
    await assert.rejects(vcsProvider(server, '/fixture'), /without a data object/);
    await assert.rejects(vcsProvider(server, '/fixture'), /without a data object/);
  } finally {
    await new Promise(resolve => http.close(resolve));
  }
});
