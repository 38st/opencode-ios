// A tiny MCP server over stdio for sandbox tests: one tool and one resource, no dependencies.
// Messages are newline-delimited JSON-RPC 2.0 (the MCP stdio transport).
import { createInterface } from 'node:readline';
import { pathToFileURL } from 'node:url';

export const fixtureResource = { uri: 'fixture://notes', name: 'fixture-notes', mimeType: 'text/plain', description: 'Sandbox fixture notes' };

export function answer(message) {
  const { id, method, params } = message;
  if (id === undefined || id === null) return undefined;
  const result = value => ({ jsonrpc: '2.0', id, result: value });
  switch (method) {
    case 'initialize':
      return result({ protocolVersion: params?.protocolVersion ?? '2025-06-18', capabilities: { tools: {}, resources: {} },
        serverInfo: { name: 'opencode-ios-fixture', version: '1.0.0' } });
    case 'ping': return result({});
    case 'tools/list':
      return result({ tools: [{ name: 'echo', description: 'Returns its input', inputSchema: { type: 'object', properties: { text: { type: 'string' } }, required: ['text'] } }] });
    case 'tools/call':
      return result({ content: [{ type: 'text', text: String(params?.arguments?.text ?? '') }] });
    case 'resources/list': return result({ resources: [fixtureResource] });
    case 'resources/templates/list': return result({ resourceTemplates: [] });
    case 'resources/read':
      return result({ contents: [{ uri: params?.uri ?? fixtureResource.uri, mimeType: 'text/plain', text: 'Fixture notes for the sandbox.\n' }] });
    case 'prompts/list': return result({ prompts: [] });
    default: return { jsonrpc: '2.0', id, error: { code: -32601, message: `Method not found: ${method}` } };
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const lines = createInterface({ input: process.stdin });
  lines.on('line', line => {
    if (!line.trim()) return;
    let message;
    try { message = JSON.parse(line); } catch { return; }
    const reply = answer(message);
    if (reply) process.stdout.write(JSON.stringify(reply) + '\n');
  });
  lines.on('close', () => process.exit(0));
}
