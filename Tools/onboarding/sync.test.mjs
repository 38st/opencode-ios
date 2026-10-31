import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { constants, render } from './sync.mjs';

const page = await readFile(new URL('../../web/index.html', import.meta.url), 'utf8');

test('the onboarding page shows the current constants', async () => {
  const values = await constants();
  assert.equal(render(page, values), page, 'run node Tools/onboarding/sync.mjs');
  assert.ok(page.includes(`<code data-constant="plugin-install">${values['plugin-install']}</code>`));
});

test('rendering replaces every marked constant and the title', () => {
  const output = render(page, { 'app-name': 'Example & Co', 'plugin-install': 'opencode plugin add @x/y', 'minimum-version': '9.9.9' });
  assert.match(output, /<title>Pair your phone · Example &amp; Co<\/title>/);
  assert.ok(!output.includes('>Opencode<'));
  assert.match(output, /data-constant="minimum-version">9\.9\.9</);
  assert.throws(() => render('<b data-constant="nope">x</b>', {}), /Unknown constant/);
});

test('the page is self-contained', () => {
  assert.doesNotMatch(page, /<(script|link|img)[^>]+(src|href)=/i);
  assert.doesNotMatch(page, /https?:\/\//);
});
