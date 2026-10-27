import http from 'node:http';

/** Fault injection at the direct server boundary. Normal traffic, including SSE, is streamed.
 * V2 pending requests are immutable, so a changed request is injected into one fresh GET only.
 */
export async function startRequestProxy(baseURL) {
  const changes = new Set(), rewritten = [], sockets = new Set();
  const server = http.createServer((request, response) => {
    const target = new URL(request.url, baseURL);
    const forwarded = http.request(target, { method: request.method, headers: { ...request.headers, host: target.host } }, incoming => {
      const id = /^\/api\/session\/[^/]+\/permission\/([^/?]+)(?:\?|$)/.exec(request.url)?.[1];
      if (request.method === 'GET' && id && changes.has(id) && incoming.statusCode === 200) {
        const chunks = [];
        incoming.on('data', chunk => chunks.push(chunk));
        incoming.on('end', () => {
          const body = JSON.parse(Buffer.concat(chunks).toString());
          const value = body.data ?? body;
          value.resources = [...(value.resources ?? []), 'changed-after-notification'];
          rewritten.push({ id, at: Date.now() });
          response.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(body));
        });
      } else {
        response.writeHead(incoming.statusCode, incoming.headers); response.flushHeaders(); incoming.pipe(response);
      }
    });
    forwarded.on('error', () => { if (!response.headersSent) response.writeHead(502); response.end(); });
    response.once('close', () => forwarded.destroy());
    request.pipe(forwarded);
  });
  server.on('connection', socket => { sockets.add(socket); socket.once('close', () => sockets.delete(socket)); });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { url: `http://127.0.0.1:${server.address().port}`, changes, rewritten,
    async close() { for (const socket of sockets) socket.destroy(); await new Promise(resolve => server.close(resolve)); } };
}
