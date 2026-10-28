import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';

// A failed UI test runs again. These helpers keep that honest: a run that records a reference image fails, the tests
// that ran again are listed, and only the attempt that passed provides measurements and screenshots.

/** Every file under a `__Snapshots__` folder below the given folders, mapped to a hash of its contents. */
export async function snapshotTree(root, folders = ['Packages', 'Tests', 'UITests']) {
  const files = new Map();
  async function walk(directory, inside) {
    let entries;
    try { entries = await readdir(directory, { withFileTypes: true }); }
    catch (error) { if (error.code === 'ENOENT') return; throw error; }
    for (const entry of entries) {
      if (['.build', '.git', '.swiftpm', 'node_modules'].includes(entry.name)) continue;
      const item = path.join(directory, entry.name);
      if (entry.isDirectory()) await walk(item, inside || entry.name === '__Snapshots__');
      else if (inside) files.set(path.relative(root, item), createHash('sha256').update(await readFile(item)).digest('hex'));
    }
  }
  for (const folder of folders) await walk(path.join(root, folder), false);
  return files;
}

/** The reference images a run added or changed. */
export function changedSnapshots(before, after) {
  return [...after].filter(([file, hash]) => before.get(file) !== hash).map(([file]) => file).sort();
}

/** Each test case in a result tree (`xcresulttool get test-results tests`) with its result and `-only-testing` ID. */
export function testCases(results) {
  const cases = [];
  function visit(node) {
    if (node.nodeType === 'Test Case') {
      // test://com.apple.xcode/<project>/<target>/<class>/<method>
      const only = node.nodeIdentifierURL ? decodeURIComponent(new URL(node.nodeIdentifierURL).pathname).split('/').slice(2).join('/') : undefined;
      cases.push({ id: node.nodeIdentifier, only, result: node.result });
      return;
    }
    for (const child of node.children ?? []) visit(child);
  }
  for (const node of results.testNodes ?? []) visit(node);
  return cases;
}

/** Whether a test case's result counts as passing: an expected failure is an `XCTExpectFailure` that held. */
export const passes = result => result === 'Passed' || result === 'Expected Failure';
const knownResults = new Set(['Passed', 'Failed', 'Skipped', 'Expected Failure']);

/**
 * The failed tests a failed run can be retried with, or the reason it cannot. Every failure has to belong to a test
 * case the tool can run again: a failure outside a test, a runner that died, a result the tree and the summary
 * (`xcresulttool get test-results summary`) disagree on, or a result the tool does not know fails the stage.
 */
export function retryable(summary, cases) {
  const unknown = cases.filter(test => !knownResults.has(test.result));
  if (unknown.length > 0) return { problem: 'unknown results: ' + unknown.map(test => `${test.id} ${test.result}`).join(', ') };
  const failed = cases.filter(test => test.result === 'Failed');
  if (failed.length === 0) return { problem: 'no failed test explains the failure' };
  const unnamed = failed.filter(test => !test.only);
  if (unnamed.length > 0) return { problem: 'failed tests with no ID to run them by: ' + unnamed.map(test => test.id).join(', ') };
  if (summary.failedTests !== failed.length) return { problem: `the summary counts ${summary.failedTests} failed tests and the result tree ${failed.length}` };
  if ((summary.testFailures ?? []).some(failure => !failure.testIdentifierURL)) return { problem: 'a failure belongs to no test' };
  return { failing: failed };
}

/** One line per test that ran again: the attempt that passed, or how many attempts failed. */
export function retriedLines(tests, iterations = 3) {
  return tests.map(test => test.passed ? `RETRIED ${test.test} (attempt ${test.passed} of ${iterations})` : `FAILED ${test.test} (${test.attempts} of ${iterations})`);
}

/**
 * The stage's attachments, with each test that passed on a later attempt taking that attempt's attachments, or none,
 * instead of its failed run's. `later` lists each attempt's exported manifest, the folder it was exported to inside
 * the stage's attachments folder, and the tests that passed in it.
 */
export function mergeAttempts(manifest, later) {
  const replaced = new Map();
  for (const attempt of later) {
    for (const id of attempt.passed) {
      const test = attempt.manifest.find(item => item.testIdentifier === id) ?? { testIdentifier: id, attachments: [] };
      replaced.set(id, { ...test, attachments: (test.attachments ?? []).map(item => ({ ...item, exportedFileName: path.join(attempt.directory, item.exportedFileName) })) });
    }
  }
  const merged = manifest.map(test => replaced.get(test.testIdentifier) ?? test);
  for (const [id, test] of replaced) if (!manifest.some(item => item.testIdentifier === id)) merged.push(test);
  return merged;
}
