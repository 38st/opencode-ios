import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { sandboxGroups, refreshSandboxGroups } from './process.mjs';
import { protectedRoots } from './profile.mjs';

const exec = promisify(execFile);
export function parseLsof(output) {
  const files = [];
  let process, file;
  for (const line of output.split('\n')) {
    const value = line.slice(1);
    switch (line[0]) {
      case 'p': process = { pid: Number(value) }; break;
      case 'g': if (process) process.pgid = Number(value); break;
      case 'c': if (process) process.name = value; break;
      case 'f': file = { ...process, descriptor: value }; break;
      case 'a': if (file) file.access = value; break;
      case 'n': if (file) files.push({ ...file, path: value.replace(/ \(deleted\)$/, '') }); break;
    }
  }
  return files;
}

export async function openWriters(home) {
  refreshSandboxGroups();
  // Inspect descriptors rather than reading the user's data. Include process groups
  // and writable access; a process merely reading a database cannot explain a write.
  let output;
  try { output = (await exec('/usr/sbin/lsof', ['-nP', '-Fpcgfan'], { maxBuffer: 32 * 1024 * 1024 })).stdout; }
  catch (error) {
    if (error.code !== 1 || error.stderr?.trim()) throw error;
    output = error.stdout;
  }
  const roots = protectedRoots(home);
  return parseLsof(output).filter(file => ['w', 'u'].includes(file.access) &&
    roots.some(root => file.path === root || file.path.startsWith(root + '/')));
}

export function attribute(change, observations, groups = sandboxGroups, enforcementVerified = false) {
  const writers = observations.filter(item => item.path === change.path);
  if (writers.some(item => groups.has(item.pgid) || item.sandboxed)) return { attribution: 'sandbox', severity: 'failure', writers };
  // More than one writer, missing group identity, or no contemporaneous writable
  // descriptor is ambiguous. Do not silently bless a write based on a process name.
  const identities = new Set(writers.map(item => `${item.pid}:${item.pgid}`));
  if (identities.size !== 1 || writers.some(item => !item.pgid)) return { attribution: 'unknown', severity: enforcementVerified ? 'warning' : 'failure', writers };
  return { attribution: 'external', severity: 'warning', writers };
}
