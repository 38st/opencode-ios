import http from 'node:http';
import https from 'node:https';
import { createHash, randomBytes } from 'node:crypto';

// Loopback-only, test-owned proxy. SSE is piped with backpressure, never collected.
export async function startFaultProxy(target, { adminToken = randomBytes(24).toString('hex') } = {}) {
  const upstream = new URL(target);
  let blocked = false, dropPrompts = 0, pauseEvents = false;
  const admissions = [], streams = new Set(), requests = new Set(), sockets = new Set();
  const server = http.createServer(async (request, response) => {
    if (request.url === '/__fault') {
      if (request.headers['x-fault-token'] !== adminToken) { response.writeHead(403).end(); return; }
      try {
        if (request.method === 'POST') {
          const chunks = []; let size = 0;
          for await (const chunk of request) { size += chunk.length; if (size > 4096) throw new Error('Admin body too large'); chunks.push(chunk); }
          const input = JSON.parse(Buffer.concat(chunks).toString());
          if (input.pauseEvents !== undefined) pauseEvents = input.pauseEvents === true;
          if (input.blocked !== undefined) blocked = input.blocked === true;
          if (Number.isInteger(input.dropPrompts) && input.dropPrompts >= 0) dropPrompts = input.dropPrompts;
          if (input.reset === true) admissions.length = 0;
          if (blocked || input.disconnectEvents) for (const stream of streams) stream.destroy();
        }
        response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify({ blocked, dropPrompts, pauseEvents, admissions }));
      } catch { response.writeHead(400).end(); }
      return;
    }
    if (blocked) { request.socket.destroy(); return; }
    const prompt = request.method === 'POST' && /\/api\/session\/[^/]+\/prompt(?:\?|$)/.test(request.url);
    const drop = prompt && dropPrompts > 0;
    if (drop) dropPrompts--;
    const headers = { ...request.headers, host: upstream.host };
    delete headers['x-fault-token'];
    const transport = upstream.protocol === 'https:' ? https : http;
    const forwarded = transport.request(new URL(request.url, upstream), { method: request.method, headers }, incoming => {
      if (drop) {
        // Reading to end ensures the upstream handler completed before losing its response.
        incoming.resume(); incoming.on('end', () => response.destroy()); return;
      }
      response.writeHead(incoming.statusCode, incoming.headers);
      response.flushHeaders();
      if (incoming.headers['content-type']?.includes('text/event-stream')) {
        streams.add(response); response.once('close', () => streams.delete(response));
        incoming.on('data', chunk => {
          if (pauseEvents) return;
          if (!response.write(chunk)) incoming.pause();
        });
        response.on('drain', () => incoming.resume());
        incoming.on('end', () => response.end());
        return;
      }
      incoming.pipe(response);
    });
    requests.add(forwarded); forwarded.once('close', () => requests.delete(forwarded));
    forwarded.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end(); });
    response.once('close', () => forwarded.destroy());
    if (prompt) {
      const chunks = []; let size = 0;
      request.on('data', chunk => { size += chunk.length; if (size <= 32 * 1024 * 1024) chunks.push(chunk); });
      request.on('end', () => {
        const bytes = Buffer.concat(chunks);
        let id; try { id = JSON.parse(bytes).id; } catch { /* Preserve malformed bodies unchanged. */ }
        admissions.push({ id, bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex'), dropped: drop });
      });
    }
    request.pipe(forwarded);
  });
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return {
    url: `http://127.0.0.1:${server.address().port}`, adminToken,
    async close() {
      for (const request of requests) request.destroy();
      for (const socket of sockets) socket.destroy();
      await new Promise(resolve => server.close(resolve));
    },
  };
}
