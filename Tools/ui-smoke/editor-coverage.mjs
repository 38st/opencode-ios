import assert from 'node:assert/strict';

export const editorCases = [
  'nativeFormattingDefinitionDoesNotMakeMentionsAtomic()',
  'textKitMentionsDeleteAtomicallyAndUndoAndMarkedTextSurvive()',
  'typingAtMentionTrailingEdgeDoesNotExtendToken()',
  'markedCompositionOwnsHardwareReturnAndStyleChangesAreBounded()',
  'dropsRouteMentionsMediaAndTextWithoutDuplicates()',
  'returnCommandReturnAndEscapeEachRunOnce()',
];
export function assertEditorCoverage(results) {
  const cases = [];
  function visit(nodes) {
    for (const node of nodes ?? []) {
      if (node.nodeIdentifierURL?.includes('/ComposerEditorTests/') && node.nodeType === 'Test Case') cases.push(node);
      visit(node.children);
    }
  }
  visit(results.testNodes);
  for (const name of editorCases) {
    assert.ok(cases.some(node => node.name === name && node.result === 'Passed'), `Editor test must run and pass: ${name}`);
  }
}
