import http from 'node:http';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { basic } from '../opencode-sandbox/index.mjs';

export async function until(predicate, label, timeout = 20000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const value = await predicate();
    if (value) return value;
    await delay(20);
  }
  throw new Error(`Timed out: ${label}`);
}

export class Capture {
  constructor(sandbox) {
    this.sandbox = sandbox;
    this.rest = [];
    this.frames = [];
    this.events = [];
    this.chunks = [];
    this.comments = [];
    this.secrets = new Set([sandbox.password, basic(sandbox.password), basic(sandbox.password).slice(6)]);
  }
  redact(value) {
    if (typeof value === 'string') {
      for (const secret of this.secrets) value = value.replaceAll(secret, '[REDACTED]');
      return value.replace(/([?&](?:auth_token|ticket)=)[^&\s]+/g, '$1[REDACTED]').replace(/(\/auth\/connect\/)(?![:{])[^/?\s]+/g, '$1[REDACTED]');
    }
    if (Array.isArray(value)) return value.map(item => this.redact(item));
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, typeof item === 'string' && /^(authorization|proxy-authorization|set-cookie|cookie|token|password|ticket|apiKey)$/i.test(key) ? '[REDACTED]' : this.redact(item)]));
    return value;
  }
  addSecret(secret) {
    this.secrets.add(secret); this.secrets.add(basic(secret)); this.secrets.add(basic(secret).slice(6));
  }
  async request(method, path, body, { auth = this.sandbox.password, status, headers: extra = {} } = {}) {
    const headers = { accept: 'application/json', 'accept-encoding': 'identity', ...(auth ? { authorization: basic(auth) } : {}), ...(body !== undefined ? { 'content-type': 'application/json' } : {}), ...extra };
    const response = await fetch(this.sandbox.baseURL + path, { method, headers, ...(body !== undefined ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(60000), redirect: 'manual' });
    const bytes = Buffer.from(await response.arrayBuffer());
    const raw = bytes.toString('utf8');
    let decoded = null, format = 'empty';
    if (bytes.length) {
      if (response.headers.get('content-type')?.includes('json')) { decoded = JSON.parse(raw); format = 'json'; }
      else { decoded = raw; format = 'text'; }
    }
    if (decoded?.token) this.addSecret(decoded.token);
    if (decoded?.code && path === '/api/pair') this.addSecret(decoded.code);
    if (decoded?.data?.ticket) this.addSecret(decoded.data.ticket);
    this.rest.push(this.redact({ request: { method, path, headers, body: body ?? null }, response: { status: response.status, headers: Object.fromEntries(response.headers), body: decoded, bodyFormat: format } }));
    if (status !== undefined) assert.equal(response.status, status, `${method} ${path}: ${JSON.stringify(decoded)}`);
    else assert.ok(response.ok, `${method} ${path}: ${response.status} ${JSON.stringify(decoded)}`);
    return decoded;
  }
  async openSSE() {
    let pending = '', failure;
    const decoder = new TextDecoder();
    const ready = new Promise((resolve, reject) => {
      this.sse = http.get(this.sandbox.baseURL + '/api/event', { headers: { authorization: basic(this.sandbox.password), accept: 'text/event-stream', 'accept-encoding': 'identity' } }, response => {
        if (response.statusCode !== 200) { reject(new Error(`SSE status ${response.statusCode}`)); response.destroy(); return; }
        this.sseResponse = response;
        response.on('data', bytes => {
          // Keep the HTTP entity bytes, without parsing/re-encoding or normalizing newlines.
          this.chunks.push(Buffer.from(bytes));
          pending += decoder.decode(bytes, { stream: true });
          let end;
          while ((end = pending.indexOf('\n\n')) !== -1) {
            const frame = pending.slice(0, end); pending = pending.slice(end + 2);
            const lines = frame.split('\n');
            this.comments.push(...lines.filter(line => line.startsWith(':')));
            const data = lines.filter(line => line.startsWith('data:')).map(line => line.slice(5).replace(/^ /, '')).join('\n');
            if (data) {
              try { this.events.push(JSON.parse(data)); resolve(); }
              catch (error) { failure = error; reject(error); }
            }
          }
        });
        response.on('error', error => { if (!this.closing) { failure = error; reject(error); } });
        response.on('end', () => { if (!this.closing) failure = new Error('SSE ended unexpectedly'); });
      });
      this.sse.on('error', error => { if (!this.closing) { failure = error; reject(error); } });
    });
    this.sseFailure = () => failure;
    let timer;
    try { await Promise.race([ready, new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('SSE first-frame timeout')), 10000); })]); }
    catch (error) { await this.closeSSE(); throw error; }
    finally { clearTimeout(timer); }
    assert.equal(this.events[0].type, 'server.connected');
  }
  event(type, predicate = () => true, timeout = 20000) {
    return until(() => {
      if (this.sseFailure?.()) throw this.sseFailure();
      return this.events.find(event => event.type === type && predicate(event));
    }, type, timeout);
  }
  async closeSSE() {
    this.closing = true;
    this.sseResponse?.destroy(); this.sse?.destroy();
    const bytes = Buffer.concat(this.chunks);
    for (const secret of this.secrets) assert.ok(!bytes.includes(secret), 'Secret found in raw SSE; refusing to save');
    return bytes;
  }
}
