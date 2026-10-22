import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { Capture, until } from './transport.mjs';
import { connectWS } from './websocket.mjs';

export const scenarioNames = [
  'plain-text', 'reasoning-text', 'read-glob-grep', 'permission-allow', 'permission-reject',
  'shell-output', 'question-form', 'subagent', 'steer-queue', 'interrupt', 'interrupt-resume',
  'revert', 'fork', 'compaction', 'retry-429', 'retry-500', 'final-error', 'pty', 'pairing', 'v1-probe',
];

export async function selectMock(mock, name) {
  await until(() => mock.state().active === 0, 'mock idle');
  const response = await fetch(mock.url + '/admin/scenario', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name }) });
  assert.equal(response.status, 200, await response.text());
}

export async function pairing(c) {
  await c.request('GET', '/api/info', undefined, { auth: null, status: 401 });
  await c.request('GET', '/api/info', undefined, { status: 200 });
  const pair = await c.request('POST', '/api/pair');
  assert.ok(pair.code);
  const redeemed = await c.request('GET', `/auth/connect/${pair.code}`, undefined, { auth: null, status: 200 });
  assert.match(redeemed.token, /^\d+\./);
  await c.request('GET', '/api/info', undefined, { auth: redeemed.token, status: 200 });
  await c.request('GET', `/auth/connect/${pair.code}`, undefined, { auth: null, status: 401 });
}

export async function pty(c) {
  const info = (await c.request('POST', '/api/pty', { command: '/bin/bash', args: ['--noprofile', '--norc'], title: 'Fixture PTY', env: { PS1: '', PROMPT_COMMAND: '', HISTFILE: '/dev/null' } })).data;
  let first, resumed;
  try {
    await c.request('PUT', `/api/pty/${info.id}`, { size: { cols: 100, rows: 30 } });
    first = await connectWS(c, `/api/pty/${info.id}/connect?cursor=0`, 1);
    const marker = await first.wait(frames => frames.find(frame => frame.opcode === 2 && frame.bytes[0] === 0), 'PTY binary cursor marker');
    const initial = JSON.parse(marker.bytes.subarray(1)).cursor;
    assert.ok(Number.isInteger(initial));
    first.send("printf 'fixture-pty-%s\\n' 'echo'\n");
    await first.wait(() => first.text().includes('fixture-pty-echo\r\n'), 'PTY echo');
    // Cursor units are UTF-16 code units, not UTF-8 bytes. The metadata follows
    // replay; only count live text frames after it.
    const markerIndex = first.received.indexOf(marker);
    const live = first.received.slice(markerIndex + 1).filter(f => f.opcode === 1).map(f => f.bytes.toString('utf8')).join('');
    const cursor = initial + live.length;
    await first.close(); first = undefined;
    resumed = await connectWS(c, `/api/pty/${info.id}/connect?cursor=${cursor}`, 2);
    const resumedMarker = await resumed.wait(frames => frames.find(f => f.opcode === 2 && f.bytes[0] === 0), 'PTY resumed marker');
    assert.ok(JSON.parse(resumedMarker.bytes.subarray(1)).cursor >= cursor);
    assert.ok(!resumed.text().includes('fixture-pty-echo'), 'Resume replayed already consumed echo');
    resumed.send("printf 'fixture-resume-%s\\n' 'ok'\n");
    await resumed.wait(() => resumed.text().includes('fixture-resume-ok\r\n'), 'PTY resumed echo');
  } finally {
    await first?.close(); await resumed?.close();
    await c.request('DELETE', `/api/pty/${info.id}`);
  }
  await c.event('pty.deleted', event => event.data.id === info.id);
}

export async function captureSnapshot(c, id, phase) {
  const session = (await c.request('GET', `/api/session/${id}`)).data;
  const messages = [];
  let cursor;
  const seen = new Set();
  do {
    const query = cursor ? `limit=200&cursor=${encodeURIComponent(cursor)}` : 'limit=200&order=asc';
    const page = await c.request('GET', `/api/session/${id}/message?${query}`);
    messages.push(...page.data);
    cursor = page.cursor?.next;
    if (cursor) {
      assert.ok(!seen.has(cursor), 'Message pagination repeated its cursor');
      seen.add(cursor);
    }
  } while (cursor);
  const inbox = (await c.request('GET', `/api/session/${id}/inbox`)).data;
  const permissions = (await c.request('GET', `/api/session/${id}/permission`)).data;
  const forms = (await c.request('GET', `/api/session/${id}/form`)).data;
  c.snapshots ??= [];
  c.snapshots.push({ phase, sessionID: id, eventOffset: c.events.length, session, messages, inbox, permissions, forms });
}

export async function conversation(c, name) {
  await writeFile(path.join(c.sandbox.project, 'sample.txt'), 'original fixture line\nsecond line\n');
  const session = (await c.request('POST', '/api/session', { title: `Fixture ${name}`, location: { directory: c.sandbox.project }, model: { providerID: 'mock', id: 'mock-1' } })).data;
  const id = session.id;
  const prompt = text => c.request('POST', `/api/session/${id}/prompt`, { text });
  const wait = () => c.request('POST', `/api/experimental/session/${id}/wait`);
  const snapshot = async (sessionID = id) => (await c.request('GET', `/api/session/${sessionID}/message?limit=200&order=asc`)).data;
  await captureSnapshot(c, id, 'start');
  const admitted = await prompt(`Run the ${name} fixture scenario.`);
  if (name.startsWith('permission-')) {
    const event = await c.event('permission.asked', e => e.data.sessionID === id);
    const request = event.data;
    await c.request('GET', `/api/session/${id}/permission`);
    await c.request('GET', `/api/session/${id}/permission/${request.id}`);
    await c.request('POST', `/api/session/${id}/permission/${request.id}/reply`, { decision: name === 'permission-allow' ? 'once' : 'reject', ...(name === 'permission-reject' ? { message: 'Keep the original fixture text.' } : {}) });
  }
  if (name === 'question-form') {
    const event = await c.event('form.created', e => e.data.form?.sessionID === id || e.data.sessionID === id);
    const form = event.data.form ?? event.data;
    await c.request('GET', `/api/session/${id}/form`);
    await c.request('GET', `/api/session/${id}/form/${form.id}`);
    await c.request('POST', `/api/session/${id}/form/${form.id}/reply`, { answer: { q0: 'Blue' } });
  }
  if (name === 'steer-queue' || name.startsWith('interrupt')) {
    await c.event(name.startsWith('interrupt') ? 'session.text.delta' : 'session.step.started', e => e.data.sessionID === id);
    if (name !== 'interrupt') await c.request('POST', `/api/session/${id}/prompt`, { text: 'Apply steering input.', delivery: 'steer' });
    if (name === 'steer-queue') await c.request('POST', `/api/session/${id}/prompt`, { text: 'Run this on the next turn.', delivery: 'queue' });
    await c.request('GET', `/api/session/${id}/inbox`);
    if (name.startsWith('interrupt')) {
      const result = await c.request('POST', `/api/session/${id}/interrupt${name === 'interrupt-resume' ? '?resume=true' : ''}`);
      assert.equal(result.interrupted, true);
    }
  }
  await wait();
  let messages = await snapshot();
  const content = () => messages.flatMap(message => message.content ?? []);
  const tools = () => content().filter(item => item.type === 'tool');
  const hasEvent = type => assert.ok(c.events.some(e => e.type === type), `Missing ${type}`);
  if (name === 'plain-text') {
    assert.ok(content().some(item => item.type === 'text' && item.text === 'Hello, fixture world!'));
    // Explicitly exercise the auxiliary title lane, without a race at scenario reset.
    await c.request('PATCH', `/api/session/${id}`, { title: '' });
    await c.event('session.renamed', event => event.data.title === 'Fixture conversation');
  }
  if (name === 'reasoning-text') {
    assert.ok(content().some(item => item.type === 'reasoning' && item.text === 'Let me think.'));
    hasEvent('session.reasoning.delta');
  }
  if (name === 'read-glob-grep') {
    assert.deepEqual(tools().map(item => item.name), ['read', 'glob', 'grep']);
    assert.ok(tools().every(item => item.state.status === 'completed'), JSON.stringify(tools()));
  }
  if (name.startsWith('permission-')) {
    const edit = tools().find(item => item.name === 'edit');
    assert.equal(edit?.state.status, name === 'permission-allow' ? 'completed' : 'error', JSON.stringify(edit));
    assert.match(await readFile(path.join(c.sandbox.project, 'sample.txt'), 'utf8'), name === 'permission-allow' ? /^edited/ : /^original/);
    hasEvent('permission.replied');
  }
  if (name === 'shell-output') {
    assert.equal(tools().find(item => item.name === 'shell')?.state.status, 'completed');
    const shell = await c.event('shell.created');
    const shellID = shell.data.info?.id ?? shell.data.id;
    assert.ok(shellID, JSON.stringify(shell));
    const output = await c.request('GET', `/api/shell/${shellID}/output`);
    assert.match(JSON.stringify(output), /fixture-shell-output/);
  }
  if (name === 'question-form') {
    assert.equal(tools().find(item => item.name === 'question')?.state.status, 'completed');
    hasEvent('form.replied');
  }
  if (name === 'subagent') {
    assert.equal(tools().find(item => item.name === 'subagent')?.state.status, 'completed', JSON.stringify(tools()));
    const children = (await c.request('GET', `/api/session?parentID=${id}`)).data;
    assert.equal(children.length, 1);
    await snapshot(children[0].id);
  }
  if (name === 'steer-queue') {
    assert.equal(messages.filter(message => message.type === 'user').length, 3);
    assert.ok(content().some(item => item.text === 'Queued turn completed.'));
  }
  if (name.startsWith('interrupt')) {
    hasEvent('session.execution.interrupted');
    if (name === 'interrupt-resume') assert.ok(content().some(item => item.text === 'Resumed steering input.'));
  }
  if (name === 'revert') {
    const messageID = admitted.data.id;
    await c.request('POST', `/api/session/${id}/revert/stage`, { messageID });
    await c.request('GET', `/api/session/${id}`);
    await c.request('DELETE', `/api/session/${id}/revert`); // redo a staged revert
    await snapshot();
    await c.request('POST', `/api/session/${id}/revert/stage`, { messageID });
    await c.request('POST', `/api/session/${id}/revert/commit`);
    assert.equal((await snapshot()).filter(message => message.type === 'user').length, 0);
    await prompt('Redo the reverted turn.');
    await wait(); messages = await snapshot();
    hasEvent('session.revert.committed'); hasEvent('session.revert.cleared');
  }
  if (name === 'fork') {
    const fork = (await c.request('POST', `/api/session/${id}/fork`, {})).data;
    assert.equal(fork.fork.sessionID, id);
    assert.ok((await snapshot(fork.id)).some(message => message.type === 'user'));
    hasEvent('session.forked');
  }
  if (name === 'compaction') {
    await c.request('POST', `/api/session/${id}/compact`, {});
    await wait(); messages = await snapshot();
    assert.ok(messages.some(message => message.type === 'compaction' && message.status === 'completed'), JSON.stringify(messages));
    hasEvent('session.compaction.ended');
  }
  if (name.startsWith('retry-')) {
    hasEvent('session.retry.scheduled');
    assert.ok(content().some(item => item.text?.startsWith('Recovered from')));
  }
  if (name === 'final-error') hasEvent('session.execution.failed');
  else assert.ok(!c.events.some(event => event.type === 'session.execution.failed'), 'Unexpected failed execution');
  await c.request('GET', `/api/session/${id}`);
  await captureSnapshot(c, id, 'end');
  return id;
}

export async function runScenario(sandbox, mock, name, { heartbeat = false, onCapture } = {}) {
  await selectMock(mock, name);
  const c = new Capture(sandbox);
  onCapture?.(c);
  try {
    if (name === 'v1-probe') {
      const health = await c.request('GET', '/global/health', undefined, { status: 200 });
      assert.equal(health.healthy, true); assert.equal(health.version, '1.19.3');
      // V1 serves the web shell at unknown routes; preserve its content type/body.
      await c.request('GET', '/api/info', undefined, { status: 200 });
    } else {
      await c.openSSE();
      if (heartbeat) await until(() => c.comments.includes(': heartbeat'), 'SSE heartbeat within 20 seconds', 20000);
      if (name === 'pairing') await pairing(c);
      else if (name === 'pty') await pty(c);
      else await conversation(c, name);
    }
    await until(() => mock.state().active === 0, 'mock complete');
    assert.equal(mock.state().remaining, 0, `Unconsumed calls in ${name}`);
    assert.deepEqual(mock.state().unexpected, [], `Unexpected calls in ${name}`);
    return { capture: c, mock: structuredClone(mock.state()) };
  } finally { await c.closeSSE(); }
}
