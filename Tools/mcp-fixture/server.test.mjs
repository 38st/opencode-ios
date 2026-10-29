import assert from 'node:assert/strict';
import test from 'node:test';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { answer } from './server.mjs';

test('answers the MCP handshake, tools and resources', () => {
  assert.equal(answer({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-06-18' } }).result.serverInfo.name, 'opencode-ios-fixture');
  assert.equal(answer({ jsonrpc: '2.0', method: 'notifications/initialized' }), undefined);
  assert.equal(answer({ jsonrpc: '2.0', id: 2, method: 'tools/list' }).result.tools[0].name, 'echo');
  assert.equal(answer({ jsonrpc: '2.0', id: 3, method: 'resources/list' }).result.resources[0].uri, 'fixture://notes');
  assert.equal(answer({ jsonrpc: '2.0', id: 4, method: 'nope' }).error.code, -32601);
});

test('speaks newline-delimited JSON-RPC over stdio', async () => {
  const child = spawn(process.execPath, [fileURLToPath(new URL('./server.mjs', import.meta.url))], { stdio: ['pipe', 'pipe', 'inherit'] });
  const reply = new Promise(resolve => child.stdout.once('data', data => resolve(JSON.parse(String(data).split('\n')[0]))));
  child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id: 7, method: 'ping' }) + '\n');
  assert.deepEqual(await reply, { jsonrpc: '2.0', id: 7, result: {} });
  child.stdin.end();
  await new Promise(resolve => child.once('exit', resolve));
});
