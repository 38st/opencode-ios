import test from 'node:test';
import assert from 'node:assert/strict';
import { assertEditorCoverage, editorCases } from './editor-coverage.mjs';

const results = () => ({ testNodes: [{ children: editorCases.map(name => ({ name, nodeType: 'Test Case',
  nodeIdentifierURL: `test://Opencode/ComposerEditorTests/EditorBehaviorTests/${name}`, result: 'Passed' })) }] });
test('full UI verification requires every editor test to run and pass', () => {
  assert.doesNotThrow(() => assertEditorCoverage(results()));
  assert.throws(() => assertEditorCoverage({ testNodes: [] }), /must run and pass/);
  for (const result of ['Skipped', 'Failed']) {
    const value = results(); value.testNodes[0].children[2].result = result;
    assert.throws(() => assertEditorCoverage(value), /trailingEdge|TrailingEdge/);
  }
});
