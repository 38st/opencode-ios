import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadAcknowledgements, renderTable, replaceTable, versionProblems } from './generate.mjs';

test('the acknowledgements match the pinned versions and every licence text exists', () => {
  assert.deepEqual(versionProblems(loadAcknowledgements()), []);
});

test('the notices table is replaced between its markers only', () => {
  const doc = { sections: [{ title: 'Libraries', items: [{ name: 'A|B', url: 'https://example.com', version: '1.0', license: 'MIT', copyright: 'Someone' }] }] };
  const table = renderTable(doc);
  assert.match(table, /\| \[A\\\|B\]\(https:\/\/example\.com\) \| 1\.0 \| MIT \| Someone \|/);
  const page = replaceTable('before\n<!-- acknowledgements:start -->\nold\n<!-- acknowledgements:end -->\nafter', table);
  assert.ok(page.startsWith('before\n<!-- acknowledgements:start -->') && page.endsWith('<!-- acknowledgements:end -->\nafter'));
  assert.throws(() => replaceTable('no markers', table));
});
