import { readFile } from "node:fs/promises";
import { expect, test } from "vitest";
import { files } from "../scripts/sync-contracts.ts";

// The package is published without server/contracts, so it carries a copy. Refresh it with
// `npm run sync-contracts`.
test("the vendored contracts are byte-identical to server/contracts", async () => {
  const names = await files();
  expect(names.length).toBeGreaterThan(10);
  for (const name of names) {
    const [source, copy] = await Promise.all([
      readFile(new URL(`../../contracts/${name}`, import.meta.url)),
      readFile(new URL(`../contracts/${name}`, import.meta.url)).catch(() => Buffer.alloc(0)),
    ]);
    expect(copy.equals(source), `contracts/${name} differs; run npm run sync-contracts`).toBe(true);
  }
});
