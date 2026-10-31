#!/usr/bin/env node
// Keeps every String Catalog in step with the code. After an app build (xcodebuild with
// -derivedDataPath .build/DerivedData), the compiler has written one .stringsdata file per target listing every
// localizable literal: each module's `localized("…")` calls and SwiftUI literals in the app and its extensions.
// This script adds new keys, removes keys the code no longer uses, keeps existing translations and plural
// variations, and gives every key a translator comment: the call's own `comment:` when it has one, otherwise a
// note naming the control and the screen it appears on. `--check` writes nothing and fails when a catalog is stale.
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

// Which build directory feeds which catalog. Package modules use `<Module>-t.build`; targets use `<Target>.build`.
export function catalogTargets() {
  const sources = join(root, 'Packages/OpencodeKit/Sources');
  const targets = readdirSync(sources)
    .filter((module) => existsSync(join(sources, module, 'Resources/Localizable.xcstrings')))
    .map((module) => ({ build: `OpencodeKit.build/Debug-iphonesimulator/${module}-t.build`,
      catalog: join(sources, module, 'Resources/Localizable.xcstrings') }));
  for (const [target, catalog] of [['Opencode', 'App/Localizable.xcstrings'], ['Widgets', 'Extensions/Widgets/Localizable.xcstrings'],
    ['NotificationService', 'Extensions/NotificationService/Localizable.xcstrings']]) {
    if (existsSync(join(root, catalog))) targets.push({ build: `Opencode.build/Debug-iphonesimulator/${target}.build`, catalog: join(root, catalog) });
  }
  return targets;
}

function stringsdataFiles(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return stringsdataFiles(path);
    return name.endsWith('.stringsdata') && !name.startsWith('ExtractedAppShortcutsMetadata') ? [path] : [];
  });
}

// Reads one Swift string literal starting at `index` (the opening quote). Returns its text and the index after it.
export function readLiteral(source, index) {
  let hashes = 0;
  while (source[index + hashes] === '#') hashes += 1;
  let i = index + hashes;
  const multiline = source.startsWith('"""', i);
  const quote = multiline ? '"""' : '"';
  i += quote.length;
  let text = '';
  const close = quote + '#'.repeat(hashes);
  while (i < source.length) {
    if (source.startsWith(close, i)) return { text, end: i + close.length };
    if (source[i] === '\\' && source.slice(i + 1, i + 1 + hashes) === '#'.repeat(hashes)) {
      const next = source[i + 1 + hashes];
      if (next === '(') {
        let depth = 1;
        let j = i + 2 + hashes;
        while (j < source.length && depth > 0) {
          if (source[j] === '"') { j = readLiteral(source, j).end; continue; }
          if (source[j] === '(') depth += 1;
          if (source[j] === ')') depth -= 1;
          j += 1;
        }
        text += source.slice(i, j);
        i = j;
        continue;
      }
      const escapes = { n: '\n', t: '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0' };
      text += escapes[next] ?? next;
      i += 2 + hashes;
      continue;
    }
    text += source[i];
    i += 1;
  }
  return null;
}

// The `comment: "…"` argument that follows the key literal in the same call, if any.
export function commentAfter(source, offset) {
  const literal = readLiteral(source, offset);
  if (!literal) return null;
  const match = /^\s*,\s*comment:\s*/.exec(source.slice(literal.end));
  if (!match) return null;
  return readLiteral(source, literal.end + match[0].length)?.text ?? null;
}

const roles = [
  [/(?:^|[^\w.])Button\($/, 'Button title'], [/\.accessibilityLabel\($/, 'VoiceOver label'],
  [/\.accessibilityHint\($/, 'VoiceOver hint'], [/\.accessibilityValue\($/, 'VoiceOver value'],
  [/accessibilityAction\(named:\s*$/, 'VoiceOver action'], [/AccessibilityCustomAction\(name:\s*$/, 'VoiceOver action'],
  [/(?:navigationTitle|ocNavigationTitle)\($/, 'Screen title'], [/(?:OCSection|Section|OCSidebarHeader)\($/, 'Section heading'],
  [/(?:Toggle|OCToggleRow)\($/, 'Switch label'], [/(?:TextField|SecureField)\($/, 'Text field placeholder'],
  [/\.alert\($/, 'Alert title'], [/\.confirmationDialog\($/, 'Confirmation title'], [/\.help\($/, 'Pointer tooltip'],
  [/(?:Label|OCLabel)\($/, 'Label'], [/(?:Picker|Menu|OCMenuButton)\($/, 'Menu title'], [/(?:NavigationLink|Link|ShareLink)\($/, 'Link title'],
  [/(?:OCBadge|OCPill)\($/, 'Badge'], [/OCIconButton\($/, 'Icon button label'], [/LabeledContent\($/, 'Row label'],
  [/ContentUnavailableView\($/, 'Empty state title'], [/\.searchable\(.*prompt:\s*$/, 'Search field placeholder'],
  [/(?:^|[^\w.])Text\($/, 'Text'],
];

function words(name) {
  return name.replace(/\.swift$/, '').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/([A-Z]+)([A-Z][a-z])/g, '$1 $2');
}

// A translator note for keys whose call has no comment: the control (from the code before `localized(`) and the
// screen (from the file name).
export function contextComment(source, offset, file) {
  const lineStart = source.lastIndexOf('\n', offset) + 1;
  const before = source.slice(lineStart, offset).replace(/localized\($/, '').trimEnd();
  const role = roles.find(([pattern]) => pattern.test(before))?.[1];
  const screen = words(basename(file));
  if (/\b(?:case|return)\b/.test(before) || /:\s*$/.test(before) || /=\s*$/.test(before)) return `Shown in ${screen}`;
  return role ? `${role} in ${screen}` : `Shown in ${screen}`;
}

function offsetOf(source, location) {
  if (Number.isInteger(location.startingOffset)) return location.startingOffset;
  let line = 1;
  let index = 0;
  while (line < location.startingLine) {
    index = source.indexOf('\n', index) + 1;
    line += 1;
  }
  return index + (location.startingColumn - 1);
}

// Offsets covered by `#Preview { … }` blocks: preview text is sample data, never shown to people.
export function previewRanges(source) {
  const ranges = [];
  for (let at = source.indexOf('#Preview'); at >= 0; at = source.indexOf('#Preview', at + 1)) {
    let i = source.indexOf('{', at);
    if (i < 0) break;
    const start = i;
    let depth = 0;
    for (; i < source.length; i += 1) {
      if (source[i] === '"') { i = (readLiteral(source, i)?.end ?? source.length) - 1; continue; }
      if (source[i] === '{') depth += 1;
      if (source[i] === '}' && --depth === 0) break;
    }
    ranges.push([start, i]);
  }
  return ranges;
}

// A key with no letters outside its placeholders ("%@", "%lld", "–") has nothing to translate.
export function translatable(key) {
  return /\p{L}/u.test(key.replace(/%(?:\d+\$)?(?:ll|l)?[@dDuUxXoOfeEgGcCsSpaAF]/g, ''));
}

export function extractedKeys(files) {
  const keys = new Map();
  const sources = new Map();
  for (const file of files) {
    const data = JSON.parse(readFileSync(file, 'utf8'));
    if (!sources.has(data.source)) sources.set(data.source, existsSync(data.source) ? readFileSync(data.source, 'utf8') : '');
    const source = sources.get(data.source);
    const previews = source ? previewRanges(source) : [];
    for (const entry of data.tables?.Localizable ?? []) {
      const offset = source ? offsetOf(source, entry.location) : -1;
      if (!translatable(entry.key) || previews.some(([from, to]) => offset >= from && offset <= to)) continue;
      const explicit = entry.comment || (offset >= 0 ? commentAfter(source, offset) : null) || null;
      const known = keys.get(entry.key);
      // A key used in several places keeps an explicit comment from any of them, else the first place's note.
      if (!known) keys.set(entry.key, { explicit, generated: offset >= 0 ? contextComment(source, offset, data.source) : null });
      else if (!known.explicit && explicit) known.explicit = explicit;
    }
  }
  return keys;
}

// The code's own comment wins; a comment already in the catalog (written by hand) is kept; otherwise the
// generated note is used.
export function merge(catalog, keys) {
  const strings = {};
  for (const key of [...keys.keys()].sort(compareKeys)) {
    const existing = catalog.strings?.[key] ?? {};
    const found = keys.get(key);
    const entry = { ...existing, comment: found.explicit ?? existing.comment ?? found.generated };
    delete entry.extractionState;
    if (!entry.comment) delete entry.comment;
    strings[key] = entry;
  }
  return { sourceLanguage: catalog.sourceLanguage ?? 'en', strings, version: catalog.version ?? '1.0' };
}

// Xcode orders keys by Unicode code point and writes `"key" : value` with two-space indentation.
function compareKeys(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

export function serialize(value, indent = '') {
  const inner = indent + '  ';
  if (Array.isArray(value)) {
    if (!value.length) return '[]';
    return `[\n${value.map((item) => inner + serialize(item, inner)).join(',\n')}\n${indent}]`;
  }
  if (value && typeof value === 'object') {
    const keys = Object.keys(value).sort(compareKeys);
    if (!keys.length) return '{\n\n' + indent + '}';
    return `{\n${keys.map((key) => `${inner}${JSON.stringify(key)} : ${serialize(value[key], inner)}`).join(',\n')}\n${indent}}`;
  }
  return JSON.stringify(value);
}

function main() {
  const check = process.argv.includes('--check');
  const flag = process.argv.indexOf('--derived-data');
  const derived = flag > 0 ? process.argv[flag + 1] : join(root, '.build/DerivedData');
  const intermediates = join(derived, 'Build/Intermediates.noindex');
  const stale = [];
  let total = 0;
  for (const target of catalogTargets()) {
    const files = stringsdataFiles(join(intermediates, target.build));
    if (!files.length) {
      console.error(`No .stringsdata for ${relative(root, target.catalog)} under ${relative(root, join(intermediates, target.build))}: build the app first.`);
      process.exit(2);
    }
    const keys = extractedKeys(files);
    total += keys.size;
    const current = readFileSync(target.catalog, 'utf8');
    const next = serialize(merge(JSON.parse(current), keys)) + '\n';
    if (next === current) continue;
    if (check) stale.push(relative(root, target.catalog));
    else writeFileSync(target.catalog, next);
  }
  if (stale.length) {
    console.error(`Stale String Catalogs (run node Tools/strings/sync.mjs after an app build):\n${stale.join('\n')}`);
    process.exit(1);
  }
  console.log(`${check ? 'Checked' : 'Synced'} ${total} keys.`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
