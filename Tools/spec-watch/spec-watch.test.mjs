import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { appEventTypes, eventDiff, issueBody, issueTitle, newerVersions, parseOasdiff, summarizeOpenAPI, summaryIsEmpty } from './diff.mjs';
import { ensureIssue, LABEL } from './github.mjs';

const fixture = name => readFile(new URL(`fixtures/${name}`, import.meta.url), 'utf8');
const json = async name => JSON.parse(await fixture(name));

test('newer versions are stable 2.x releases after the baseline, oldest first', () => {
  const registry = { versions: { '2.0.31': {}, '2.0.32': {}, '2.0.40': {}, '2.0.33': {}, '2.1.0-beta.1': {}, '1.19.3': {}, '2.0.100': {} } };
  assert.deepEqual(newerVersions(registry, '2.0.32'), ['2.0.33', '2.0.40', '2.0.100']);
  assert.deepEqual(newerVersions(registry, '2.0.100'), []);
  assert.deepEqual(newerVersions({}, '2.0.32'), []);
});

test('the structural summary lists added, removed and changed operations and schemas', async () => {
  const summary = summarizeOpenAPI(await json('base.json'), await json('next.json'));
  assert.deepEqual(summary, {
    addedOperations: ['PUT /api/session/{sessionID}/goal'],
    removedOperations: ['POST /api/session/{sessionID}/share'],
    changedOperations: ['GET /api/session'],
    addedSchemas: ['Goal'],
    removedSchemas: ['Share'],
    changedSchemas: ['ServerInfo'],
  });
  const base = await json('base.json');
  assert.ok(summaryIsEmpty(summarizeOpenAPI(base, structuredClone(base))));
});

test('oasdiff changelog output keeps breaking changes apart', async () => {
  const entries = parseOasdiff(await fixture('oasdiff-changelog.json'));
  assert.deepEqual(entries.filter(entry => entry.breaking).map(entry => entry.operation), ['POST /api/session/{sessionID}/share', 'GET /api/session']);
  assert.equal(entries.length, 3);
  assert.deepEqual(parseOasdiff(''), []);
  assert.throws(() => parseOasdiff('{}'), /not a list/);
});

test('the event diff compares the upstream union with the app decoder', async () => {
  const known = appEventTypes(await fixture('ServerEvent.swift'));
  assert.deepEqual(known, ['session.created', 'session.shared']);
  assert.deepEqual(eventDiff(await fixture('types.ts'), known), { upstream: 2, added: ['session.goal.set'], removed: ['session.shared'] });
  assert.throws(() => appEventTypes('struct Nothing {}'), /knownTypes/);
});

test('the issue text names what changed upstream', async () => {
  const body = issueBody({
    version: '2.0.40', baseline: '2.0.32', newer: ['2.0.33', '2.0.40'],
    summary: summarizeOpenAPI(await json('base.json'), await json('next.json')),
    oasdiff: parseOasdiff(await fixture('oasdiff-changelog.json')),
    events: { upstream: 2, added: ['session.goal.set'], removed: ['session.shared'] },
  });
  assert.equal(issueTitle('2.0.40'), 'opencode 2.0.40: server changes to check');
  assert.match(body, /oasdiff reports 3 changes, 2 breaking/);
  assert.match(body, /`POST \/api\/session\/\{sessionID\}\/share`: api removed without deprecation/);
  assert.match(body, /Releases since then: 2\.0\.33, 2\.0\.40/);
  assert.match(body, /- `session\.goal\.set`/);
  assert.doesNotMatch(body, /\n\n\n/);
  for (const internal of ['Tools/', '.build', 'Fixtures/', 'Packages/']) assert.ok(!body.includes(internal), internal);
  const without = issueBody({ version: '2.0.40', baseline: '2.0.32', newer: ['2.0.40'], summary: summarizeOpenAPI(await json('base.json'), await json('base.json')), events: undefined });
  assert.match(without, /oasdiff was not run/);
  assert.match(without, /could not be read/);
});

function fakeGitHub(open = []) {
  const calls = [];
  const fetch = async (url, init = {}) => {
    calls.push({ url, method: init.method ?? 'GET', headers: init.headers, body: init.body && JSON.parse(init.body) });
    if ((init.method ?? 'GET') === 'GET') return new Response(JSON.stringify(open), { status: 200 });
    return new Response(JSON.stringify({ number: 7, html_url: 'https://github.com/o/r/issues/7' }), { status: 201 });
  };
  return { calls, fetch };
}

test('an issue is opened once per title, with the workflow token', async () => {
  const github = fakeGitHub([{ number: 3, title: 'something else', html_url: 'x' }, { number: 4, title: 'opencode 2.0.40: server changes to check', html_url: 'y', pull_request: {} }]);
  const result = await ensureIssue({ repository: 'o/r', token: 't0k', title: 'opencode 2.0.40: server changes to check', body: 'b', fetch: github.fetch });
  assert.deepEqual(result, { created: true, number: 7, url: 'https://github.com/o/r/issues/7' });
  assert.equal(github.calls[1].method, 'POST');
  assert.deepEqual(github.calls[1].body, { title: 'opencode 2.0.40: server changes to check', body: 'b', labels: [LABEL] });
  assert.equal(github.calls[0].headers.authorization, 'Bearer t0k');

  const again = fakeGitHub([{ number: 9, title: 'opencode 2.0.40: server changes to check', html_url: 'z' }]);
  assert.deepEqual(await ensureIssue({ repository: 'o/r', token: 't', title: 'opencode 2.0.40: server changes to check', body: 'b', fetch: again.fetch }), { created: false, number: 9, url: 'z' });
  assert.equal(again.calls.length, 1);

  await assert.rejects(ensureIssue({ repository: 'o/r', token: '', title: 't', body: 'b', fetch: again.fetch }), /GITHUB_TOKEN/);
  await assert.rejects(ensureIssue({ repository: 'nope', token: 't', title: 't', body: 'b', fetch: again.fetch }), /owner\/name/);
});
