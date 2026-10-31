import path from 'node:path';
import { writeFile } from 'node:fs/promises';
import { Capture } from '../fixture-recorder/transport.mjs';
import { seedReviewRepository } from '../review-fixture/index.mjs';

export async function captureReview({ server, mock, browser, output, manifest, sizes }) {
  const fixture = await seedReviewRepository(server, mock);
  const api = new Capture(server);
  const empty = (await api.request('POST', '/api/session', { title: 'Review sample without changes', location: { directory: fixture.directory }, model: { providerID: 'mock', id: 'mock-1' } })).data.id;
  const base = `${server.baseURL}/server/${Buffer.from(server.baseURL).toString('base64url')}`;
  for (const [width, height] of sizes) for (const mode of ['light', 'dark']) {
    const session = (await api.request('POST', `/api/session/${fixture.session}/fork`, {})).data.id;
    const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: 1, colorScheme: mode, reducedMotion: 'reduce' });
    const page = await context.newPage();
    const mobile = width < 768;
    const capture = async name => {
      await page.evaluate(() => document.fonts.ready);
      const file = `review-${name}-${mode}-${width}x${height}.png`;
      await page.screenshot({ path: path.join(output, file), animations: 'disabled' });
      manifest.captures.push({ name: 'review-' + name, mode, width, height, file, route: new URL(page.url()).pathname });
      console.log(`Captured ${file}`);
    };
    const goto = async id => {
      await page.goto(`${base}/session/${id}`);
      await page.locator('[data-component=composer-editor]').waitFor();
    };
    const panel = () => mobile ? page.locator('[data-component=session-review]') : page.locator('#review-panel');
    const showReview = async () => {
      if (mobile) await page.getByRole('tab', { name: 'Changes', exact: true }).click();
      else if (!(await page.locator('#review-panel').isVisible())) await page.getByRole('button', { name: 'Toggle review', exact: true }).click();
      await panel().waitFor();
    };
    const source = async title => {
      if (!mobile && !(await panel().locator('[data-slot="session-review-v2-sidebar"]').isVisible())) {
        await panel().getByRole('button', { name: 'Toggle file tree', exact: true }).click();
      }
      const current = panel().getByText(/^(Git changes|Branch changes|Last turn changes)$/).filter({ visible: true }).first();
      if ((await current.innerText()) === title) return;
      await current.click();
      await page.getByRole('option', { name: title, exact: true }).click();
    };
    const openChangedFile = async (file, text) => {
      if (mobile) {
        const section = panel().locator(`[data-file="${file}"]`);
        await section.waitFor();
        const collapsed = section.getByRole('button', { expanded: false }).first();
        if (await collapsed.count()) await collapsed.click();
      } else {
        if (!(await panel().locator('[data-slot="session-review-v2-sidebar"]').isVisible())) {
          await panel().getByRole('button', { name: 'Toggle file tree', exact: true }).click();
        }
        await panel().getByText(path.basename(file), { exact: true }).filter({ visible: true }).first().click();
      }
      await panel().getByText(text, { exact: false }).first().waitFor();
    };
    const example = () => openChangedFile('Sources/Example.swift', 'let value = 2');
    try {
      await page.goto(server.baseURL);
      await page.getByRole('button', { name: 'Use password', exact: true }).click();
      await page.locator('input[type=password]').fill(server.password);
      await page.getByRole('button', { name: 'Connect', exact: true }).click();
      await page.getByText('Review sample edits', { exact: true }).first().waitFor();
      await page.goto(`${server.baseURL}/settings`);
      await page.locator('[data-action=settings-show-turn-diffs] [data-slot=switch-control]').click();
      await goto(session);
      await page.getByText(/Changed files?/).first().waitFor();
      await capture('turn-card');
      await showReview();
      for (const [title, name] of [['Git changes', 'working'], ['Branch changes', 'branch'], ['Last turn changes', 'last-turn']]) {
        await source(title);
        if (name === 'branch') await openChangedFile('README.md', 'Committed on feature.');
        else await example();
        await capture(name);
      }
      if (!mobile) {
        for (const style of ['Unified', 'Split']) {
          await panel().getByRole('button', { name: style + ' diff', exact: true }).click(); await capture(style.toLowerCase());
        }
        await panel().getByRole('button', { name: 'Show all lines', exact: true }).click(); await capture('all-lines');
        const filter = panel().getByPlaceholder('Filter files');
        await filter.fill('swift'); await capture('filter'); await filter.fill('');
        if (width === 820) {
          await panel().getByRole('button', { name: 'Toggle file tree', exact: true }).click();
          await panel().getByRole('button', { name: 'Unified diff', exact: true }).click();
        }
      }
      const line = panel().locator('[data-line-type="change-addition"] [data-diff-span], [data-line-type="change-addition"] [data-column-number]').first();
      await line.click();
      const editor = panel().getByRole('textbox').filter({ visible: true }).last();
      await editor.fill('Keep the public name and document the new value.'); await capture('comment-editor');
      if (mobile) await panel().locator('[data-slot="line-comment-action"][data-variant="primary"]').click();
      else await panel().getByRole('button', { name: 'Comment', exact: true }).last().click();
      if (mobile) await page.getByRole('tab', { name: 'Session', exact: true }).click();
      await capture('comment-composer');
      await fetch(mock.url + '/admin/scenario', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'plain-text' }) });
      await page.locator('[data-component=composer-editor]').fill('Please address this comment.');
      await page.locator('[data-component=composer-editor]').press('Enter');
      await api.request('POST', `/api/experimental/session/${session}/wait`);
      await page.getByText('Please address this comment.', { exact: true }).first().waitFor(); await capture('comment-sent');
      await showReview(); await source('Git changes'); await example();
      if (mobile) {
        await page.getByRole('tab', { name: 'More...', exact: true }).click();
        await page.getByRole('dialog', { name: 'More options', exact: true }).getByRole('button', { name: 'Files', exact: true }).click();
      } else { await panel().getByRole('button', { name: 'Open file', exact: true }).first().click(); }
      await page.getByPlaceholder('Filter files').last().waitFor(); await capture('files-tree');
      await page.getByPlaceholder('Filter files').last().fill('Example.swift');
      await page.locator('[data-slot="file-tree-v2-row"][data-path="Sources/Example.swift"]').last().click();
      await page.getByText('let value = 2', { exact: false }).last().waitFor(); await capture('file-view');
      await goto(empty); await showReview(); await source('Last turn changes');
      await page.getByText(mobile ? 'No changes' : 'No file changes yet', { exact: true }).waitFor(); await capture('empty');
      await goto(fixture.noGitSession); await showReview();
      await page.getByRole('button', { name: 'Create Git repository', exact: true }).waitFor(); await capture('no-git');
    } catch (error) {
      await page.screenshot({ path: path.join(output, `review-failure-${mode}-${width}.png`) });
      await writeFile(path.join(output, `review-failure-${mode}-${width}.txt`), (await page.locator('body').innerText()).replaceAll(server.password, '[REDACTED]'));
      throw error;
    } finally { await context.close(); }
  }
}
