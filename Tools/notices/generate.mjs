#!/usr/bin/env node
// One source for the licence notices: OCDesign's Resources/Licenses/acknowledgements.json. The app's
// Acknowledgements screen reads that file; this script writes the component table in THIRD_PARTY_NOTICES.md
// from it and copies each licence text next to it. `--check` changes nothing and fails when anything drifted:
// the table, a missing licence text, or a version that no longer matches Package.resolved, an npm lockfile
// or the grammar manifest.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const licenses = join(root, 'Packages/OpencodeKit/Sources/OCDesign/Resources/Licenses');
const notices = join(root, 'THIRD_PARTY_NOTICES.md');
const start = '<!-- acknowledgements:start -->';
const end = '<!-- acknowledgements:end -->';

export function loadAcknowledgements(dir = licenses) {
  return JSON.parse(readFileSync(join(dir, 'acknowledgements.json'), 'utf8'));
}

const cell = (text) => String(text).replaceAll('|', '\\|');

export function renderTable(doc) {
  const lines = [start, '', 'Generated from `Packages/OpencodeKit/Sources/OCDesign/Resources/Licenses/acknowledgements.json` by',
    '`node Tools/notices/generate.mjs`; the app\'s Acknowledgements screen shows the same list and licence texts.', ''];
  for (const section of doc.sections) {
    lines.push(`### ${section.title}`, '', '| Component | Version | Licence | Copyright |', '| --- | --- | --- | --- |');
    for (const item of section.items) {
      lines.push(`| [${cell(item.name)}](${item.url}) | ${cell(item.version)} | ${cell(item.license)} | ${cell(item.copyright)} |`);
    }
    lines.push('');
  }
  lines.push(end);
  return lines.join('\n');
}

export function replaceTable(markdown, table) {
  const from = markdown.indexOf(start);
  const to = markdown.indexOf(end);
  if (from < 0 || to < from) throw new Error(`THIRD_PARTY_NOTICES.md has no ${start} … ${end} block`);
  return markdown.slice(0, from) + table + markdown.slice(to + end.length);
}

// Where each licence text comes from when it is (re)copied. Assets' texts are maintained by hand.
function licenseSource(item) {
  if (item.package) {
    const checkout = join(root, '.build/DerivedData/SourcePackages/checkouts', checkoutName(item.package));
    for (const name of ['LICENSE', 'LICENSE.txt', 'LICENSE.md', 'COPYING']) {
      if (existsSync(join(checkout, name))) return join(checkout, name);
    }
    return null;
  }
  if (item.grammar) return join(root, 'Packages/OpencodeKit/Grammars', item.grammar, 'LICENSE');
  if (item.npm) return join(root, item.npm, 'node_modules', item.name, 'LICENSE');
  return null;
}

// Apache-2.0 asks redistributions to carry the project's NOTICE file, so it follows the licence text.
function licenseText(source) {
  const notice = join(dirname(source), 'NOTICE.txt');
  const text = readFileSync(source, 'utf8');
  return existsSync(notice) ? `${text.trimEnd()}\n\n---\n\n${readFileSync(notice, 'utf8')}` : text;
}

function checkoutName(identity) {
  return { 'grdb.swift': 'GRDB.swift', swiftterm: 'SwiftTerm' }[identity] ?? identity;
}

export function versionProblems(doc) {
  const problems = [];
  const resolved = JSON.parse(readFileSync(join(root, 'Packages/OpencodeKit/Package.resolved'), 'utf8'));
  const pins = new Map(resolved.pins.map((pin) => [pin.identity, pin.state.version]));
  const grammars = new Map(JSON.parse(readFileSync(join(root, 'Tools/grammars/manifest.json'), 'utf8'))
    .map((grammar) => [grammar.name, grammar]));
  const locks = new Map();
  for (const item of doc.sections.flatMap((section) => section.items)) {
    if (item.package && pins.get(item.package) !== item.version) {
      problems.push(`${item.name}: ${item.version} listed, Package.resolved pins ${pins.get(item.package) ?? 'nothing'}`);
    }
    if (item.grammar) {
      const grammar = grammars.get(item.grammar);
      const expected = grammar?.tag.startsWith('v') ? grammar.tag.slice(1) : grammar?.revision.slice(0, 7);
      if (expected !== item.version) problems.push(`${item.name}: ${item.version} listed, the manifest has ${expected}`);
    }
    if (item.npm) {
      if (!locks.has(item.npm)) locks.set(item.npm, JSON.parse(readFileSync(join(root, item.npm, 'package-lock.json'), 'utf8')));
      const locked = locks.get(item.npm).packages[`node_modules/${item.name}`];
      if (locked?.version !== item.version || locked?.dev) {
        problems.push(`${item.name}: ${item.version} listed, ${item.npm} locks ${locked?.version ?? 'nothing'}`);
      }
    }
    if (!existsSync(join(licenses, item.licenseFile))) problems.push(`${item.name}: ${item.licenseFile} is missing`);
  }
  // Every runtime npm package must be listed, so a new dependency cannot ship without a notice.
  const listed = new Set(doc.sections.flatMap((section) => section.items).filter((item) => item.npm).map((item) => `${item.npm}:${item.name}`));
  for (const dir of ['server/plugin', 'server/relay']) {
    const lock = locks.get(dir) ?? JSON.parse(readFileSync(join(root, dir, 'package-lock.json'), 'utf8'));
    for (const [path, entry] of Object.entries(lock.packages)) {
      if (!path || entry.dev) continue;
      const name = path.replace(/^.*node_modules\//, '');
      if (!listed.has(`${dir}:${name}`)) problems.push(`${dir} ships ${name} ${entry.version} without a notice`);
    }
  }
  return problems;
}

function main() {
  const check = process.argv.includes('--check');
  const doc = loadAcknowledgements();
  const markdown = readFileSync(notices, 'utf8');
  const updated = replaceTable(markdown, renderTable(doc));
  if (!check) {
    for (const item of doc.sections.flatMap((section) => section.items)) {
      const source = licenseSource(item);
      if (source && existsSync(source)) writeFileSync(join(licenses, item.licenseFile), licenseText(source));
    }
    writeFileSync(notices, updated);
  }
  const problems = versionProblems(doc);
  if (check && updated !== markdown) problems.push('THIRD_PARTY_NOTICES.md is out of date: run node Tools/notices/generate.mjs');
  if (problems.length) {
    console.error(problems.join('\n'));
    process.exit(1);
  }
  console.log(check ? 'Notices are up to date.' : 'Notices written.');
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main();
