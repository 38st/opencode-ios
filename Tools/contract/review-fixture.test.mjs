import { test } from 'node:test';
import assert from 'node:assert/strict';
import { configureReview, largeSource } from '../review-fixture/index.mjs';

test('review fixture rewrites all 5,000 lines with one changed numeric token', () => {
  const before = largeSource().trimEnd().split('\n'), after = largeSource(true).trimEnd().split('\n');
  assert.equal(before.length, 5000); assert.equal(after.length, 5000);
  before.forEach((line, i) => {
    assert.equal(line, `let value${i + 1} = ${i + 1}`);
    assert.equal(after[i], `let value${i + 1} = ${i + 2}`);
  });
});
test('review Git discovery is confined to the sandbox parent', () => {
  const env = { HOME: '/sandbox/home' }, config = { unchanged: true };
  configureReview(config, { project: '/sandbox/project' }, env);
  assert.deepEqual(env, { HOME: '/sandbox/home', GIT_CEILING_DIRECTORIES: '/sandbox' });
  assert.deepEqual(config, { unchanged: true });
});
