import assert from 'node:assert/strict';
import { seedReviewRepository, configureReview } from '../review-fixture/index.mjs';
import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { repository, resolveVersion, startSandbox, V1_VERSION } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { stopAll, run } from '../opencode-sandbox/process.mjs';
import { startMock } from '../mock-llm/server.mjs';
import { runScenario } from '../fixture-recorder/scenarios.mjs';
import { runPluginChecks } from '../push-e2e/plugin-checks.mjs';

const { values } = parseArgs({ options: { version: { type: 'string' }, 'write-flows-only': { type: 'boolean' } } });
const version = await resolveVersion(values.version);
const auditDir = path.join(repository, '.build/opencode-sandbox/audits', `contract-${Date.now()}`);
await audit(auditDir, async () => {
  const mock = await startMock();
  let server, v1;
  try {
    console.log(`Contract V2 ${version}, V1 ${V1_VERSION}; audit ${auditDir}`);
    server = await startSandbox({ version, mockURL: mock.url, configure: configureReview });
    const worktreeDirectory = path.join(server.root, 'worktree-project');
    await mkdir(worktreeDirectory);
    await writeFile(path.join(worktreeDirectory, 'README.md'), 'M3b worktree contract fixture\n');
    await run('/usr/bin/git', ['init', '--quiet', worktreeDirectory], { env: server.env, cwd: server.root });
    await run('/usr/bin/git', ['add', 'README.md'], { env: server.env, cwd: worktreeDirectory });
    await run('/usr/bin/git', ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Fixture'], { env: server.env, cwd: worktreeDirectory });
    const paired = await runScenario(server, mock, 'pairing', { heartbeat: true });
    assert.equal(paired.capture.events[0].type, 'server.connected');
    console.log('PASS auth, single-use pairing, SSE first frame and heartbeat within 20 seconds');
    await runScenario(server, mock, 'plain-text');
    console.log('PASS prompt round trip and auxiliary title');
    const reasoning = await runScenario(server, mock, 'reasoning-text');
    await writeFile(path.join(auditDir, 'reasoning-wire.json'), JSON.stringify({
      events: reasoning.capture.events.filter(event => event.type.startsWith('session.reasoning.')),
      snapshots: reasoning.capture.rest.filter(entry => entry.request.path.includes('/message')).map(entry => entry.response.body),
    }, null, 2) + '\n');
    console.log('PASS reasoning stream and snapshot capture');
    await runScenario(server, mock, 'pty');
    console.log('PASS PTY echo, resize, binary marker, cursor resume and deletion');
    v1 = await startSandbox({ version: V1_VERSION, v1: true, mockURL: mock.url });
    await runScenario(v1, mock, 'v1-probe');
    console.log('PASS V1 detection');
    const review = await seedReviewRepository(server, mock);
    // Swift receives only sandbox coordinates. The PID comes from authenticated
    // /api/info, not npx's wrapper, so SIGSTOP targets the actual server.
    const swift = await run('/usr/bin/xcrun', ['swift', 'test', '--package-path', 'Packages/OpencodeKit',
      '--filter', values['write-flows-only'] ? 'sandboxWritePaths' : 'OCNetworkingLiveTests'], { cwd: repository, env: {
        ...process.env,
        OPENCODE_LIVE_REVIEW: JSON.stringify(review),
        OPENCODE_LIVE_URL: server.baseURL,
        OPENCODE_LIVE_MOCK_URL: mock.url,
        OPENCODE_LIVE_DIRECTORY: server.project,
        OPENCODE_LIVE_WORKTREE_DIRECTORY: worktreeDirectory,
        OPENCODE_LIVE_PASSWORD: server.password,
        OPENCODE_LIVE_PID: String(server.info.pid),
        OPENCODE_LIVE_VERSION: version,
        OPENCODE_LIVE_V1_URL: v1.baseURL,
        OPENCODE_LIVE_V1_PASSWORD: v1.password,
      } });
    console.log(swift);
    assert.match(swift, /PASS M3a store projection equals snapshot: compact/, 'Swift write contracts must run through compact');
    console.log('PASS Swift networking, projection and M3a write contracts');
    // The push plugin in its own sandboxes: installed by configuration and by `opencode plugin add`.
    const push = await runPluginChecks({ version, mock });
    await writeFile(path.join(auditDir, 'push-plugin.json'), JSON.stringify(push, null, 2) + '\n');
    console.log('PASS push plugin live checks');
  } finally {
    try { await v1?.stop(); await server?.stop(); }
    finally { await stopAll(); await mock.close(); }
  }
});
console.log('PASS process cleanup and isolation audit');
