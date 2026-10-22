import path from 'node:path';
import { writeFile } from 'node:fs/promises';
import { Capture } from '../fixture-recorder/transport.mjs';

export async function captureComposer({ server, browser, output, manifest, sizes }) {
  const api = new Capture(server);
  const session = (await api.request('POST', '/api/session', {
    title: 'Composer reference', location: { directory: server.project }, agent: 'reviewer',
    model: { providerID: 'mock', id: 'mock-vision', variant: 'careful' },
  })).data.id;
  const base = `${server.baseURL}/server/${Buffer.from(server.baseURL).toString('base64url')}`;
  for (const [width, height] of sizes) for (const mode of ['light', 'dark']) {
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: mode, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const capture = async name => {
      await page.evaluate(() => document.fonts.ready);
      const file = `${name}-${mode}-${width}x${height}.png`;
      await page.screenshot({ path: path.join(output, file), animations: 'disabled' });
      manifest.captures.push({ name, mode, width, height, file, route: new URL(page.url()).pathname });
      console.log(`Captured ${file}`);
    };
    try {
      await page.goto(server.baseURL);
      await page.getByRole('button', { name: 'Use password', exact: true }).click();
      await page.locator('input[type=password]').fill(server.password);
      await page.getByRole('button', { name: 'Connect', exact: true }).click();
      await page.getByText('Composer reference', { exact: true }).first().waitFor();
      await page.goto(`${server.baseURL}/settings`);
      await page.locator('[data-action=settings-show-custom-agents] [data-slot=switch-control]').click();
      await page.goto(`${base}/session/${session}`);
      const editor = page.locator('[data-component=composer-editor]');
      await editor.waitFor();
      await page.locator('[data-action=composer-model]').waitFor();
      // Custom fixture models have epoch-zero release dates. Enable them through
      // the official manager so the comparison includes actual model rows.
      await page.locator('[data-action=composer-model]').click();
      await page.getByText('Manage models', { exact: true }).click();
      for (const name of ['Mock 1', 'Mock Vision']) {
        const toggle = page.getByRole('switch', { name, exact: true });
        await toggle.waitFor();
        if (!(await toggle.isChecked())) await toggle.locator('..').locator('[data-slot=switch-control]').click();
      }
      await page.goto(`${base}/session/${session}`); await editor.waitFor();
      await capture('composer-idle');
      await editor.fill('Review the implementation and preserve the existing behavior.');
      await capture('composer-typing');
      await editor.fill('@');
      await page.locator('[data-component=composer-suggestions]').waitFor();
      await capture('composer-context');
      await editor.fill('/');
      await page.locator('[data-component=composer-suggestions]').waitFor();
      await capture('composer-commands');
      await editor.fill('');
      await page.locator('[data-action=composer-model]').click();
      await page.getByPlaceholder('Search models').waitFor();
      await capture('composer-model-picker');
      await page.keyboard.press('Escape');
      // Navigate to close native mobile drawers as well as desktop popovers.
      await page.goto(`${base}/session/${session}`); await editor.waitFor();
      await page.getByRole('button', { name: 'Choose model variant', exact: true }).click();
      await capture('composer-variant-picker');
      await page.goto(`${base}/session/${session}`); await editor.waitFor();
      await page.getByRole('button', { name: 'Choose agent', exact: true }).click();
      await capture('composer-agent-picker');
      await page.goto(`${base}/session/${session}`); await editor.waitFor();
      await editor.fill(''); await editor.pressSequentially('!');
      await page.locator('[data-action=composer-exit-shell]').waitFor();
      await editor.fill('git status');
      await capture('composer-shell');
      await page.keyboard.press('Escape'); await editor.fill('');
      const item = (await api.request('POST', `/api/session/${session}/prompt`, { text: 'Review the regression tests', delivery: 'queue', resume: false })).data;
      await page.getByText('Review the regression tests', { exact: true }).first().waitFor();
      await capture('composer-queue');
      await api.request('DELETE', `/api/session/${session}/inbox/${item.id}`);
      await page.keyboard.press('Meta+n');
      await page.locator('[data-component=new-session]').waitFor();
      await capture('composer-new-session');
    } catch (error) {
      await page.screenshot({ path: path.join(output, `composer-failure-${mode}-${width}.png`) });
      await writeFile(path.join(output, `composer-failure-${mode}-${width}.txt`), (await page.locator('body').innerText()).replaceAll(server.password, '[REDACTED]'));
      throw error;
    } finally { await context.close(); }
  }
}
