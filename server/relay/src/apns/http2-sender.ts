import http2 from "node:http2";
import type { RelayConfig } from "../config.ts";
import { apnsPath, type ApnsResponse, type ApnsSender } from "./delivery.ts";
import type { ApnsRequest } from "./request.ts";

/** The Node sender: one long-lived HTTP/2 session per APNs host, as Apple recommends. */
export class Http2Sender implements ApnsSender {
  readonly #hosts: RelayConfig["apns"];
  readonly #sessions = new Map<string, http2.ClientHttp2Session>();

  constructor(hosts: RelayConfig["apns"]) {
    this.#hosts = hosts;
  }

  #session(origin: string): http2.ClientHttp2Session {
    const existing = this.#sessions.get(origin);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const session = http2.connect(origin);
    const forget = () => {
      if (this.#sessions.get(origin) === session) this.#sessions.delete(origin);
    };
    session.on("error", forget);
    session.on("close", forget);
    session.on("goaway", forget);
    session.unref();
    this.#sessions.set(origin, session);
    return session;
  }

  send(request: ApnsRequest, providerToken: string): Promise<ApnsResponse> {
    const origin = request.environment === "sandbox" ? this.#hosts.sandboxURL : this.#hosts.productionURL;
    return new Promise((resolve, reject) => {
      const stream = this.#session(origin).request({
        ":method": "POST",
        ":path": apnsPath(request.deviceToken),
        ...request.headers,
        authorization: `bearer ${providerToken}`,
        "content-type": "application/json",
      });
      let status = 0, text = "";
      stream.setEncoding("utf8");
      stream.setTimeout(10_000, () => stream.close(http2.constants.NGHTTP2_CANCEL));
      stream.on("response", (headers) => (status = Number(headers[":status"])));
      stream.on("data", (chunk: string) => (text += chunk));
      stream.on("error", reject);
      stream.on("close", () => {
        if (!status) return reject(new Error("APNs stream closed without a response"));
        let reason: string | undefined;
        try {
          reason = (JSON.parse(text) as { reason?: string }).reason;
        } catch {
          reason = undefined;
        }
        resolve({ status, ...(reason ? { reason } : {}) });
      });
      stream.end(request.body);
    });
  }

  close(): void {
    for (const session of this.#sessions.values()) session.close();
    this.#sessions.clear();
  }
}
