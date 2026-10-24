// Copies the contract code and data into this package, which is published without its parent
// directory. test/contracts-copy.test.ts fails when the copy differs from server/contracts.
//   node scripts/sync-contracts.ts
import { copyFile, mkdir, readdir, rm } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const source = new URL("../../contracts/", import.meta.url);
const target = new URL("../contracts/", import.meta.url);
export const files = async (): Promise<string[]> => [
  "constants.json",
  "risk-rules.json",
  ...(await readdir(new URL("src/", source))).filter((name) => name.endsWith(".ts")).sort().map((name) => `src/${name}`),
];

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  await rm(target, { recursive: true, force: true });
  await mkdir(new URL("src/", target), { recursive: true });
  for (const file of await files()) await copyFile(new URL(file, source), new URL(file, target));
  console.log(`copied ${(await files()).length} contract files into server/plugin/contracts`);
}
