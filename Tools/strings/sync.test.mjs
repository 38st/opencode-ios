import { test } from 'node:test';
import assert from 'node:assert/strict';
import { commentAfter, contextComment, merge, previewRanges, readLiteral, serialize, translatable } from './sync.mjs';

test('reads literals with escapes and nested interpolations', () => {
  const source = 'localized("Open \\(name.isEmpty ? "it" : name) \\"now\\"", comment: "Menu item")';
  const start = source.indexOf('"');
  assert.equal(readLiteral(source, start).text, 'Open \\(name.isEmpty ? "it" : name) "now"');
  assert.equal(commentAfter(source, start), 'Menu item');
  assert.equal(commentAfter('localized("Done")', 10), null);
});

test('names the control and screen when the call has no comment', () => {
  const source = '    Button(localized("Pair again")) { }\n    .accessibilityLabel(localized("Remove"))\n    case .a: localized("Gone")';
  assert.equal(contextComment(source, source.indexOf('"Pair'), '/x/ServerDetailView.swift'), 'Button title in Server Detail View');
  assert.equal(contextComment(source, source.indexOf('"Remove'), '/x/ServerDetailView.swift'), 'VoiceOver label in Server Detail View');
  assert.equal(contextComment(source, source.indexOf('"Gone'), '/x/HomeView.swift'), 'Shown in Home View');
});

test('keeps translations and hand-written comments, drops unused keys', () => {
  const catalog = { sourceLanguage: 'en', version: '1.0', strings: {
    old: { comment: 'unused' },
    '%lld files': { comment: 'Count', localizations: { en: { variations: { plural: { one: { stringUnit: { state: 'translated', value: '%lld file' } } } } } } },
    Done: { comment: 'Hand-written' },
  } };
  const keys = new Map([['%lld files', { explicit: null, generated: 'Text in X' }], ['Done', { explicit: null, generated: 'Button title in X' }],
    ['New', { explicit: 'Creates one', generated: 'Button title in X' }]]);
  const merged = merge(catalog, keys);
  assert.deepEqual(Object.keys(merged.strings), ['%lld files', 'Done', 'New']);
  assert.equal(merged.strings['%lld files'].comment, 'Count');
  assert.ok(merged.strings['%lld files'].localizations.en.variations.plural.one);
  assert.equal(merged.strings.Done.comment, 'Hand-written');
  assert.equal(merged.strings.New.comment, 'Creates one');
});

test('writes the catalog the way Xcode does', () => {
  assert.equal(serialize({ version: '1.0', strings: {}, sourceLanguage: 'en' }),
    '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}');
});

test('skips previews and keys with nothing to translate', () => {
  const source = 'Text(localized("Real"))\n#Preview("Rows") {\n  Text("Sample } brace")\n}\nText(localized("After"))';
  const [range] = previewRanges(source);
  assert.ok(source.indexOf('"Sample') > range[0] && source.indexOf('"Sample') < range[1]);
  assert.ok(source.indexOf('"After') > range[1]);
  assert.equal(translatable('%@'), false);
  assert.equal(translatable('%lld · %@'), false);
  assert.equal(translatable('–'), false);
  assert.equal(translatable('%lld files'), true);
});
