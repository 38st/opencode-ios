import http from 'node:http';
import { createHash } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { pathToFileURL } from 'node:url';
import { scenarios, auxiliaryKind, auxiliaryCall } from './scenarios.mjs';

export const scenarioHash = scenario => createHash('sha256').update(JSON.stringify(scenario)).digest('hex');
const usageDefault = { prompt_tokens: 24, completion_tokens: 12, total_tokens: 36, prompt_tokens_details: { cached_tokens: 0 }, completion_tokens_details: { reasoning_tokens: 3 } };

export async function startMock({ port = 0 } = {}) {
  let selected = 'plain-text', script = scenarios[selected], index = 0, serial = 0;
  let consumed = [], unexpected = [];
  const active = new Set();
  const json = (res, status, body) => { res.writeHead(status, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };
  const state = () => ({ scenario: selected, hash: scenarioHash(script), consumed, remaining: script.calls.length - index, unexpected, active: active.size });
  const server = http.createServer(async (req, res) => {
    const controller = new AbortController();
    res.on('close', () => controller.abort());
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/admin/state') return json(res, 200, state());
      const chunks = [];
      let length = 0;
      for await (const chunk of req) {
        length += chunk.length;
        if (length > 8 * 1024 * 1024) return json(res, 413, { error: 'Request too large' });
        chunks.push(chunk);
      }
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks)) : {};
      if (req.method === 'POST' && url.pathname === '/admin/scenario') {
        if (active.size) return json(res, 409, { error: 'Model calls are still active' });
        const next = body.script ?? scenarios[body.name];
        if (!next || !Array.isArray(next.calls)) return json(res, 400, { error: 'Unknown or invalid scenario' });
        selected = body.name ?? 'custom'; script = next; index = 0; consumed = []; unexpected = [];
        return json(res, 200, state());
      }
      if (req.method !== 'POST' || url.pathname !== '/v1/chat/completions') return json(res, 404, { error: 'Unknown route' });
      const kind = auxiliaryKind(body) ?? 'primary';
      const call = kind === 'primary' ? script.calls[index++] : auxiliaryCall(kind);
      if (!call) {
        index--;
        unexpected.push({ kind, model: body.model });
        return json(res, 400, { error: { message: 'Mock scenario exhausted', type: 'invalid_request_error' } });
      }
      const record = { ordinal: ++serial, kind, model: body.model, stream: body.stream === true, scriptIndex: kind === 'primary' ? index - 1 : null, status: 'active', tools: (body.tools ?? []).map(t => t.function?.name) };
      consumed.push(record); active.add(controller);
      try {
        await delay(call.delayMs ?? 0, undefined, { signal: controller.signal });
        if (call.error) {
          if (call.error.retryAfter !== undefined) res.setHeader('retry-after', call.error.retryAfter);
          record.status = call.error.status;
          return json(res, call.error.status, { error: { message: call.error.message, type: call.error.status === 429 ? 'rate_limit_error' : 'api_error', code: String(call.error.status) } });
        }
        const id = `chatcmpl-fixture-${record.ordinal}`;
        const base = { id, object: 'chat.completion.chunk', created: 1_700_000_000, model: body.model };
        const finish = call.finishReason ?? (call.tools?.length ? 'tool_calls' : 'stop');
        const usage = { ...usageDefault, ...call.usage };
        if (!body.stream) {
          record.status = 'completed';
          return json(res, 200, { ...base, object: 'chat.completion', choices: [{ index: 0, message: { role: 'assistant', content: (call.deltas ?? []).map(d => d.text ?? '').join(''), reasoning_content: (call.deltas ?? []).map(d => d.reasoning ?? '').join(''), ...(call.tools?.length ? { tool_calls: call.tools.map((t, i) => ({ id: `call_${record.ordinal}_${i}`, type: 'function', function: { name: t.name, arguments: JSON.stringify(t.arguments) } })) } : {}) }, finish_reason: finish }], usage });
        }
        res.writeHead(200, { 'content-type': 'text/event-stream', 'cache-control': 'no-cache', connection: 'keep-alive' });
        const send = (delta, finish_reason = null) => res.write(`data: ${JSON.stringify({ ...base, choices: [{ index: 0, delta, finish_reason }] })}\n\n`);
        send({ role: 'assistant', content: '' });
        for (const delta of call.deltas ?? []) {
          await delay(delta.delayMs ?? 5, undefined, { signal: controller.signal });
          send({ ...(delta.text !== undefined ? { content: delta.text } : {}), ...(delta.reasoning !== undefined ? { reasoning_content: delta.reasoning } : {}) });
        }
        if (call.waitForAbort) {
          await new Promise((_, reject) => {
            if (controller.signal.aborted) reject(controller.signal.reason);
            else controller.signal.addEventListener('abort', () => reject(controller.signal.reason), { once: true });
          });
        }
        for (const [i, tool] of (call.tools ?? []).entries()) {
          const parts = tool.argumentDeltas ?? [JSON.stringify(tool.arguments).slice(0, 8), JSON.stringify(tool.arguments).slice(8)];
          send({ tool_calls: [{ index: i, id: `call_${record.ordinal}_${i}`, type: 'function', function: { name: tool.name, arguments: '' } }] });
          for (const part of parts) {
            await delay(tool.delayMs ?? 5, undefined, { signal: controller.signal });
            send({ tool_calls: [{ index: i, function: { arguments: part } }] });
          }
        }
        send({}, finish);
        res.write(`data: ${JSON.stringify({ ...base, choices: [], usage })}\n\n`);
        res.end('data: [DONE]\n\n');
        record.status = 'completed';
      } catch (error) {
        record.status = controller.signal.aborted ? 'cancelled' : 'failed';
        if (!controller.signal.aborted) throw error;
      } finally { active.delete(controller); }
    } catch (error) {
      if (!res.headersSent) json(res, 400, { error: { message: error.message } });
      else res.destroy(error);
    }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    state,
    async close() {
      for (const controller of active) controller.abort();
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    },
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const mock = await startMock({ port: Number(process.env.PORT ?? 0) });
  console.log(mock.url);
  for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await mock.close(); process.exit(0); });
}
