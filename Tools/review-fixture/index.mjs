import assert from 'node:assert/strict';
import path from 'node:path';
import { mkdir, writeFile, rm, copyFile } from 'node:fs/promises';
import { setTimeout as delay } from 'node:timers/promises';
import { run } from '../opencode-sandbox/process.mjs';
import { Capture, until } from '../fixture-recorder/transport.mjs';
import { fileURLToPath } from 'node:url';

// Native discovery walks filesystem markers independently of Git's ceiling.
// Hide only the enclosing checkout's markers from this sandbox process tree.
export function configureReview(_config, dirs, env) {
  env.GIT_CEILING_DIRECTORIES = path.dirname(dirs.project);
  const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  return { deniedReads: [path.join(repository, '.git'), path.join(repository, '.hg')] };
}

export const largeSource = (changed = false) => Array.from({ length: 5000 }, (_, i) => `let value${i + 1} = ${i + 1 + Number(changed)}\n`).join('');

// All three harnesses call this helper. It never changes the sandbox's existing project or fixtures.
export async function seedReviewRepository(server, mock) {
  const directory = path.join(server.root, 'review-project');
  const noGit = path.join(server.root, 'review-no-git');
  assert.ok(directory.startsWith(server.root + path.sep));
  await mkdir(path.join(directory, 'Sources'), { recursive: true });
  await mkdir(path.join(directory, 'src'), { recursive: true });
  await mkdir(noGit, { recursive: true });
  const git = args => run('/usr/bin/git', args, { cwd: directory, env: server.env });
  await git(['init', '--quiet', '--initial-branch=main']);
  const base = {
    'Sources/Example.swift': 'struct Example {\n    let value = 1\n    let title = "Original"\n}\n',
    'src/example.ts': 'export const value = 1;\nexport const title = "Original";\n',
    'data.json': '{\n  "enabled": false\n}\n',
    'README.md': '# Review fixture\n\nA file with **Markdown**.\n',
    'removed.txt': 'Remove this tracked file.\n',
    'deleted-by-turn.txt': 'Delete through the scripted tool.\n',
    'Large.swift': largeSource(),
    '.hidden': 'Dotfiles remain visible.\n',
  };
  for (const [name, text] of Object.entries(base)) await writeFile(path.join(directory, name), text);
  await copyFile(fileURLToPath(new URL('../../Fixtures/source/review/image.png', import.meta.url)), path.join(directory, 'image.png'));
  await writeFile(path.join(directory, 'binary.bin'), Buffer.from([0, 1, 2, 3, 4]));
  await git(['add', '.']);
  await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Review base']);
  await git(['switch', '--quiet', '-c', 'feature']);
  await writeFile(path.join(directory, 'README.md'), '# Review fixture\n\nCommitted on feature.\n');
  await git(['add', 'README.md']);
  await git(['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Feature change']);
  await writeFile(path.join(directory, 'data.json'), '{\n  "enabled": true\n}\n');
  await writeFile(path.join(directory, 'added.txt'), 'Uncommitted added file.\n');
  await rm(path.join(directory, 'removed.txt'));
  await writeFile(path.join(noGit, 'hello.txt'), 'No repository yet.\n');
  const api = new Capture(server);
  const resolved = await api.request('GET', '/api/location?' + new URLSearchParams({ 'location[directory]': noGit }));
  assert.equal(resolved.project.directory, noGit, 'No-Git fixture must never resolve to the outer repository');
  const session = async (title, root = directory) => (await api.request('POST', '/api/session', {
    title, location: { directory: root }, model: { providerID: 'mock', id: 'mock-1' },
  })).data.id;
  const edit = await session('Review sample edits');
  const large = await session('Review sample large diff');
  const noGitSession = await session('Review sample without Git', noGit);
  const turn = async (id, name, calls) => {
    await until(async () => (await fetch(mock.url + '/admin/state').then(r => r.json())).active === 0, 'mock idle');
    const response = await fetch(mock.url + '/admin/scenario', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name, script: { calls } }) });
    assert.equal(response.status, 200);
    const admission = (await api.request('POST', `/api/session/${id}/prompt`, { text: name })).data;
    let finished = false, failure;
    const waiting = api.request('POST', `/api/experimental/session/${id}/wait`).then(() => { finished = true; }, error => { failure = error; finished = true; });
    while (!finished) {
      for (const request of (await api.request('GET', `/api/session/${id}/permission`)).data) {
        await api.request('POST', `/api/session/${id}/permission/${request.id}/reply`, { decision: 'once' });
      }
      await delay(50);
    }
    await waiting; if (failure) throw failure;
    const messages = (await api.request('GET', `/api/session/${id}/message?limit=200&order=asc`)).data;
    const tools = messages.flatMap(m => m.content ?? []).filter(c => c.type === 'tool');
    assert.ok(tools.every(t => t.state.status === 'completed'), JSON.stringify(tools.map(t => ({ name: t.name, state: t.state.status, error: t.state.error }))));
    return admission.id;
  };
  const tool = (name, args) => ({ tools: [{ name, arguments: args }] });
  const from = await turn(edit, 'Review a small edit', [
    tool('read', { path: 'Sources/Example.swift' }),
    tool('edit', { path: 'Sources/Example.swift', oldString: 'let value = 1', newString: 'let value = 2' }),
    tool('write', { path: 'src/created.ts', content: 'export const created = true;\n' }),
    tool('shell', { command: 'rm -- deleted-by-turn.txt' }),
    { deltas: [{ text: 'Review [Example.swift](Sources/Example.swift:2-3) and `Sources/Example.swift:2`.' }] },
  ]);
  const largeFrom = await turn(large, 'Rewrite the 5000-line source', [
    tool('read', { path: 'Large.swift', limit: 2000 }),
    tool('write', { path: 'Large.swift', content: largeSource(true) }),
    { deltas: [{ text: 'Updated every value in [Large.swift](Large.swift:1).' }] },
  ]);
  const navigationSession = (await api.request('POST', `/api/session/${edit}/fork`, {})).data.id;
  return { directory, noGit, session: edit, from, navigationSession, largeSession: large, largeFrom, noGitSession };
}
