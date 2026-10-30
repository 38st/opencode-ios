// The session features contract, against the sandbox: moving a session into a worktree (the `move` inbox item, then
// `session.moved` and its `location-switched` row), the transcript export with and without sanitising, usage
// statistics in a time zone, and a side question through `generate`, which leaves the history unchanged.
import assert from 'node:assert/strict';
import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { Capture, until } from '../fixture-recorder/transport.mjs';
import { run } from '../opencode-sandbox/process.mjs';

const at = directory => 'location%5Bdirectory%5D=' + encodeURIComponent(directory);
const text = (...parts) => ({ deltas: parts.map(part => ({ text: part })) });

export async function sessionsContract(sandbox, mock, { log = () => {} } = {}) {
  const c = new Capture(sandbox);
  await c.openSSE();
  const result = {};
  try {
    const directory = path.join(sandbox.root, 'sessions-contract');
    await mkdir(directory);
    await writeFile(path.join(directory, 'README.md'), 'Sessions contract fixture\n');
    const git = args => run('/usr/bin/git', args, { env: sandbox.env, cwd: directory });
    await git(['init', '--quiet', '--initial-branch=main']); await git(['add', 'README.md']);
    await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Fixture']);
    const projectID = (await c.request('GET', '/api/location?' + at(directory))).project.id;
    await fetch(mock.url + '/admin/scenario', { method: 'POST', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ name: 'sessions-contract', script: { calls: [text('Exported ', 'answer.'), text('Side answer.'), text('Moved answer.')] } }) });

    // One turn of history, then the export with and without sanitising.
    const session = (await c.request('POST', '/api/session', { title: 'Sessions contract', location: { directory } })).data;
    await c.request('POST', `/api/session/${session.id}/prompt`, { text: 'Export me' });
    await c.event('session.execution.succeeded', event => event.data.sessionID === session.id);
    const exported = await c.request('GET', `/api/experimental/session/${session.id}/export?sanitize=false`);
    const sanitized = await c.request('GET', `/api/experimental/session/${session.id}/export?sanitize=true`);
    log('export', JSON.stringify(exported).slice(0, 4000));
    log('sanitized', JSON.stringify(sanitized).slice(0, 4000));
    const transfer = exported.data ?? exported;
    assert.equal(transfer.info.id, session.id, 'The export carries the session');
    assert.ok(transfer.messages.some(message => message.type === 'user' && message.text === 'Export me'), 'The export carries the prompt');
    await c.request('GET', `/api/experimental/session/ses_missing/export?sanitize=true`, undefined, { status: 404 });
    result.export = { messages: transfer.messages.length, sanitizedMessages: (sanitized.data ?? sanitized).messages.length };

    // A side question: an answer, and no new row in the history.
    const before = (await c.request('GET', `/api/session/${session.id}/message?limit=200`)).data.length;
    const generated = await c.request('POST', `/api/session/${session.id}/generate`, { prompt: 'What did you just say?' });
    log('generate', JSON.stringify(generated));
    assert.equal(generated.data.text, 'Side answer.');
    assert.equal((await c.request('GET', `/api/session/${session.id}/message?limit=200`)).data.length, before, 'A side question stays out of the history');

    // Statistics over today in a fixed time zone, for this project.
    const now = Date.now();
    const statsQuery = `from=${now - 86_400_000}&to=${now + 60_000}&timezone=${encodeURIComponent('Europe/Istanbul')}&tools=summary`;
    const stats = await c.request('GET', `/api/experimental/session/stats?${statsQuery}&project=${encodeURIComponent(projectID)}`);
    log('stats', JSON.stringify(stats).slice(0, 4000));
    assert.ok(stats.data, 'Statistics are wrapped in data');
    const empty = await c.request('GET', `/api/experimental/session/stats?from=1&to=2&timezone=UTC`);
    log('stats-empty', JSON.stringify(empty).slice(0, 2000));
    await c.request('GET', `/api/experimental/session/stats?timezone=${encodeURIComponent('Not/AZone')}`, undefined, { status: 400 });
    result.stats = Object.keys(stats.data).sort();

    // Moving into a new worktree: the move waits in the inbox until it is applied.
    const worktree = await c.request('POST', '/api/worktree', { projectID });
    log('worktree', JSON.stringify(worktree));
    const target = worktree.directory ?? worktree.data?.directory;
    const listed = async () => { const list = await c.request('GET', '/api/worktree?projectID=' + encodeURIComponent(projectID)); return list.data ?? list; };
    await until(async () => (await listed()).some(item => item.directory === target), 'worktree listed', 60000);
    result.worktrees = (await listed()).map(item => ({ strategy: item.strategy ?? null, checkout: item.directory === directory }));
    await c.request('POST', `/api/session/${session.id}/move`, { directory: target, delivery: 'steer' }, { status: 204 });
    const moved = await c.event('session.moved', event => event.data.sessionID === session.id);
    log('moved', JSON.stringify(moved));
    assert.equal(moved.data.location.directory, target);
    const info = (await c.request('GET', `/api/session/${session.id}`)).data;
    assert.equal(info.location.directory, target, 'The session now lives in the worktree');
    const rows = (await c.request('GET', `/api/session/${session.id}/message?limit=200`)).data;
    assert.ok(rows.some(row => row.type === 'location-switched' && row.location.directory === target), 'The move is a transcript row');
    await c.request('POST', `/api/session/${session.id}/move`, { directory: path.join(directory, 'missing') }, { status: 400 });
    result.move = { enqueued: c.events.some(event => event.type === 'session.inbox.enqueued' && event.data.sessionID === session.id && event.data.item?.type === 'move') };

    await c.request('DELETE', `/api/session/${session.id}`, undefined, { status: 204 });
    return result;
  } finally { await c.closeSSE(); }
}
