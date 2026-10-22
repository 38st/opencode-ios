import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { lstatSync, readFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const escape = text => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

test('repository files contain no home directory paths', () => {
  // Example paths in docs and screenshots live under /Users/Shared. Windows paths such as
  // C:/Users/test in the reference file URI tests are not home directories on this Mac.
  const patterns = [/(?<![A-Za-z]:)\/Users\/(?!Shared\b)[^/\s"'`<>\\]+/];
  const home = os.homedir();
  if (home.split('/').filter(Boolean).length > 1) patterns.push(new RegExp(`${escape(home)}(?![\\w.-])`));
  // Untracked files that are not ignored are searched too, so a path fails before it is committed.
  const files = execFileSync('git', ['ls-files', '-z', '--cached', '--others', '--exclude-standard'], { cwd: repository, encoding: 'utf8' }).split('\0').filter(Boolean);
  const leaks = files.filter(file => {
    const absolute = path.join(repository, file);
    try { if (!lstatSync(absolute).isFile()) return false; } catch { return false; }
    // Latin-1 maps every byte to one character, so binary files are searched too.
    const text = readFileSync(absolute).toString('latin1');
    return patterns.some(pattern => pattern.test(text));
  });
  assert.deepEqual(leaks, []);
});
