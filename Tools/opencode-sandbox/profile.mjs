import os from 'node:os';
import path from 'node:path';
import { realpath } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

export const protectedRoots = (home = os.homedir()) =>
  ['.config/opencode', '.local/share/opencode', '.local/state/opencode', '.cache/opencode', 'Library/LaunchAgents']
    .map(relative => path.join(home, relative));

// Resolve existing ancestors too: the protected directory need not exist yet.
async function canonical(file) {
  try { return await realpath(file); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    const parent = path.dirname(file);
    if (parent === file) throw error;
    return path.join(await canonical(parent), path.basename(file));
  }
}

export async function sandboxProfile(home = os.homedir()) {
  const roots = protectedRoots(home);
  const paths = [...new Set([...roots, ...await Promise.all(roots.map(canonical))])];
  return '(version 1)\n(allow default)\n' + paths.map(file =>
    `(deny file-write* (subpath ${JSON.stringify(file)}))`).join('\n') + '\n';
}

export async function sandboxCommand(command, args, home) {
  if (process.platform !== 'darwin') throw new Error('Sandbox servers require macOS sandbox-exec');
  return { command: '/usr/bin/sandbox-exec', args: ['-p', await sandboxProfile(home), command, ...args] };
}

// The canary is inside the disposable run directory, never the user's data.
// The bootstrap proves denial under this exact profile before it starts npx.
export async function verifiedSandboxCommand(command, args, directory, home = os.homedir(), deniedReads = []) {
  const base = await sandboxCommand(command, args, home);
  const canary = path.join(await canonical(directory), 'enforcement-denied-write');
  const profile = base.args[1] + `(deny file-write* (literal ${JSON.stringify(canary)}))\n` +
    deniedReads.map(file => `(deny file-read* (subpath ${JSON.stringify(path.resolve(file))}))\n(deny file-test-existence (subpath ${JSON.stringify(path.resolve(file))}))\n`).join('');
  const enforcement = { receipt: path.join(directory, 'enforcement.json'), token: randomUUID(),
    profileDigest: createHash('sha256').update(profile).digest('hex'), protectedRoots: protectedRoots(home) };
  return { command: base.command, args: ['-p', profile, process.execPath,
    fileURLToPath(new URL('./enforcement-bootstrap.mjs', import.meta.url)),
    JSON.stringify({ ...enforcement, canary }), command, ...args], enforcement };
}
