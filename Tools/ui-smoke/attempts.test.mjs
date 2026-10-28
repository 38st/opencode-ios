import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { changedSnapshots, mergeAttempts, passes, retriedLines, retryable, snapshotTree, testCases } from './attempts.mjs';

const testCase = (id, result) => ({ nodeType: 'Test Case', nodeIdentifier: id, name: id.split('/')[1], result,
  nodeIdentifierURL: `test://com.apple.xcode/Opencode/OpencodeUITests/${id.replace('()', '')}` });
const tree = (...cases) => ({ testNodes: [{ nodeType: 'Test Plan', children: [{ nodeType: 'UI test bundle', children: [{ nodeType: 'Test Suite', children: cases }] }] }] });
const attachment = name => ({ suggestedHumanReadableName: name, exportedFileName: name + '.png' });

test('failed tests are found with the ID that runs them again', () => {
  const cases = testCases(tree(testCase('ReadSmokeTests/testReadScreens()', 'Failed'), testCase('ReviewSmokeTests/testReviewAndFiles()', 'Passed')));
  assert.deepEqual(cases, [
    { id: 'ReadSmokeTests/testReadScreens()', only: 'OpencodeUITests/ReadSmokeTests/testReadScreens', result: 'Failed' },
    { id: 'ReviewSmokeTests/testReviewAndFiles()', only: 'OpencodeUITests/ReviewSmokeTests/testReviewAndFiles', result: 'Passed' },
  ]);
  assert.deepEqual(testCases({}), []);
});

test('each test that ran again is listed with the attempt that passed, or as failed', () => {
  assert.deepEqual(retriedLines([{ test: 'A/testTwice()', attempts: 2, passed: 2 }, { test: 'B/testLast()', attempts: 3, passed: 3 }, { test: 'C/testNever()', attempts: 3, passed: null }]),
    ['RETRIED A/testTwice() (attempt 2 of 3)', 'RETRIED B/testLast() (attempt 3 of 3)', 'FAILED C/testNever() (3 of 3)']);
});

test('an expected failure that held counts as passing', () => {
  assert.equal(passes('Passed'), true);
  assert.equal(passes('Expected Failure'), true, 'testReviewNavigation reports this when the first chord is dropped');
  for (const result of ['Failed', 'Skipped', undefined]) assert.equal(passes(result), false);
});

test('only a failure that belongs to known failed tests is retried', () => {
  const failed = testCase('ReadSmokeTests/testReadScreens()', 'Failed'), passed = testCase('ReviewSmokeTests/testReviewAndFiles()', 'Passed');
  const named = { testIdentifierURL: failed.nodeIdentifierURL };
  const cases = testCases(tree(failed, passed, testCase('ReviewSmokeTests/testReviewNavigation()', 'Expected Failure')));
  assert.deepEqual(retryable({ failedTests: 1, testFailures: [named] }, cases).failing.map(test => test.only), ['OpencodeUITests/ReadSmokeTests/testReadScreens']);
  assert.match(retryable({ failedTests: 2, testFailures: [named, named] }, cases).problem, /summary counts 2/, 'A test the tree lost');
  assert.match(retryable({ failedTests: 1, testFailures: [named, { failureText: 'Test runner exited' }] }, cases).problem, /belongs to no test/);
  assert.match(retryable({}, cases).problem, /summary counts undefined/, 'An unreadable summary is not a pass');
  assert.match(retryable({ failedTests: 0, testFailures: [] }, testCases(tree(passed))).problem, /no failed test/);
  const unnamed = { ...failed, nodeIdentifierURL: undefined };
  assert.match(retryable({ failedTests: 1, testFailures: [named] }, testCases(tree(unnamed))).problem, /no ID/);
  assert.match(retryable({ failedTests: 1, testFailures: [named] }, testCases(tree(failed, testCase('A/testOther()', 'unknown')))).problem, /unknown results: A\/testOther\(\) unknown/);
});

test('only the passing attempt provides measurements and screenshots', () => {
  const manifest = [
    { testIdentifier: 'A/testOnce()', attachments: [attachment('approval-latency')] },
    { testIdentifier: 'B/testTwice()', attachments: [attachment('failure-screen')] },
    { testIdentifier: 'C/testNever()', attachments: [attachment('failure-screen')] },
  ];
  const later = [
    { directory: 'attempt-2', manifest: [{ testIdentifier: 'B/testTwice()', attachments: [attachment('review-scroll')] }, { testIdentifier: 'C/testNever()', attachments: [attachment('second-failure')] }], passed: ['B/testTwice()'] },
    { directory: 'attempt-3', manifest: [{ testIdentifier: 'C/testNever()', attachments: [attachment('third-failure')] }], passed: [] },
  ];
  assert.deepEqual(mergeAttempts(manifest, later).map(test => [test.testIdentifier, test.attachments.map(item => item.exportedFileName)]), [
    ['A/testOnce()', ['approval-latency.png']],
    ['B/testTwice()', [path.join('attempt-2', 'review-scroll.png')]],
    ['C/testNever()', ['failure-screen.png']],
  ]);
  assert.deepEqual(mergeAttempts([], [{ directory: 'attempt-2', manifest: [{ testIdentifier: 'D/testLate()', attachments: [] }], passed: ['D/testLate()'] }]),
    [{ testIdentifier: 'D/testLate()', attachments: [] }], 'A test whose failed run left no attachments still counts');
  assert.deepEqual(mergeAttempts([{ testIdentifier: 'A/testOnce()', attachments: [attachment('approval-latency')] }], [{ directory: 'attempt-2', manifest: [], passed: ['A/testOnce()'] }]),
    [{ testIdentifier: 'A/testOnce()', attachments: [] }], 'The failed run\'s measurement never stands in for a passing attempt that left none');
});

test('a run that records or changes a reference image is caught', async () => {
  const root = await mkdtemp(path.join(tmpdir(), 'snapshots-'));
  try {
    const folder = path.join(root, 'Packages/Kit/Tests/Screens/__Snapshots__/Suite');
    await mkdir(folder, { recursive: true });
    await mkdir(path.join(root, 'Packages/Kit/.build/__Snapshots__'), { recursive: true });
    await writeFile(path.join(folder, 'home.png'), 'one');
    await writeFile(path.join(root, 'Packages/Kit/Tests/Screens/Other.swift'), 'not a snapshot');
    const before = await snapshotTree(root);
    assert.deepEqual([...before.keys()], ['Packages/Kit/Tests/Screens/__Snapshots__/Suite/home.png']);
    await writeFile(path.join(root, 'Packages/Kit/.build/__Snapshots__/ignored.png'), 'build output');
    assert.deepEqual(changedSnapshots(before, await snapshotTree(root)), []);
    await writeFile(path.join(folder, 'home.png'), 'two');
    await writeFile(path.join(folder, 'new.png'), 'recorded');
    assert.deepEqual(changedSnapshots(before, await snapshotTree(root)),
      ['Packages/Kit/Tests/Screens/__Snapshots__/Suite/home.png', 'Packages/Kit/Tests/Screens/__Snapshots__/Suite/new.png']);
  } finally { await rm(root, { recursive: true, force: true }); }
});
