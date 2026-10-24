// Node entry point (the Fly.io fallback): node src/node.ts
// Reads the same variables as the Worker, plus PORT, HOST, RELAY_DATABASE and TRUST_PROXY
// ("fly" or "forwarded"; see NodeRelayOptions.trustProxy).
import { parseTrustProxy, startNodeRelay } from "./node-server.ts";

const relay = await startNodeRelay({
  env: process.env,
  database: process.env.RELAY_DATABASE ?? "relay.sqlite",
  port: Number(process.env.PORT ?? 8787),
  host: process.env.HOST ?? "0.0.0.0",
  trustProxy: parseTrustProxy(process.env.TRUST_PROXY),
});
console.log(JSON.stringify({ event: "listening", url: relay.url }));
for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.once(signal, () => void relay.close().then(() => process.exit(0)));
}
