import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Reads the reference clone as text only. CI supplies its generated types.ts path.
export function eventNames(types) {
  const union = types.match(/export type V2Event =\s*\n([\s\S]*?)(?=\n\n)/)?.[1];
  assert.ok(union, 'V2Event union is missing');
  const names = [];
  for (const [, name] of union.matchAll(/\|\s*(\w+)/g)) {
    const definition = types.match(new RegExp(`export type ${name} = ([\\s\\S]*?)(?=\\nexport type|$)`))?.[1];
    assert.ok(definition, `Missing ${name}`);
    if (name === 'V2EventRpc') continue; // rpc.* is an intentionally open namespace.
    const type = definition.match(/type:\s*"([^"]+)"/)?.[1];
    assert.ok(type, `Missing discriminator for ${name}`);
    names.push(type);
  }
  return names.sort();
}

export function checkEvents(types, swift) {
  const start = swift.indexOf('static func decode(');
  const end = swift.indexOf('public static let knownTypes', start);
  const decoder = swift.slice(start, end < 0 ? undefined : end);
  const cases = [...decoder.matchAll(/case "([^"]+)"/g)].map(match => match[1]);
  assert.deepEqual([...new Set(cases)].sort(), eventNames(types));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.ok(process.argv[2], 'Usage: node Tools/contract/check-events.mjs /read-only/clone/packages/client/src/promise/generated/types.ts');
  const swift = await readFile(new URL('../../Packages/OpencodeKit/Sources/OCModels/ServerEvent.swift', import.meta.url), 'utf8');
  const types = await readFile(process.argv[2], 'utf8');
  checkEvents(types, swift);
  console.log(`PASS ${eventNames(types).length} fixed V2 events plus rpc.* match the reference union`);
}
