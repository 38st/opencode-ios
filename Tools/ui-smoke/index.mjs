import assert from 'node:assert/strict';
import { seedReviewRepository, configureReview } from '../review-fixture/index.mjs';
import { assertEditorCoverage } from './editor-coverage.mjs';
import { changedSnapshots, mergeAttempts, passes, retriedLines, retryable, snapshotTree, testCases } from './attempts.mjs';
import { startFaultProxy } from './fault-proxy.mjs';
import { configureComposer } from './composer-config.mjs';
import { seedReadScreens } from './read-screens.mjs';
import { vcsProvider, waitForNoProvider } from './vcs-reset.mjs';
import path from 'node:path';
import { mkdir, writeFile, readFile, copyFile, rm } from 'node:fs/promises';
import { parseArgs, promisify } from 'node:util';
import { execFile } from 'node:child_process';
import { repository, resolveVersion, startSandbox, V1_VERSION } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { stopAll, run } from '../opencode-sandbox/process.mjs';
import { startMock } from '../mock-llm/server.mjs';

const { values } = parseArgs({ options: { version: { type: 'string' }, 'skip-snapshots': { type: 'boolean' }, 'review-only': { type: 'boolean' }, 'review-test': { type: 'string' }, 'ipad-only': { type: 'boolean' }, 'read-flows-only': { type: 'boolean' }, 'composer-only': { type: 'boolean' }, 'worktree-only': { type: 'boolean' }, 'composer-test': { type: 'string' }, 'workspace-only': { type: 'boolean' }, 'workspace-test': { type: 'string' }, 'system-only': { type: 'boolean' }, 'system-test': { type: 'string' } } });
const workspaceTests = ['testMenuNavigationAndSwitcher', 'testMenuComposerCommands', 'testReviewNextApproval', 'testTwoWindows', 'testDragFileIntoComposer'];
const workspaceTest = values['workspace-test'];
if (workspaceTest) assert.ok(workspaceTests.includes(workspaceTest), 'Unknown workspace test');
const workspaceOnly = values['workspace-only'] || Boolean(workspaceTest);
// The iPad flow's workspace captures: the menu bar, the switcher, two windows and drag and drop.
const workspaceScreens = ['ipad-workspace-review-open', 'ipad-palette', 'ipad-workspace-composer-commands', 'ipad-workspace-next-approval', 'ipad-windows-second', 'ipad-workspace-drop-mention'];
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
const systemTests = ['testShortcutsRunTheIntents', 'testSpotlightOpensASession', 'testWidgetOnTheHomeScreen'];
const systemTest = values['system-test'];
if (systemTest) assert.ok(systemTests.includes(systemTest), 'Unknown system test');
const systemOnly = values['system-only'] || Boolean(systemTest);
// The iPhone system flow's captures: Shortcuts, Spotlight, the widget and Settings.
const systemScreens = ['system-shortcuts-send', 'system-shortcuts-status', 'system-spotlight', 'system-widget', 'system-settings'];
// A failed UI test runs again, up to twice, on the same build: a test passes when any attempt passes, so a regression
// still fails while a burst of load on the shared host no longer restarts the whole run. Unit and snapshot tests run
// once: a snapshot test records a missing reference image and would pass on the next attempt.
const attemptsAllowed = 3;
// A UI test that hangs ends at its `executionTimeAllowance` (600 seconds when it sets none) and fails like any other,
// so it can run again; without this XCTest waits for it forever.
const timeouts = ['-test-timeouts-enabled', 'YES'];
const full = !reviewOnly && !composerOnly && !workspaceOnly && !systemOnly && !values['ipad-only'] && !values['read-flows-only'] && !values['skip-snapshots'];
const version = await resolveVersion(values.version);
const runID = `ui-${Date.now()}`;
const output = path.join(repository, '.build/ui-smoke', runID);
await mkdir(output, { recursive: true });
const testResults = async (result, report = 'tests') => JSON.parse((await promisify(execFile)('/usr/bin/xcrun', ['xcresulttool', 'get', 'test-results', report, '--path', result],
  { maxBuffer: 64 * 1024 * 1024 })).stdout);
/** The failed tests of a failed run, or an error when the failure is not theirs alone. */
async function failedTests(stage, result, failure) {
  const plan = retryable(await testResults(result, 'summary').catch(() => ({})), testCases(await testResults(result).catch(() => ({}))));
  if (plan.problem) throw new Error(`${stage}: not retried, ${plan.problem}`, { cause: failure });
  return plan.failing;
}
/** Runs `xcodebuild` into a result bundle and writes its log. A run that adds or changes a reference image fails. */
async function xcodebuildTest(result, log, args, env, action = 'test') {
  const before = await snapshotTree(repository);
  let failure;
  try {
    await writeFile(path.join(output, log), await run('/usr/bin/xcodebuild', ['-project', 'Opencode.xcodeproj', '-scheme', 'Opencode',
      '-derivedDataPath', '.build/DerivedData', '-resultBundlePath', result, '-parallel-testing-enabled', 'NO', ...args,
      '-collect-test-diagnostics', 'never', action], { cwd: repository, env }));
  } catch (error) {
    failure = error;
    await writeFile(path.join(output, log), error.message);
  }
  const recorded = changedSnapshots(before, await snapshotTree(repository));
  for (const file of recorded) console.log(`RECORDED ${file}`);
  // Never retried: a second attempt would compare against the image the first one wrote.
  if (recorded.length > 0) throw Object.assign(new Error('The run added or changed reference images: ' + recorded.join(', '), { cause: failure }), { recorded });
  if (failure) throw failure;
}
const retried = {};
const exportAttachments = async (result, folder) => {
  await run('/usr/bin/xcrun', ['xcresulttool', 'export', 'attachments', '--path', result, '--output-path', folder]);
  return JSON.parse(await readFile(path.join(folder, 'manifest.json'), 'utf8'));
};
/**
 * A UI stage. The failed tests run again together, up to twice, on the same build; the tool does this itself because
 * Xcode 26 and later drops its own retry when a failure in an async test that stops at its first failure relaunches
 * the test runner (Apple's known issue 108565878). `beforeRetry` resets the fixtures a failed attempt can leave
 * changed. Prints the tests that ran again, keeps them in retried.json, and returns each test's attachments from the
 * attempt that passed.
 */
async function uiStage(stage, destination, result, log, attachments, filters, env, beforeRetry) {
  let failure;
  try { await xcodebuildTest(result, log, ['-destination', destination, ...timeouts, ...filters], env); } catch (error) { failure = error; }
  // A run that recorded a reference image is never retried: a second attempt would compare against that image.
  if (failure?.recorded) throw failure;
  let failing = failure ? await failedTests(stage, result, failure) : [];
  const manifest = await exportAttachments(result, attachments);
  const tests = failing.map(test => ({ test: test.id, attempts: 1, passed: null })), later = [];
  try {
    for (let attempt = 2; attempt <= attemptsAllowed && failing.length > 0; attempt++) {
      await beforeRetry();
      const bundle = result.replace(/\.xcresult$/, `-attempt-${attempt}.xcresult`), folder = `attempt-${attempt}`;
      let retryFailure;
      try {
        await xcodebuildTest(bundle, log.replace(/\.log$/, `-attempt-${attempt}.log`), ['-destination', destination, ...timeouts,
          ...failing.map(test => '-only-testing:' + test.only)], env, 'test-without-building');
      } catch (error) { if (error.recorded) throw error; retryFailure = error; }
      for (const entry of tests) if (failing.some(test => test.id === entry.test)) entry.attempts = attempt;
      if (retryFailure) await failedTests(`${stage} attempt ${attempt}`, bundle, retryFailure);
      const outcomes = new Map(testCases(await testResults(bundle)).map(test => [test.id, test.result]));
      const passed = failing.filter(test => passes(outcomes.get(test.id))).map(test => test.id);
      for (const entry of tests) if (passed.includes(entry.test)) entry.passed = attempt;
      // The tests that passed take this attempt's attachments, so its export has to work.
      if (passed.length > 0) later.push({ directory: folder, manifest: await exportAttachments(bundle, path.join(attachments, folder)), passed });
      failing = failing.filter(test => !passed.includes(test.id));
    }
  } finally {
    // Also when a retry fails outside its tests: what ran again is always on record.
    for (const line of retriedLines(tests, attemptsAllowed)) console.log(line);
    retried[stage] = tests;
    await writeFile(path.join(output, 'retried.json'), JSON.stringify(retried, null, 2) + '\n');
  }
  if (failing.length > 0) throw new Error(`${stage}: ${failing.map(test => test.id).join(', ')} failed ${attemptsAllowed} times`, { cause: failure });
  return mergeAttempts(manifest, later);
}
await run('xcodegen', ['generate'], { cwd: repository });
const inventory = JSON.parse(await run('/usr/bin/xcrun', ['simctl', 'list', 'devices', 'available', '--json']));
const devices = Object.values(inventory.devices).flat();
const device = devices.find(device => device.name === 'iPhone 17 Pro' && device.state === 'Booted')
  ?? devices.find(device => device.name === 'iPhone 17 Pro');
assert.ok(device, 'The existing iPhone 17 Pro simulator is required');
const ipad = devices.find(device => device.name === 'opencode-ios iPad');
const destination = `platform=iOS Simulator,id=${values['ipad-only'] || workspaceOnly ? (assert.ok(ipad, 'The workspace tests need the opencode-ios iPad simulator'), ipad.udid) : device.udid}`;
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
    // A failed attempt can leave the fault proxy blocking or dropping traffic and the no-Git fixture with a repository.
    const beforeRetry = async () => {
      const reset = await fetch(proxy.url + '/__fault', { method: 'POST', headers: { 'x-fault-token': proxy.adminToken, 'content-type': 'application/json' },
        body: JSON.stringify({ blocked: false, dropPrompts: 0, pauseEvents: false, reset: true }) });
      assert.equal(reset.status, 200, 'The fault proxy resets before a retry');
      await rm(path.join(review.noGit, '.git'), { recursive: true, force: true });
      // The server could keep the repository state it saw; the retried test must start without a repository.
      await waitForNoProvider(() => vcsProvider(server, review.noGit));
    };
    if (full) {
      const units = path.join(output, 'Units.xcresult');
      await xcodebuildTest(units, 'units.log', ['-destination', destination, '-skip-testing:OpencodeUITests'], environment);
      // The full test tree outgrows the process helper's 24,000-character output tail.
      const editorResults = await testResults(units);
      await writeFile(path.join(output, 'test-results.json'), JSON.stringify(editorResults, null, 2));
      assertEditorCoverage(editorResults);
      console.log('PASS all composer editor regression tests ran in the standard scheme');
    }
    const attachments = path.join(output, 'attachments');
    const manifest = await uiStage(values['ipad-only'] || workspaceOnly ? 'iPad' : 'iPhone', destination, result, 'test.log', attachments, ['-skip-testing:OpencodeUITests/PushSmokeTests',
      ...(workspaceOnly ? ['-only-testing:OpencodeUITests/WorkspaceSmokeTests' + (workspaceTest ? '/' + workspaceTest : '')] : systemOnly ? ['-only-testing:OpencodeUITests/SystemSmokeTests' + (systemTest ? '/' + systemTest : '')] : reviewOnly ? ['-only-testing:OpencodeUITests/ReviewSmokeTests' + (reviewTest ? '/' + reviewTest : '')] : composerOnly ? ['-only-testing:OpencodeUITests/ComposerSmokeTests' + (composerTest ? '/' + composerTest : '')] : values['ipad-only'] || values['read-flows-only'] ? ['-only-testing:OpencodeUITests/ReadSmokeTests'] : ['-only-testing:OpencodeUITests', '-skip-testing:OpencodeUITests/WorkspaceSmokeTests'])],
      environment, beforeRetry);
    if (!reviewOnly && !composerOnly && !workspaceOnly && !systemOnly) assert.ok(manifest.some(test => test.testIdentifier?.includes('ReadSmokeTests/testReadScreens')), 'Read smoke test must run; regenerate the Xcode project after adding test sources');
    const captured = new Set();
    const screenshots = path.join(repository, '.build/screenshots');
    await mkdir(screenshots, { recursive: true });
    for (const test of manifest) for (const attachment of test.attachments ?? []) {
      // Findings the tests record about the simulator, kept next to the result bundle.
      const finding = attachment.suggestedHumanReadableName ?? '';
      if (finding.startsWith('finding-')) await copyFile(path.join(attachments, attachment.exportedFileName), path.join(output, (values['ipad-only'] || workspaceOnly ? 'ipad-' : '') + path.basename(finding)));
      for (const name of [...reviewScreens(Boolean(values['ipad-only'])), ...workspaceScreens, ...systemScreens, 'palette-iphone', 'context-sheet', 'composer-replace-draft', 'composer-sent', 'composer-queue', 'composer-new', 'composer-delete', 'composer-revert-confirmation', 'composer-send-menu', 'composer-worktree', 'permission-dock', 'permission-sheet', 'permission-reject', 'question-sheet', 'question-review', 'inbox', 'session-list', 'transcript-tools', 'transcript-live', 'subagent', 'ipad-split', 'ipad-portrait', 'onboarding', 'home', 'server-list', 'add-server-password', 'add-server', 're-pair', 'server-detail', 'diagnostics', 'local-network', 'update']) {
        if (attachment.suggestedHumanReadableName?.startsWith(name + '_')) {
          await copyFile(path.join(attachments, attachment.exportedFileName), path.join(screenshots, `${name}.png`));
          captured.add(name);
          break;
        }
      }
    }
    if (!reviewOnly && !composerOnly && !workspaceOnly && !systemOnly) for (const name of ['inbox', 'session-list', 'transcript-tools', 'transcript-live', 'subagent']) assert.ok(captured.has(name), `Missing read screenshot: ${name}`);
    if (workspaceOnly && !workspaceTest) for (const name of workspaceScreens) assert.ok(captured.has(name), `Missing iPad workspace screenshot: ${name}`);
    if ((full || systemOnly) && !systemTest) for (const name of systemScreens) assert.ok(captured.has(name), `Missing system screenshot: ${name}`);
    if (!reviewOnly && !composerOnly && !workspaceOnly && !systemOnly) {
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
    if (!reviewOnly && !values['ipad-only'] && !values['read-flows-only'] && !composerOnly && !workspaceOnly && !systemOnly) for (const name of ['onboarding', 'server-list', 'update']) assert.ok(captured.has(name));
    if (full) for (const name of ['palette-iphone', 'context-sheet']) assert.ok(captured.has(name), `Missing switcher screenshot: ${name}`);
    if (ipad && !values['ipad-only'] && !composerOnly && !workspaceOnly && !systemOnly) {
      const ipadResult = path.join(output, 'iPad.xcresult');
      const ipadAttachments = path.join(output, 'ipad-attachments');
      const ipadManifest = await uiStage('iPad', `platform=iOS Simulator,id=${ipad.udid}`, ipadResult, 'ipad.log', ipadAttachments, [...(reviewOnly ? [] : ['-only-testing:OpencodeUITests/ReadSmokeTests/testReadScreens', '-only-testing:OpencodeUITests/ComposerSmokeTests/testComposerQueueAndSessionActions', '-only-testing:OpencodeUITests/WorkspaceSmokeTests']), '-only-testing:OpencodeUITests/ReviewSmokeTests' + (reviewTest ? '/' + reviewTest : '')],
        environment, beforeRetry);
      const ipadCaptured = new Set();
      for (const test of ipadManifest) for (const attachment of test.attachments ?? []) {
        const finding = attachment.suggestedHumanReadableName ?? '';
        if (finding.startsWith('finding-')) await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(output, 'ipad-' + path.basename(finding)));
        for (const name of [...(reviewOnly ? [] : ['ipad-split', 'ipad-portrait', 'ipad-composer-queue', 'ipad-composer-new', ...workspaceScreens]), ...reviewScreens(true)]) {
          if (attachment.suggestedHumanReadableName?.startsWith(name + '_')) {
            await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(screenshots, `${name}.png`));
            ipadCaptured.add(name);
            break;
          }
        }
      }
      for (const name of [...(reviewOnly ? [] : ['ipad-split', 'ipad-portrait', 'ipad-composer-queue', 'ipad-composer-new', ...workspaceScreens]), ...reviewScreens(true)]) assert.ok(ipadCaptured.has(name), `Missing iPad screenshot: ${name}`);
      for (const test of ipadManifest) for (const attachment of test.attachments ?? []) {
        if (attachment.suggestedHumanReadableName?.startsWith('review-scroll')) await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(output, attachment.suggestedHumanReadableName.startsWith('review-scroll-nowrap') ? 'ipad-review-scroll-nowrap.json' : 'ipad-review-scroll.json'));
        if (attachment.suggestedHumanReadableName?.startsWith('review-comment-server')) await copyFile(path.join(ipadAttachments, attachment.exportedFileName), path.join(output, 'ipad-review-comment-server.json'));
      }
      console.log('PASS iPad read flows, split-view captures, menu bar, switcher, two windows and drag and drop');
    }
    if (!composerOnly && !workspaceOnly && !systemOnly && !values['read-flows-only'] && !values['ipad-only']) {
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

if (full) {
  // The push stage runs its one test once, with no retry, and must not record a reference image either.
  const before = await snapshotTree(repository);
  console.log(await run(process.execPath, ['Tools/push-e2e/simulator.mjs', '--version', version], { cwd: repository }));
  const recorded = changedSnapshots(before, await snapshotTree(repository));
  for (const file of recorded) console.log(`RECORDED ${file}`);
  assert.deepEqual(recorded, [], 'The push stage added or changed reference images');
}
