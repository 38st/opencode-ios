// Keeps web/index.html in step with the constants it shows: the app's display name (project.yml), the
// plugin package (server/contracts/constants.json) and the oldest supported server (ServerInfo.swift).
//   node Tools/onboarding/sync.mjs           # rewrite the page
//   node Tools/onboarding/sync.mjs --check   # exit 1 if the page is out of date
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const read = relative => readFile(path.join(root, relative), 'utf8');
const escape = text => text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export async function constants() {
  const project = await read('project.yml');
  const contract = JSON.parse(await read('server/contracts/constants.json'));
  const server = await read('Packages/OpencodeKit/Sources/OCModels/ServerInfo.swift');
  const name = project.match(/^\s+CFBundleDisplayName: (.+)$/m)?.[1]?.trim();
  const minimum = server.match(/static let minimumVersion = "([^"]+)"/)?.[1];
  if (!name || !minimum) throw new Error('A constant is missing from project.yml or ServerInfo.swift');
  return { 'app-name': name, 'plugin-install': `opencode plugin add ${contract.names.package}`, 'minimum-version': minimum };
}

export function render(page, values) {
  const output = page.replace(/(<(\w+)[^>]*\sdata-constant="([\w-]+)"[^>]*>)([^<]*)(<\/\2>)/g, (match, open, _tag, key, _text, close) => {
    if (!(key in values)) throw new Error(`Unknown constant ${key}`);
    return open + escape(values[key]) + close;
  });
  return output.replace(/<title>Pair your phone · [^<]*<\/title>/, () => `<title>Pair your phone · ${escape(values['app-name'] ?? '')}</title>`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const file = path.join(root, 'web/index.html');
  const page = await readFile(file, 'utf8');
  const updated = render(page, await constants());
  if (process.argv.includes('--check')) {
    if (updated !== page) { console.error('web/index.html is out of date: run node Tools/onboarding/sync.mjs'); process.exit(1); }
    console.log('web/index.html matches its constants');
  } else if (updated !== page) {
    await writeFile(file, updated);
    console.log('Updated web/index.html');
  }
}
