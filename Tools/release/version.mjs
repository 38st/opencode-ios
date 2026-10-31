// Reads and changes Config/Version.xcconfig, the single source of the version and build number.
//   node Tools/release/version.mjs                    # prints "0.1.0 (1)"
//   node Tools/release/version.mjs --build 42         # sets the build number
//   node Tools/release/version.mjs --next-build       # adds one to the build number
//   node Tools/release/version.mjs --version 1.2.0    # sets the version
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';

export const VERSION_FILE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../Config/Version.xcconfig');
const VERSION = /^\d+\.\d+(\.\d+)?$/;
const BUILD = /^[1-9]\d{0,8}$/;

export function parseVersion(text) {
  const marketing = text.match(/^MARKETING_VERSION = (\S+)$/m)?.[1];
  const build = text.match(/^CURRENT_PROJECT_VERSION = (\S+)$/m)?.[1];
  if (!marketing || !VERSION.test(marketing)) throw new Error('MARKETING_VERSION must be like 1.2 or 1.2.3');
  if (!build || !BUILD.test(build)) throw new Error('CURRENT_PROJECT_VERSION must be a positive integer');
  return { marketing, build: Number(build) };
}

export function withVersion(text, { marketing, build }) {
  if (marketing !== undefined && !VERSION.test(marketing)) throw new Error(`Invalid version: ${marketing}`);
  if (build !== undefined && !BUILD.test(String(build))) throw new Error(`Invalid build number: ${build}`);
  let output = text;
  if (marketing !== undefined) output = output.replace(/^MARKETING_VERSION = \S+$/m, `MARKETING_VERSION = ${marketing}`);
  if (build !== undefined) output = output.replace(/^CURRENT_PROJECT_VERSION = \S+$/m, `CURRENT_PROJECT_VERSION = ${build}`);
  parseVersion(output);
  return output;
}

export const describe = ({ marketing, build }) => `${marketing} (${build})`;

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const { values } = parseArgs({ options: { build: { type: 'string' }, 'next-build': { type: 'boolean' }, version: { type: 'string' } } });
  const text = await readFile(VERSION_FILE, 'utf8');
  const current = parseVersion(text);
  const build = values['next-build'] ? current.build + 1 : values.build;
  if (build !== undefined || values.version !== undefined) {
    const updated = withVersion(text, { marketing: values.version, build });
    await writeFile(VERSION_FILE, updated);
    console.log(describe(parseVersion(updated)));
  } else {
    console.log(describe(current));
  }
}
