import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';

/** Forward accepted APNs requests byte-for-byte as JSON objects; never decrypt at the bridge. */
export class SimulatorBridge {
  constructor({ apns, bundleID, device, directory, run = promisify(execFile) }) {
    Object.assign(this, { apns, bundleID, device, directory, run });
    this.index = 0; this.deliveries = []; this.pending = Promise.resolve();
  }
  start() { this.timer = setInterval(() => this.pump(), 50); }
  pump() {
    for (; this.index < this.apns.requests.length; this.index++) {
      const request = this.apns.requests[this.index], index = this.index;
      if (request.status !== 200 || request.problems.length) continue;
      if (!request.headers['apns-topic'].startsWith(this.bundleID)) continue;
      this.pending = this.pending.then(async () => {
        await mkdir(this.directory, { recursive: true });
        const file = path.join(this.directory, `${index}.apns`);
        await writeFile(file, JSON.stringify(request.body), { mode: 0o600 });
        const result = { index, type: request.headers['apns-push-type'], acceptedAt: Date.now() };
        try {
          const output = await this.run('xcrun', ['simctl', 'push', this.device, this.bundleID, file]);
          result.output = output.stdout; result.forwardedAt = Date.now();
        } catch (error) { result.error = error.stderr || error.message; }
        this.deliveries.push(result);
        await writeFile(path.join(this.directory, 'deliveries.json'), JSON.stringify(this.deliveries, null, 2));
      });
    }
  }
  async stop() { clearInterval(this.timer); this.pump(); await this.pending; }
}
