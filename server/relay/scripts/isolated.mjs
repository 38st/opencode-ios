// Runs a command with wrangler's state confined to this package, so nothing it does reaches the
// account's own wrangler login, metrics preference, dev registry or logs.
//   node scripts/isolated.mjs wrangler dev
//   node scripts/isolated.mjs vitest run --config vitest.workers.config.ts
// Wrangler's global configuration lives in getGlobalConfigPath(): ~/.wrangler if it exists, else
// $XDG_CONFIG_HOME/.wrangler (macOS: ~/Library/Preferences/.wrangler). Both derive from HOME and
// XDG_CONFIG_HOME, so pointing those at a scratch directory keeps every write local. Telemetry is
// off through WRANGLER_SEND_METRICS, and the account's Cloudflare credentials are not passed on.
import { spawn } from 'node:child_process';
import { lstat, mkdir, readdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const relayDirectory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

/** The directories the account's wrangler keeps its state in; a guard checks they never change. */
export const wranglerHomes = (home = os.homedir()) => [path.join(home, '.wrangler'), path.join(home, 'Library/Preferences/.wrangler'), path.join(home, '.config/.wrangler')];

/** Paths and nanosecond mtimes, two levels deep, of every existing wrangler home directory. */
export async function snapshotWranglerHomes(home = os.homedir()) {
  const result = {};
  for (const root of wranglerHomes(home)) {
    const walk = async (file, depth) => {
      const stat = await lstat(file, { bigint: true });
      result[file] = stat.mtimeNs.toString();
      if (stat.isDirectory() && depth < 2) for (const name of await readdir(file)) await walk(path.join(file, name), depth + 1).catch(() => {});
    };
    await walk(root, 0).catch(() => { result[root] = null; });
  }
  return result;
}

/** The entries whose presence or mtime differ between two snapshots. */
export function changedWranglerHomes(before, after) {
  return [...new Set([...Object.keys(before), ...Object.keys(after)])].filter(key => before[key] !== after[key]).sort();
}

/** The environment for an isolated wrangler or workerd run, with its state under `stateDirectory`. */
export async function isolatedEnvironment(stateDirectory, base = process.env) {
  const home = path.join(stateDirectory, 'home');
  await mkdir(path.join(home, 'config'), { recursive: true });
  await mkdir(path.join(home, 'cache'), { recursive: true });
  const env = { ...base };
  for (const name of Object.keys(env)) if (/^(CLOUDFLARE_|CF_|WRANGLER_)/.test(name)) delete env[name];
  return {
    ...env,
    HOME: home,
    XDG_CONFIG_HOME: path.join(home, 'config'),
    XDG_CACHE_HOME: path.join(home, 'cache'),
    XDG_STATE_HOME: path.join(home, 'state'),
    WRANGLER_SEND_METRICS: 'false',
    WRANGLER_LOG_PATH: path.join(stateDirectory, 'logs'),
    WRANGLER_HIDE_BANNER: 'true',
    NO_COLOR: '1',
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [command, ...args] = process.argv.slice(2);
  if (!command) {
    console.error('usage: node scripts/isolated.mjs <command> [args...]');
    process.exit(2);
  }
  const before = await snapshotWranglerHomes();
  const env = await isolatedEnvironment(path.join(relayDirectory, '.wrangler'));
  const binary = path.join(relayDirectory, 'node_modules/.bin', command);
  const child = spawn(binary, args, { cwd: relayDirectory, env, stdio: 'inherit' });
  const forward = signal => child.kill(signal);
  for (const signal of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(signal, forward);
  child.on('exit', async (code, signal) => {
    const changed = changedWranglerHomes(before, await snapshotWranglerHomes());
    if (changed.length) {
      console.error(`The account's wrangler state changed during the run: ${changed.join(', ')}`);
      process.exit(1);
    }
    process.exit(code ?? (signal ? 1 : 0));
  });
}
