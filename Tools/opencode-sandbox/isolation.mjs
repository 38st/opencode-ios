import { readdir, lstat, writeFile, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { onShutdown, sandboxGroups, enforcementReport } from './process.mjs';
import { openWriters, attribute } from './attribution.mjs';

const roots = ['.config/opencode', '.local/share/opencode', '.local/state/opencode', '.cache/opencode', 'Library/LaunchAgents'];
export async function snapshot(home = os.homedir()) {
  const result = {};
  async function walk(file, depth) {
    const stat = await lstat(file, { bigint: true });
    const entries = [{ path: file, mtime_ns: stat.mtimeNs.toString(), directory: stat.isDirectory() }];
    if (stat.isDirectory() && depth < 2) {
      for (const name of (await readdir(file)).sort()) {
        try { entries.push(...await walk(path.join(file, name), depth + 1)); }
        catch (error) { if (error.code !== 'ENOENT') throw error; }
      }
    }
    return entries;
  }
  for (const relative of roots) {
    const file = path.join(home, relative);
    try { result[file] = await walk(file, 0); }
    catch (error) { if (error.code === 'ENOENT') result[file] = null; else throw error; }
  }
  return result;
}

export function compare(before, after) {
  const flatten = value => new Map(Object.entries(value).flatMap(([root, rows]) => rows ?? [{ path: root, mtime_ns: null }]).map(row => [row.path, row.mtime_ns]));
  const a = flatten(before), b = flatten(after);
  return [...new Set([...a.keys(), ...b.keys()])].sort().filter(key => a.get(key) !== b.get(key)).map(key => ({ path: key, before: a.get(key) ?? null, after: b.get(key) ?? null }));
}

export async function audit(directory, action, { home = os.homedir() } = {}) {
  await mkdir(directory, { recursive: true });
  const before = await snapshot(home);
  await writeFile(path.join(directory, 'before.json'), JSON.stringify(before, null, 2) + '\n');
  let previous = before, previousWriters = await openWriters(home), previousTime = Date.now();
  const observed = [];
  let pending = Promise.resolve(), samplingError, finished;
  const sample = async () => {
    const [current, writers] = await Promise.all([snapshot(home), openWriters(home)]);
    const time = Date.now();
    const changes = compare(previous, current);
    const directories = new Set([...Object.values(previous), ...Object.values(current)].flatMap(rows => rows ?? []).filter(row => row.directory).map(row => row.path));
    for (const change of changes) {
      const candidates = [...previousWriters, ...writers].filter(writer => writer.path === change.path ||
        (directories.has(change.path) && writer.path.startsWith(change.path + '/') && changes.some(item => item.path === writer.path)))
        .map(writer => ({ ...writer, viaPath: writer.path, path: change.path }));
      const evidence = candidates.map(writer => ({ ...writer, observedFrom: previousTime, observedTo: time,
        sandboxed: sandboxGroups.has(writer.pgid) }));
      observed.push({ ...change, detectedAt: new Date(time).toISOString(),
        changeTime: change.after ? new Date(Number(BigInt(change.after) / 1000000n)).toISOString() : null,
        ...attribute(change, evidence) });
    }
    previous = current; previousWriters = writers; previousTime = time;
  };
  // Serial sampling avoids overlapping lsof processes and captures writers that
  // close their descriptors before the final before/after comparison.
  let sampling = false;
  const timer = setInterval(() => {
    if (sampling) return;
    sampling = true;
    pending = sample().catch(error => { samplingError = error; }).finally(() => { sampling = false; });
  }, 500);
  const finish = () => finished ??= (async () => {
    clearInterval(timer); await pending; await sample();
    const after = previous, changes = compare(before, after);
    const enforcement = enforcementReport();
    for (const item of observed) {
      Object.assign(item, attribute(item, item.writers, sandboxGroups, enforcement.verified));
    }
    const failures = observed.filter(item => item.severity === 'failure');
    await writeFile(path.join(directory, 'after.json'), JSON.stringify(after, null, 2) + '\n');
    await writeFile(path.join(directory, 'comparison.json'), JSON.stringify({ unchanged: changes.length === 0,
      changes, observations: observed, enforcement, failures: failures.length + (enforcement.verified ? 0 : 1), samplingError: samplingError?.message }, null, 2) + '\n');
    for (const item of observed.filter(item => item.severity === 'warning')) {
      const writer = item.writers[0];
      const attribution = item.attribution === 'external' ? `external ${writer.name} (PID ${writer.pid}, PGID ${writer.pgid})` : 'writer unattributed; sandbox enforcement verified';
      console.warn(`Isolation warning: ${item.path} changed at ${item.changeTime ?? item.detectedAt}; ${attribution}`);
    }
    if (samplingError) throw samplingError;
    if (!enforcement.verified) throw new Error(`Sandbox enforcement is not verified for every launch; see ${directory}`);
    if (failures.length) throw new Error(`Isolation audit found ${failures.length} changes attributed to sandbox processes; see ${directory}`);
  })();
  const removeHook = onShutdown(finish);
  try { return await action(); }
  finally { removeHook(); await finish(); }
}
