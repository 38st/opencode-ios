import { access, mkdir, realpath, writeFile, rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import path from 'node:path';
import { repository } from '../opencode-sandbox/index.mjs';
import { run } from '../opencode-sandbox/process.mjs';

export async function setupBrowser() {
  const prefix = path.join(repository, '.build/design-tools');
  process.env.PLAYWRIGHT_BROWSERS_PATH = path.join(repository, '.build/playwright');
  const cli = path.join(prefix, 'node_modules/playwright/cli.js');
  try { await access(cli); }
  catch {
    const npm = await realpath(path.join(path.dirname(process.execPath), 'npm'));
    await run(process.execPath, [npm, 'install', '--prefix', prefix, '--cache', path.join(prefix, 'npm-cache'),
      '--ignore-scripts', '--no-audit', '--no-fund', '--save-exact', 'playwright@1.56.1']);
  }
  // Use Playwright's pinned browser URL and install location. macOS ditto avoids
  // Node 26's stalled zip extraction, and preserves executable permissions.
  const plan = await run(process.execPath, [cli, 'install', '--dry-run', 'chromium']);
  const directory = plan.match(/Install location:\s+([^\n]+)/)?.[1];
  const url = plan.match(/Download url:\s+(https:[^\n]+)/)?.[1];
  if (!directory?.startsWith(process.env.PLAYWRIGHT_BROWSERS_PATH + '/') || !url) throw new Error('Unexpected Playwright browser install plan');
  const executablePath = path.join(directory, 'chrome-mac/Chromium.app/Contents/MacOS/Chromium');
  try { await access(executablePath); }
  catch {
    await mkdir(directory, { recursive: true });
    const zip = path.join(process.env.PLAYWRIGHT_BROWSERS_PATH, 'chromium-download.zip');
    const response = await fetch(url, { signal: AbortSignal.timeout(180000) });
    if (!response.ok) throw new Error(`Browser download: ${response.status}`);
    await pipeline(Readable.fromWeb(response.body), createWriteStream(zip));
    await run('/usr/bin/ditto', ['-xk', zip, directory]);
    await rm(zip);
    await writeFile(path.join(directory, 'INSTALLATION_COMPLETE'), '');
  }
  const { chromium } = await import(path.join(prefix, 'node_modules/playwright/index.mjs'));
  return chromium.launch({ executablePath });
}
