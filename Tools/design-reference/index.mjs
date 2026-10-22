#!/usr/bin/env node
import assert from 'node:assert/strict';
import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import { repository, resolveVersion, startSandbox } from '../opencode-sandbox/index.mjs';
import { audit } from '../opencode-sandbox/isolation.mjs';
import { startMock } from '../mock-llm/server.mjs';
import { setupBrowser } from './setup.mjs';
import { seed } from './seed.mjs';
import { configureComposer } from '../ui-smoke/composer-config.mjs';
import { captureComposer } from './composer.mjs';
import { captureReview } from './review.mjs';
import { configureReview } from '../review-fixture/index.mjs';

const { values } = parseArgs({ options: { version: { type: 'string' }, 'composer-only': { type: 'boolean' }, 'review-only': { type: 'boolean' } } });
const version = await resolveVersion(values.version);
const output = path.join(repository, '.build/design-reference');
await mkdir(output, { recursive: true });
const sizes = [[1440, 900], [1180, 820], [820, 1180], [393, 852]];
const manifest = { version, capturedAt: new Date().toISOString(), source: 'The web UI served by the sandbox V2 server; no clone code is executed.', captures: [] };
await audit(path.join(output, 'isolation'), async () => {
  const mock = await startMock();
  let server, browser;
  try {
    server = await startSandbox({ version, mockURL: mock.url, configure: values['review-only'] ? configureReview : values['composer-only'] ? configureComposer : undefined });
    const sessions = values['composer-only'] || values['review-only'] ? {} : await seed(server, mock);
    browser = await setupBrowser();
    if (!values['composer-only'] && !values['review-only']) for (const [width, height] of sizes) for (const mode of ['light', 'dark']) {
      const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: mode, reducedMotion: 'reduce' });
      const page = await context.newPage();
      const capture = async name => {
        await page.evaluate(() => document.fonts.ready);
        const file = `${name}-${mode}-${width}x${height}.png`;
        await page.screenshot({ path: path.join(output, file), animations: 'disabled' });
        manifest.captures.push({ name, mode, width, height, file, route: new URL(page.url()).pathname });
        console.log(`Captured ${file}`);
      };
      const gotoSession = async id => {
        await page.goto(`${server.baseURL}/server/${Buffer.from(server.baseURL).toString('base64url')}/session/${id}`);
        await page.getByText(id === sessions.timeline ? 'Design system' : id === sessions.permission ? 'Permission request' : 'Question', { exact: true }).first().waitFor({ state: 'visible' });
        await page.waitForTimeout(600);
      };
      try {
        await page.goto(server.baseURL);
        await page.getByRole('button', { name: 'Use password', exact: true }).waitFor();
        await capture('connect-pairing');
        await page.getByRole('button', { name: 'Use password', exact: true }).click();
        await capture('connect-password');
        await page.locator('input[type=password]').fill(server.password);
        await page.getByRole('button', { name: 'Connect', exact: true }).click();
        await page.getByText('Design system', { exact: true }).waitFor();
        if (width === 1440) {
          const tokens = await page.evaluate(() => {
            const style = getComputedStyle(document.documentElement);
            return Object.fromEntries(Array.from(style).filter(name => name.startsWith('--')).map(name => [name.slice(2), style.getPropertyValue(name).trim()]));
          });
          await writeFile(path.join(output, `computed-tokens-${mode}.json`), JSON.stringify(tokens, null, 2) + '\n');
        }
        await capture('home');
        await capture('session-list');
        await gotoSession(sessions.timeline);
        const tools = page.getByText('Read, Glob, Grep', { exact: true });
        if (await tools.count()) await tools.click();
        await page.getByText('Run the read-glob-grep fixture scenario.', { exact: true }).scrollIntoViewIfNeeded();
        await capture('timeline');
        if (width < 768) await page.getByText('Changes', { exact: true }).click();
        else await page.getByRole('button', { name: 'Toggle review', exact: true }).click();
        await page.getByText('sample.txt', { exact: true }).first().waitFor();
        if (width < 768) await page.getByRole('button', { name: 'Expand all', exact: true }).click();
        await page.getByText('edited fixture line', { exact: true }).first().waitFor({ timeout: 20000 });
        await capture('review');
        await page.goto(server.baseURL);
        await page.getByText('Design system', { exact: true }).filter({ visible: true }).first().waitFor();
        if (width < 768) await page.locator('[data-component=home-projects-dropdown]').click();
        await capture('projects');
        await page.getByRole('button', { name: 'Add project', exact: true }).first().click();
        await page.getByRole('button', { name: 'Select folder', exact: true }).waitFor();
        await capture('open-project');
        await page.getByRole('button', { name: 'Select folder', exact: true }).click();
        await page.goto(server.baseURL);
        await page.getByText('Design system', { exact: true }).filter({ visible: true }).first().waitFor();
        if (width < 768) await page.locator('[data-slot=mobile-tabs-trigger]').click();
        await capture('sidebar');
        await gotoSession(sessions.permission);
        assert.match(await page.locator('body').innerText(), /permission|allow|approve/i);
        await capture('permission');
        await gotoSession(sessions.question);
        await page.getByText('Blue', { exact: true }).waitFor();
        await capture('question');
        await page.goto(`${server.baseURL}/settings`);
        await page.getByText('General', { exact: true }).waitFor();
        await capture('settings');
        await page.goto(`${server.baseURL}/settings?tab=servers`);
        await page.getByText('Connection', { exact: true }).waitFor();
        await capture('settings-server');
      } catch (error) {
        await page.screenshot({ path: path.join(output, `failure-${mode}-${width}.png`) });
        await writeFile(path.join(output, `failure-${mode}-${width}.txt`), (await page.locator('body').innerText()).replaceAll(server.password, '[REDACTED]'));
        throw error;
      } finally { await context.close(); }
    }
    if (!values['composer-only'] && !values['review-only']) {
      await server.stop();
      server = await startSandbox({ version, mockURL: mock.url, configure: configureComposer });
    }
    if (!values['review-only']) {
      await captureComposer({ server, browser, output, manifest, sizes });
      if (!values['composer-only']) {
        await server.stop();
        server = await startSandbox({ version, mockURL: mock.url, configure: configureReview });
      }
    }
    if (!values['composer-only']) await captureReview({ server, mock, browser, output, manifest, sizes });
    await writeFile(path.join(output, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  } finally { await browser?.close(); await server?.stop(); await mock.close(); }
});
console.log(`PASS ${manifest.captures.length} official UI captures, cleanup and isolation`);
