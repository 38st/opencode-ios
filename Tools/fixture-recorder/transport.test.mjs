import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Capture } from './transport.mjs';
import { basic } from '../opencode-sandbox/index.mjs';

test('redaction covers credentials, pairing tokens, cookies and URL carriers', () => {
  const capture = new Capture({ password: 'per-run-password' });
  capture.addSecret('123.signature');
  const result = capture.redact({ request: { path: '/auth/connect/pair-code', headers: { authorization: basic('per-run-password') } }, response: { token: '123.signature', headers: { 'set-cookie': 'session=secret' } }, link: 'http://localhost/api?auth_token=abc&ticket=xyz', embedded: 'prefix 123.signature suffix' });
  assert.equal(result.request.path, '/auth/connect/[REDACTED]');
  assert.equal(result.request.headers.authorization, '[REDACTED]');
  assert.equal(result.response.token, '[REDACTED]');
  assert.equal(result.response.headers['set-cookie'], '[REDACTED]');
  assert.equal(result.link, 'http://localhost/api?auth_token=[REDACTED]&ticket=[REDACTED]');
  assert.equal(result.embedded, 'prefix [REDACTED] suffix');
  assert.deepEqual(capture.redact({ properties: { token: { type: 'string' } }, code: 'invalid_request' }), { properties: { token: { type: 'string' } }, code: 'invalid_request' });
  assert.equal(capture.redact('/auth/connect/:code and /auth/connect/{code}'), '/auth/connect/:code and /auth/connect/{code}');
});

test('raw SSE is byte-preserved, and a leaked secret prevents publishing', async () => {
  const capture = new Capture({ password: 'per-run-password' });
  const bytes = Buffer.from('data: {"text":"café 🐈"}\n\n: heartbeat\n\n');
  capture.chunks.push(bytes.subarray(0, 21), bytes.subarray(21));
  assert.deepEqual(await capture.closeSSE(), bytes);
  capture.chunks.push(Buffer.from('per-run-password'));
  await assert.rejects(capture.closeSSE(), /Secret found/);
});
