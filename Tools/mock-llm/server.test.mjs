import { test } from 'node:test';
import assert from 'node:assert/strict';
import { startMock } from './server.mjs';

async function fixture(t) {
  const mock = await startMock();
  t.after(() => mock.close());
  const post = (route, body) => fetch(mock.url + route, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) });
  return { mock, select: (name, script) => post('/admin/scenario', { name, script }), call: (body = {}) => post('/v1/chat/completions', { model: 'mock-1', stream: true, messages: [{ role: 'user', content: 'fixture' }], ...body }) };
}

test('chat chunks carry reasoning, text, finish and usage, ending in DONE', async t => {
  const f = await fixture(t);
  await f.select('reasoning-text');
  const response = await f.call();
  assert.match(response.headers.get('content-type'), /text\/event-stream/);
  const wire = await response.text();
  const frames = wire.trim().split('\n\n').map(line => line.slice(6));
  assert.equal(frames.pop(), '[DONE]');
  const chunks = frames.map(JSON.parse);
  assert.equal(chunks[1].choices[0].delta.reasoning_content, 'Let me think.');
  assert.equal(chunks[2].choices[0].delta.content, 'The answer is 42.');
  assert.equal(chunks.at(-2).choices[0].finish_reason, 'stop');
  assert.equal(chunks.at(-1).usage.total_tokens, 36);
  assert.equal(f.mock.state().remaining, 0);
});

test('tool-call arguments stream in fragments, with stable index and id', async t => {
  const f = await fixture(t);
  await f.select('custom', { calls: [{ tools: [{ name: 'read', arguments: { path: 'sample.txt' } }] }] });
  const frames = (await (await f.call()).text()).trim().split('\n\n').slice(0, -1).map(line => JSON.parse(line.slice(6)));
  const deltas = frames.flatMap(frame => frame.choices.flatMap(choice => choice.delta.tool_calls ?? []));
  assert.match(deltas[0].id, /^call_/);
  assert.equal(deltas[0].function.name, 'read');
  assert.ok(deltas.every(delta => delta.index === 0));
  assert.deepEqual(JSON.parse(deltas.map(delta => delta.function.arguments).join('')), { path: 'sample.txt' });
  assert.ok(frames.some(frame => frame.choices[0]?.finish_reason === 'tool_calls'));
});

test('auxiliary calls do not consume the primary script; exhaustion fails closed', async t => {
  const f = await fixture(t);
  const title = await f.call({ stream: false, messages: [{ role: 'system', content: 'You are a title generator.' }] });
  assert.equal((await title.json()).choices[0].message.content, 'Fixture conversation');
  assert.equal(f.mock.state().remaining, 1);
  const compact = await f.call({ stream: false, messages: [{ role: 'user', content: 'Return a structured summary' }] });
  assert.match((await compact.json()).choices[0].message.content, /## Objective/);
  const summary = await f.call({ stream: false, messages: [{ role: 'system', content: 'Write a summary' }] });
  assert.equal((await summary.json()).choices[0].message.content, 'Deterministic conversation summary.');
  await (await f.call()).text();
  assert.equal((await f.call()).status, 400);
  assert.equal(f.mock.state().unexpected.length, 1);
  assert.deepEqual(f.mock.state().consumed.map(call => call.kind), ['title', 'compaction', 'summary', 'primary']);
});

test('title requests are recognised in the 2.1.2 and the 2.1.3 wording, by their system prompt', async t => {
  const f = await fixture(t);
  // Up to 2.1.2: the old system prompt, and the first message as it was.
  const before = { role: 'system', content: 'You are a title generator. You output ONLY a thread title. Nothing else.' };
  // From 2.1.3 (upstream d2812d147): a new system prompt, and the input framed as a message or a conversation.
  const after = { role: 'system', content: 'You name conversations so the user can find them later in a list of past sessions.\n\nYou will receive the first message of a conversation.' };
  const message = 'Here is the first message of the conversation:\n\n<message>\nRun the fixture.\n</message>\n\nReply with only the title.';
  const conversation = 'Here is the conversation so far:\n\n<conversation>\nOriginal request:\nRun the fixture.\n\nRecent conversation:\nAssistant: Done.\n</conversation>\n\nReply with only the title.';
  for (const messages of [[before, { role: 'user', content: 'Run the fixture.' }], [after, { role: 'user', content: message }], [after, { role: 'user', content: conversation }]]) {
    const response = await f.call({ stream: false, messages });
    assert.equal((await response.json()).choices[0].message.content, 'Fixture conversation');
  }
  assert.equal(f.mock.state().remaining, 1, 'A title request consumed a scripted turn');
  // The user-side wording alone is not a title request: it takes the scripted turn.
  await (await f.call({ stream: false, messages: [{ role: 'system', content: 'You are an AI agent running in OpenCode.' }, { role: 'user', content: message }] })).text();
  assert.deepEqual(f.mock.state().consumed.map(call => call.kind), ['title', 'title', 'title', 'primary']);
});

test('429 and 500 responses consume one step, then a successful retry', async t => {
  const f = await fixture(t);
  for (const status of [429, 500]) {
    await f.select(`retry-${status}`);
    const failed = await f.call();
    assert.equal(failed.status, status);
    assert.equal(failed.headers.get('retry-after'), '0');
    assert.ok((await failed.json()).error.message);
    assert.match(await (await f.call()).text(), new RegExp(`Recovered from ${status}`));
    assert.equal(f.mock.state().remaining, 0);
  }
});

test('delays are cancellable and scenario changes reject active calls', async t => {
  const f = await fixture(t);
  await f.select('interrupt');
  const controller = new AbortController();
  const response = await fetch(f.mock.url + '/v1/chat/completions', { method: 'POST', signal: controller.signal, body: JSON.stringify({ model: 'mock-1', stream: true, messages: [] }) });
  assert.equal((await f.select('plain-text')).status, 409);
  controller.abort();
  await assert.rejects(response.text());
  for (let i = 0; i < 50 && f.mock.state().active; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(f.mock.state().active, 0);
  assert.equal(f.mock.state().consumed[0].status, 'cancelled');
});

test('a held stream stays active until the client interrupts it', async t => {
  const f = await fixture(t);
  await f.select('held', { calls: [{ deltas: [{ text: 'Waiting for Stop.' }], waitForAbort: true }] });
  const controller = new AbortController();
  const response = await fetch(f.mock.url + '/v1/chat/completions', { method: 'POST', signal: controller.signal,
    body: JSON.stringify({ model: 'mock-1', stream: true, messages: [] }) });
  const reader = response.body.getReader();
  let wire = '';
  while (!wire.includes('Waiting for Stop.')) {
    const chunk = await reader.read();
    assert.equal(chunk.done, false);
    wire += new TextDecoder().decode(chunk.value);
  }
  assert.equal(f.mock.state().active, 1);
  assert.ok(!wire.includes('[DONE]'));
  controller.abort();
  await assert.rejects(reader.read());
  for (let i = 0; i < 50 && f.mock.state().active; i++) await new Promise(resolve => setTimeout(resolve, 10));
  assert.equal(f.mock.state().active, 0);
  assert.equal(f.mock.state().consumed[0].status, 'cancelled');
});
