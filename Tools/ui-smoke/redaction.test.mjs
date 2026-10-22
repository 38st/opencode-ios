import assert from 'node:assert/strict';
import test from 'node:test';
import { run } from '../opencode-sandbox/process.mjs';

test('XCTest truncated typing diagnostics cannot reveal credential prefixes', async () => {
  const secret = 'synthetic-credential-for-redaction';
  const lines = [`Type '${secret.slice(0, 18)}...' into "serverPassword" SecureTextField`,
    `Type 'http://localhost/auth...' into "pairingLink" TextField`, secret,
    'New link: http://127.0.0.1:1234/auth/connect/synthetic-one-use-code'];
  const output = await run(process.execPath, ['-e', 'console.log(JSON.parse(process.env.TEST_LINES).join("\\n"))'], {
    env: { ...process.env, TEST_LINES: JSON.stringify(lines), TEST_RUNNER_OPENCODE_UI_PASSWORD: secret },
  });
  assert.ok(!output.includes(secret.slice(0, 18)));
  assert.ok(!output.includes('localhost/auth'));
  assert.ok(!output.includes('synthetic-one-use-code'));
  assert.ok(output.includes('serverPassword'));
  assert.ok(output.includes('[REDACTED]'));
});
