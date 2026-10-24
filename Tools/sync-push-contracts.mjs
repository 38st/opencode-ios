// Copies the contract files the app reads at run time into OCPushCore's resources. The Swift
// test bundledContractsMatchServerContractsByteForByte fails when a copy differs.
//   node Tools/sync-push-contracts.mjs          copy
//   node Tools/sync-push-contracts.mjs --check  exit 1 if a copy differs
import { copyFile, mkdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const files = ['constants.json', 'risk-rules.json'];
export const source = path.join(repository, 'server/contracts');
export const target = path.join(repository, 'Packages/OpencodeKit/Sources/OCPushCore/Resources/Contracts');

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const check = process.argv.includes('--check');
  let stale = 0;
  await mkdir(target, { recursive: true });
  for (const name of files) {
    if (check) {
      const [a, b] = await Promise.all([readFile(path.join(source, name)), readFile(path.join(target, name)).catch(() => Buffer.alloc(0))]);
      if (!a.equals(b)) { stale++; console.error(`stale: ${path.relative(repository, path.join(target, name))}`); }
    } else await copyFile(path.join(source, name), path.join(target, name));
  }
  if (stale) process.exit(1);
  console.log(check ? 'OCPushCore contract resources are current' : `copied ${files.length} files into ${path.relative(repository, target)}`);
}
