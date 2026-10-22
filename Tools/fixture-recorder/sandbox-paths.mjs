import { realpathSync } from 'node:fs';

// Published fixtures must not reveal where the checkout lives, so every sandbox
// run root is rewritten to this fixed path before a fixture is written.
export const PUBLISHED_ROOT = '/sandbox';

const pathCharacter = /[\w.-]/;
const encodings = [text => text, text => text.replaceAll('/', '\\/'), encodeURI, encodeURIComponent];

// Plain, JSON-escaped and URL-encoded spellings of each root, also with symlinks resolved.
// Longest first, so /private/var/root is replaced before /var/root can match inside it.
function spellings(roots) {
  const paths = new Set();
  for (const root of roots) {
    paths.add(root);
    try { paths.add(realpathSync(root)); } catch {}
  }
  const pairs = new Map();
  for (const root of paths) for (const encode of encodings) pairs.set(encode(root), encode(PUBLISHED_ROOT));
  return [...pairs].map(([from, to]) => [Buffer.from(from), Buffer.from(to)]).sort((a, b) => b[0].length - a[0].length);
}

// Replaces whole path components only, so a longer name that starts with the root stays as it is.
function replace(bytes, from, to) {
  const parts = [];
  let start = 0, index = bytes.indexOf(from);
  while (index !== -1) {
    const end = index + from.length;
    const whole = !(end < bytes.length && pathCharacter.test(String.fromCharCode(bytes[end])));
    if (whole) { parts.push(bytes.subarray(start, index), to); start = end; }
    index = bytes.indexOf(from, whole ? end : index + 1);
  }
  if (!parts.length) return bytes;
  parts.push(bytes.subarray(start));
  return Buffer.concat(parts);
}

// Returns the bytes with every sandbox root replaced and every other byte unchanged.
export function relocate(data, roots) {
  let bytes = Buffer.from(data);
  for (const [from, to] of spellings(roots)) bytes = replace(bytes, from, to);
  return bytes;
}
