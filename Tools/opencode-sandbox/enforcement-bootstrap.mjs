import { writeFileSync } from 'node:fs';
import { spawn } from 'node:child_process';

const [encoded, command, ...args] = process.argv.slice(2);
const { receipt, canary, ...proof } = JSON.parse(encoded);
let denied = false;
try { writeFileSync(canary, 'This must be denied', { flag: 'wx' }); }
catch (error) {
  if (error.code !== 'EPERM' && error.code !== 'EACCES') throw error;
  denied = true;
}
if (!denied) throw new Error('Sandbox enforcement denied-write check failed; refusing to start server');
writeFileSync(receipt, JSON.stringify({ ...proof, pid: process.pid, deniedWrite: true, verifiedAt: new Date().toISOString() }) + '\n', { flag: 'wx' });
// Seatbelt restrictions are inherited by every descendant, including npx and PTYs.
const child = spawn(command, args, { stdio: 'inherit' });
child.once('error', error => { console.error(error.message); process.exitCode = 1; });
child.once('exit', (code, signal) => { process.exitCode = code ?? (signal ? 1 : 0); });
