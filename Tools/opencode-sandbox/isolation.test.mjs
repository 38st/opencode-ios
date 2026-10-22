import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, mkdtemp, writeFile, rm, utimes, symlink } from 'node:fs/promises';
import path from 'node:path';
import { snapshot, compare } from './isolation.mjs';
import { repository, resolveVersion } from './index.mjs';
import { launch } from './process.mjs';

test('audit compares exact depth-two mtimes and never follows symlinks', async t => {
  const parent = path.join(repository, '.build/sandbox-tests');
  await mkdir(parent, { recursive: true });
  const root = await mkdtemp(path.join(parent, 'audit-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const config = path.join(root, '.config/opencode');
  await mkdir(path.join(config, 'nested/deeper'), { recursive: true });
  await writeFile(path.join(config, 'nested/file'), 'fixture');
  await symlink('/does-not-exist', path.join(config, 'link'));
  const before = await snapshot(root);
  assert.equal(before[config].length, 5);
  assert.equal(before[path.join(root, '.cache/opencode')], null);
  assert.deepEqual(compare(before, await snapshot(root)), []);
  await utimes(path.join(config, 'nested/file'), 1700000000, 1700000000);
  assert.deepEqual(compare(before, await snapshot(root)).map(row => row.path), [path.join(config, 'nested/file')]);
});

test('version overrides reject ranges, V1, prereleases and command injection', async () => {
  assert.equal(await resolveVersion('2.0.32'), '2.0.32');
  for (const value of ['latest', '^2.0.32', '1.19.3', '2.0.32-beta', '2.0.32; touch bad']) await assert.rejects(resolveVersion(value));
});

test('latest version resolves stable 2.x numerically in one registry request', async t => {
  const original = globalThis.fetch;
  t.after(() => { globalThis.fetch = original; });
  let requests = 0;
  globalThis.fetch = async () => { requests++; return { ok: true, json: async () => ({ versions: { '2.0.9': {}, '2.0.32': {}, '2.0.33-beta': {}, '3.0.0': {}, '1.19.3': {} } }) }; };
  assert.equal(await resolveVersion(), '2.0.32');
  assert.equal(requests, 1);
});

test('cleanup terminates the process group and a descendant with its own group', async t => {
  const group = launch(process.execPath, ['-e', `const {spawn}=require('node:child_process'); const child=spawn(process.execPath,['-e','setInterval(()=>{},1000)'],{detached:true,stdio:'ignore'}); console.log(child.pid); setInterval(()=>{},1000);`], { env: { PATH: '/usr/bin:/bin' } });
  t.after(() => group.stop());
  for (let i = 0; i < 100 && !group.output.trim(); i++) await new Promise(resolve => setTimeout(resolve, 10));
  const child = Number(group.output.trim());
  assert.ok(child > 0);
  await group.stop();
  assert.throws(() => process.kill(-group.child.pid, 0), { code: 'ESRCH' });
  assert.throws(() => process.kill(-child, 0), { code: 'ESRCH' });
});

// Never attempt a write to the user's real protected paths in a test.
test('sandbox-exec denies writes in every protected root, including descendants', async t => {
  const { sandboxCommand, protectedRoots } = await import('./profile.mjs');
  const { run } = await import('./process.mjs');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/enforce-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const protectedRoot of protectedRoots(root)) {
    await mkdir(protectedRoot, { recursive: true });
    const invocation = await sandboxCommand(process.execPath, ['-e',
      'require("node:fs").writeFileSync(process.argv[1], "forbidden")', path.join(protectedRoot, 'denied')], root);
    await assert.rejects(run(invocation.command, invocation.args), /EPERM|Operation not permitted/);
  }
  const invocation = await sandboxCommand(process.execPath, ['-e',
    'require("node:fs").writeFileSync(process.argv[1], "allowed")', path.join(root, 'allowed')], root);
  await run(invocation.command, invocation.args);
});

test('attribution requires a unique writable process and fails closed', async () => {
  const { parseLsof, attribute } = await import('./attribution.mjs');
  const files = parseLsof('p20\ng10\ncOpenCode\nf3\nau\nn/test/opencode.db\n');
  const change = { path: '/test/opencode.db' };
  assert.equal(attribute(change, files, new Set()).severity, 'warning');
  assert.equal(attribute(change, files, new Set([10])).attribution, 'sandbox');
  assert.equal(attribute(change, [], new Set()).severity, 'failure');
  assert.equal(attribute(change, [], new Set(), true).severity, 'warning');
  assert.equal(attribute(change, files, new Set([10]), true).severity, 'failure');
  assert.equal(attribute(change, [...files, { ...files[0], pid: 30 }], new Set()).attribution, 'unknown');
});

test('audit attributes an external live writer with lsof and change time', async t => {
  const { readFile } = await import('node:fs/promises');
  const { audit } = await import('./isolation.mjs');
  const { setTimeout: delay } = await import('node:timers/promises');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/attribute-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const enforced = await verifiedChild(root);
  t.after(() => enforced.stop());
  const dir = path.join(root, '.local/share/opencode');
  await mkdir(dir, { recursive: true });
  const file = path.join(dir, 'opencode.db');
  await writeFile(file, 'before');
  // The external writer is deliberately outside sandboxGroups and keeps the
  // writable descriptor open so the before/after sample can identify it.
  const writer = launch(process.execPath, ['-e', `
    const fs = require('node:fs'); const fd = fs.openSync(process.argv[1], 'r+');
    console.log('ready'); setTimeout(() => fs.writeSync(fd, 'after!'), 1200);
    setInterval(() => {}, 1000);
  `, file]);
  t.after(() => writer.stop());
  while (!writer.output.includes('ready')) { writer.check(); await delay(10); }
  const directory = path.join(root, 'report');
  await audit(directory, () => delay(1800), { home: root });
  const result = JSON.parse(await readFile(path.join(directory, 'comparison.json'), 'utf8'));
  assert.equal(result.unchanged, false);
  assert.equal(result.failures, 0);
  assert.equal(result.observations[0].attribution, 'external');
  assert.equal(result.observations[0].writers[0].pid, writer.child.pid);
  assert.ok(result.observations[0].changeTime);
  assert.ok(result.observations[0].writers[0].name);
  assert.equal(result.enforcement.verified, true);
});

async function verifiedChild(root) {
  const { verifiedSandboxCommand } = await import('./profile.mjs');
  const invocation = await verifiedSandboxCommand(process.execPath, ['-e', 'setInterval(()=>{},1000)'], root, root);
  const group = launch(invocation.command, invocation.args, { sandboxed: true, enforcement: invocation.enforcement });
  try {
    for (let i = 0; i < 100; i++) {
      group.check();
      if (await group.verifyEnforcement()) return group;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    throw new Error('Enforcement verification timed out');
  } catch (error) { await group.stop(); throw error; }
}

test('a server cannot launch without enforced bootstrap verification', () => {
  assert.throws(() => launch(process.execPath, ['-e', 'process.exit()'], { sandboxed: true }), /enforcement is required/);
});

test('enforcement retries incomplete receipts and still rejects mismatched complete proofs', async t => {
  const { readFile } = await import('node:fs/promises');
  const { verifiedSandboxCommand } = await import('./profile.mjs');
  const { enforcementReport } = await import('./process.mjs');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/receipt-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const invocation = await verifiedSandboxCommand(process.execPath, ['-e', 'console.log("ready");setInterval(()=>{},1000)'], root, root);
  // Read a controlled copy of an actual sandbox proof to reproduce each point
  // in a partial write without relying on scheduler timing.
  const receipt = path.join(root, 'observed-receipt.json');
  const group = launch(invocation.command, invocation.args, { sandboxed: true, enforcement: { ...invocation.enforcement, receipt } });
  t.after(() => group.stop());
  for (let i = 0; i < 100 && !group.output.includes('ready'); i++) {
    group.check(); await new Promise(resolve => setTimeout(resolve, 20));
  }
  assert.ok(group.output.includes('ready'));
  const proof = JSON.parse(await readFile(invocation.enforcement.receipt, 'utf8'));
  assert.equal(await group.verifyEnforcement(), false);
  for (const partial of ['', '{', '{"pid":', '{invalid json}']) {
    await writeFile(receipt, partial);
    assert.equal(await group.verifyEnforcement(), false);
    assert.equal(enforcementReport().launches.find(item => item.pid === group.child.pid).verified, false);
  }
  for (const mismatch of [null, { ...proof, pid: -1 }, { ...proof, token: 'wrong' },
    { ...proof, profileDigest: 'wrong' }, { ...proof, deniedWrite: false }, { ...proof, protectedRoots: [] }]) {
    await writeFile(receipt, JSON.stringify(mismatch));
    await assert.rejects(group.verifyEnforcement(), /receipt is invalid/);
  }
  await writeFile(receipt, JSON.stringify(proof));
  assert.equal(await group.verifyEnforcement(), true);
});

test('failed denied-write check prevents the target process from starting', async t => {
  const { readFile, access } = await import('node:fs/promises');
  const { run } = await import('./process.mjs');
  const { verifiedSandboxCommand } = await import('./profile.mjs');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/unenforced-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const marker = path.join(root, 'target-started');
  const invocation = await verifiedSandboxCommand(process.execPath, ['-e', 'require("node:fs").writeFileSync(process.argv[1], "started")', marker], root, root);
  // Deliberately omit sandbox-exec, so the canary succeeds and bootstrap must refuse npx.
  await assert.rejects(run(invocation.args[2], invocation.args.slice(3)), /denied-write check failed/);
  await assert.rejects(access(marker), { code: 'ENOENT' });
  await assert.rejects(readFile(invocation.enforcement.receipt), { code: 'ENOENT' });
});

test('verified enforcement allows unattributed external changes as warnings', async t => {
  const { readFile } = await import('node:fs/promises');
  const { audit } = await import('./isolation.mjs');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/unknown-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const group = await verifiedChild(root);
  t.after(() => group.stop());
  const cache = path.join(root, '.cache/opencode');
  await mkdir(cache, { recursive: true });
  const file = path.join(cache, 'models.json');
  await writeFile(file, '{}');
  await audit(path.join(root, 'report'), () => writeFile(file, '{"external":true}'), { home: root });
  const report = JSON.parse(await readFile(path.join(root, 'report/comparison.json'), 'utf8'));
  assert.equal(report.failures, 0);
  assert.equal(report.enforcement.verified, true);
  assert.equal(report.observations[0].attribution, 'unknown');
  assert.equal(report.observations[0].severity, 'warning');
});

test('optional marker isolation hides existence as well as reads without hiding fixture files', async t => {
  const { verifiedSandboxCommand } = await import('./profile.mjs');
  const { run } = await import('./process.mjs');
  const root = await mkdtemp(path.join(repository, '.build/sandbox-tests/markers-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const marker = path.join(root, '.git'), own = path.join(root, 'fixture.txt');
  await mkdir(marker); await writeFile(own, 'fixture');
  const script = 'const fs=require("node:fs");console.log(JSON.stringify({marker:fs.existsSync(process.argv[1]),text:fs.readFileSync(process.argv[2],"utf8")}))';
  const invocation = await verifiedSandboxCommand(process.execPath, ['-e', script, marker, own], root, root, [marker]);
  assert.deepEqual(JSON.parse(await run(invocation.command, invocation.args)), { marker: false, text: 'fixture' });
});
