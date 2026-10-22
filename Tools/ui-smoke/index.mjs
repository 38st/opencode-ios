import assert from 'node:assert/strict';
import { seedReviewRepository, configureReview } from '../review-fixture/index.mjs';
import { assertEditorCoverage } from './editor-coverage.mjs';
import { startFaultProxy } from './fault-proxy.mjs';
import { configureComposer } from './composer-config.mjs';
import { seedReadScreens } from './read-screens.mjs';
import path from 'node:path';
import { mkdir, writeFile, readFile, copyFile } from 'node:fs/promises';
import { parseArgs, promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { repository, resolveVersion, startSandbox, V1_VERSION } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { stopAll, run } from '../opencode-sandbox/process.mjs';
import { startMock } from '../mock-llm/server.mjs';

const { values } = parseArgs({ options: { version: { type: 'string' }, 'skip-snapshots': { type: 'boolean' }, 'review-only': { type: 'boolean' }, 'review-test': { type: 'string' }, 'ipad-only': { type: 'boolean' }, 'read-flows-only': { type: 'boolean' }, 'composer-only': { type: 'boolean' }, 'worktree-only': { type: 'boolean' }, 'composer-test': { type: 'string' } } });
const reviewTest = values['review-test'];
if (reviewTest) assert.ok(['testReviewAndFiles', 'testLargeDiffScroll', 'testReviewNavigation'].includes(reviewTest), 'Unknown review test');
const reviewOnly = values['review-only'] || Boolean(reviewTest);
const reviewScreens = (ipad = false) => [
  ...(!reviewTest || reviewTest === 'testReviewAndFiles' ? ['review-changes', 'review-comment', 'review-files', ...(ipad ? [] : ['review-created-git'])] : []),
  ...(!reviewTest || reviewTest === 'testReviewNavigation' ? ['review-turn-navigation', 'review-reviewed', 'review-file-tree', 'review-file-link'] : []),
  ...(!reviewTest || reviewTest === 'testLargeDiffScroll' ? (ipad ? ['review-large-split-nowrap', 'review-large-split'] : ['review-large-unified']) : []),
].map(name => (ipad ? 'ipad-' : '') + name);
const composerTest = values['composer-test'] ?? (values['worktree-only'] ? 'testInterruptAndNewWorktree' : undefined);
if (composerTest) assert.ok(['testComposerDurabilityAndSends', 'testComposerQueueAndSessionActions', 'testInterruptAndNewWorktree'].includes(composerTest), 'Unknown composer test');
const composerOnly = values['composer-only'] || Boolean(composerTest);
const version = await resolveVersion(values.version);
const runID = `ui-${Date.now()}`;
const output = path.join(repository, '.build/ui-smoke', runID);
await mkdir(output, { recursive: true });
await run('xcodegen', ['generate'], { cwd: repository });
const inventory = JSON.parse(await run('/usr/bin/xcrun', ['simctl', 'list', 'devices', 'available', '--json']));
const devices = Object.values(inventory.devices).flat();
const device = devices.find(device => device.name === 'iPhone 17 Pro' && device.state === 'Booted')
  ?? devices.find(device => device.name === 'iPhone 17 Pro');
assert.ok(device, 'The existing iPhone 17 Pro simulator is required');
const ipad = devices.find(device => device.name === 'opencode-ios iPad');
const destination = `platform=iOS Simulator,id=${values['ipad-only'] ? (assert.ok(ipad), ipad.udid) : device.udid}`;
await audit(path.join(repository, '.build/opencode-sandbox/audits', runID), async () => {
  const mock = await startMock();
  let server, v1, proxy;
  try {
    server = await startSandbox({ version, mockURL: mock.url, configure: async (config, dirs, env) => { await configureComposer(config, dirs, env); return configureReview(config, dirs, env); } });
    const worktreeDirectory = path.join(server.root, 'composer-worktree-project');
    await mkdir(worktreeDirectory);
    await writeFile(path.join(worktreeDirectory, 'README.md'), 'Composer worktree UI fixture\n');
    await run('/usr/bin/git', ['init', '--quiet', worktreeDirectory], { env: server.env, cwd: server.root });
    await run('/usr/bin/git', ['add', 'README.md'], { env: server.env, cwd: worktreeDirectory });
    await run('/usr/bin/git', ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--quiet', '-m', 'Fixture'], { env: server.env, cwd: worktreeDirectory });
    v1 = await startSandbox({ version: V1_VERSION, v1: true, mockURL: mock.url });
    const screens = await seedReadScreens(server, mock);
    const review = await seedReviewRepository(server, mock);
    proxy = await startFaultProxy(server.baseURL);
    const result = path.join(output, 'Smoke.xcresult');
    const environment = {
      ...process.env,
      TEST_RUNNER_OPENCODE_UI_REVIEW: JSON.stringify(review),
      TEST_RUNNER_OPENCODE_UI_READ_SCREENS: JSON.stringify(screens),
      TEST_RUNNER_OPENCODE_UI_MOCK_URL: mock.url,
      TEST_RUNNER_OPENCODE_UI_DIRECTORY: server.project,
      TEST_RUNNER_OPENCODE_UI_WORKTREE_DIRECTORY: worktreeDirectory,
      TEST_RUNNER_OPENCODE_UI_URL: server.baseURL,
      TEST_RUNNER_OPENCODE_UI_PROXY_URL: proxy.url,
      TEST_RUNNER_OPENCODE_UI_PROXY_TOKEN: proxy.adminToken,
      TEST_RUNNER_OPENCODE_UI_PASSWORD: server.password,
      TEST_RUNNER_OPENCODE_UI_V1_URL: v1.baseURL,
      TEST_RUNNER_OPENCODE_UI_V1_PASSWORD: v1.password,
      TEST_RUNNER_OPENCODE_UI_TEST_ID: runID,
    };
    let log;
    try {
      log = await run('/usr/bin/xcodebuild', ['-project', 'Opencode.xcodeproj', '-scheme', 'Opencode',
        '-destination', destination, '-derivedDataPath', '.build/DerivedData', '-resultBundlePath', result,
        '-parallel-testing-enabled', 'NO', ...(reviewOnly ? ['-only-testing:OpencodeUITests/ReviewSmokeTests' + (reviewTest ? '/' + reviewTest : '')] : composerOnly ? ['-only-testing:OpencodeUITests/ComposerSmokeTests' + (composerTest ? '/' + composerTest : '')] : values['ipad-only'] || values['read-flows-only'] ? ['-only-testing:OpencodeUITests/ReadSmokeTests'] : values['skip-snapshots'] ? ['-only-testing:OpencodeUITests'] : []), '-collect-test-diagnostics', 'never', 'test'],
        { cwd: repository, env: environment });
    } catch (error) {
      await writeFile(path.join(output, 'test.log'), error.message);
      throw error;
    }
    await writeFile(path.join(output, 'test.log'), log);
    if (!reviewOnly && !composerOnly && !values['ipad-only'] && !values['read-flows-only'] && !values['skip-snapshots']) {
      // The full test tree outgrows the process helper's 24,000-character output tail.
      const { stdout } = await promisify(execFile)('/usr/bin/xcrun', ['xcresulttool', 'get', 'test-results', 'tests', '--path', result], { maxBuffer: 64 * 1024 * 1024 });
      const editorResults = JSON.parse(stdout);
      await writeFile(path.join(output, 'test-results.json'), JSON.stringify(editorResults, null, 2));
      assertEditorCoverage(editorResults);
      console.log('PASS all composer editor regression tests ran in the standard scheme');
    }
    const attachments = path.join(output, 'attachments');
    await run('/usr/bin/xcrun', ['xcresulttool', 'export', 'attachments', '--path', result, '--output-path', attachments]);
    const manifest = JSON.parse(await readFile(path.join(attachments, 'manifest.json'), 'utf8'));
    if (!reviewOnly && !composerOnly) assert.ok(manifest.some(test => test.testIdentifier?.includes('ReadSmokeTests/testReadScreens')), 'Read smoke test must run; regenerate the Xcode project after adding test sources');
    const captured = new Set();
    const screenshots = path.join(repository, '.build/screenshots');
    await mkdir(screenshots, { recursive: true });
    for (const test of manifest) for (const attachment of test.attachments ?? []) {
      for (const name of [...reviewScreens(Boolean(values['ipad-only'])), 'composer-replace-draft', 'composer-sent', 'composer-queue', 'composer-new', 'composer-delete', 'composer-revert-confirmation', 'composer-send-menu', 'composer-worktree', 'permission-dock', 'permission-sheet', 'permission-reject', 'question-sheet', 'question-review', 'inbox', 'session-list', 'transcript-tools', 'transcript-live', 'subagent', 'ipad-split', 'ipad-portrait', 'onboarding', 'home', 'server-list', 'add-server-password', 'add-server', 're-pair', 'server-detail', 'diagnostics', 'local-network', 'update']) {
        if (attachment.suggestedHumanReadableName?.startsWith(name)) {
          await copyFile(path.join(attachments, attachment.exportedFileName), path.join(screenshots, `${name}.png`));
          captured.add(name);
          break;
        }
      }
    }
    if (!reviewOnly && !composerOnly) for (const name of ['inbox', 'session-list', 'transcript-tools', 'transcript-live', 'subagent']) assert.ok(captured.has(name), `Missing read screenshot: ${name}`);
    if (!reviewOnly && !composerOnly) {
    assert.ok(manifest.some(test => test.testIdentifier?.includes('ReadSmokeTests/testApprovals')), 'Approval smoke test must run');
    const latencyAttachment = manifest.flatMap(test => test.attachments ?? []).find(item => item.suggestedHumanReadableName?.startsWith('approval-latency'));
    assert.ok(latencyAttachment, 'Missing approval latency measurement');
    const latency = await readFile(path.join(attachments, latencyAttachment.exportedFileName), 'utf8');
    await writeFile(path.join(output, 'approval-latency.json'), latency);
    const answer = manifest.flatMap(test => test.attachments ?? []).find(item => item.suggestedHumanReadableName?.startsWith('answer-latency'));
    assert.ok(answer, 'Missing question answer latency measurement');
    await copyFile(path.join(attachments, answer.exportedFileName), path.join(output, 'answer-latency.json'));
    console.log('PASS permission allow once, question answer, reject with note; ' + latency.trim());
    console.log(`PASS live transcript, jump to latest, subagent, viewed state and deep link; ${result}`);
    }
    if (!reviewOnly && !values['ipad-only'] && !values['read-flows-only'] && !composerOnly) for (const name of ['onboarding', 'server-list', 'update']) assert.ok(captured.has(name));
    if (ipad && !values['ipad-only'] && !composerOnly) {
      const ipadResult = path.join(output, 'iPad.xcresult');
      const ipadLog = await run('/usr/bin/xcodebuild', ['-project', 'Opencode.xcodeproj', '-scheme', 'Opencode',
        '-destination', `platform=iOS Simulator,id=${ipad.udid}`, '-derivedDataPath', '.build/DerivedData',
        '-resultBundlePath', ipadResult, '-parallel-testing-enabled', 'NO', ...(reviewOnly ? [] : ['-only-testing:OpencodeUITests/ReadSmokeTests/testReadScreens', '-only-testing:OpencodeUITests/ComposerSmokeTests/testComposerQueueAndSessionActions']), '-only-testing:OpencodeUITests/ReviewSmokeTests' + (reviewTest ? '/' + reviewTest : ''),
        '-collect-test-diagnostics', 'never', 'test'], { cwd: repository, env: environment });
      await writeFile(path.join(output, 'ipad.log'), ipadLog);
      const ipadAttachments = path.join(output, 'ipad-attachments');
      await run('/usr/bin/xcrun', ['xcresulttool', 'export', 'attachments', '--path', ipadResult, '--output-path', ipadAttachments]);
      const ipadManifest = JSON.parse(await readFile(path.join(ipadAttachments, 'manifest.json'), 'utf8'));
      const ipadCaptured = new Set();
      for (const test of ipadManifest) for (const attachment of test.attachments ?? []) {
        for (const name of [...(reviewOnly ? [] : ['ipad-split', 'ipad-portrait', 'ipad-composer-queue', 'ipad-composer-new']), ...reviewScreens(true)]) {
          if (attachment.suggestedHumanReadableName?.startsWith(name)) {
            await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(screenshots, `${name}.png`));
            ipadCaptured.add(name);
            break;
          }
        }
      }
      for (const name of [...(reviewOnly ? [] : ['ipad-split', 'ipad-portrait', 'ipad-composer-queue', 'ipad-composer-new']), ...reviewScreens(true)]) assert.ok(ipadCaptured.has(name), `Missing iPad screenshot: ${name}`);
      for (const test of ipadManifest) for (const attachment of test.attachments ?? []) {
        if (attachment.suggestedHumanReadableName?.startsWith('review-scroll')) await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(output, attachment.suggestedHumanReadableName.startsWith('review-scroll-nowrap') ? 'ipad-review-scroll-nowrap.json' : 'ipad-review-scroll.json'));
        if (attachment.suggestedHumanReadableName?.startsWith('review-comment-server')) await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(output, 'ipad-review-comment-server.json'));
      }
      console.log('PASS iPad read flows and split-view captures');
    }
    if (!composerOnly && !values['read-flows-only'] && !values['ipad-only']) {
      for (const name of reviewScreens()) assert.ok(captured.has(name), `Missing review screenshot: ${name}`);
      for (const test of manifest) for (const attachment of test.attachments ?? []) {
        for (const name of ['review-scroll', 'review-comment-server', 'file-comment-server']) if (attachment.suggestedHumanReadableName?.startsWith(name)) await copyFile(path.join(attachments, attachment.exportedFileName), path.join(output, name + '.json'));
      }
    }
    if (reviewOnly && values['ipad-only']) {
      for (const name of reviewScreens(true)) assert.ok(captured.has(name), `Missing iPad review screenshot: ${name}`);
      for (const test of manifest) for (const attachment of test.attachments ?? []) {
        for (const name of ['review-scroll-nowrap', 'review-scroll', 'review-comment-server']) {
          if (!attachment.suggestedHumanReadableName?.startsWith(name)) continue;
          await copyFile(path.join(attachments, attachment.exportedFileName), path.join(output, 'ipad-' + name + '.json'));
          break;
        }
      }
    }
    // Leave a freshly installed, launched app on the requested booted simulator.
    const afterTests = JSON.parse(await run('/usr/bin/xcrun', ['simctl', 'list', 'devices', '--json']));
    const current = Object.values(afterTests.devices).flat().find(item => item.udid === device.udid);
    if (current.state !== 'Booted') await run('/usr/bin/xcrun', ['simctl', 'boot', device.udid]);
    await run('/usr/bin/xcrun', ['simctl', 'bootstatus', device.udid, '-b']);
    await run('/usr/bin/xcrun', ['simctl', 'install', device.udid, '.build/DerivedData/Build/Products/Debug-iphonesimulator/Opencode.app']);
    await run('/usr/bin/xcrun', ['simctl', 'launch', '--terminate-running-process', device.udid, 'dev.opencodeios.client'],
      { env: { ...process.env, SIMCTL_CHILD_OPENCODE_UI_TEST_ID: runID + '-read' } });
    console.log('PASS screenshots exported; app installed and launched on the booted simulator');
  } finally {
    try { await proxy?.close(); await v1?.stop(); await server?.stop(); }
    finally { await stopAll(); await mock.close(); }
  }
});
console.log('PASS UI smoke process cleanup and opencode isolation audit');
