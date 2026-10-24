import { PLUGIN_ID } from "../contracts/src/index.ts";
import type { Host } from "./host.ts";
import { definition, handlers } from "./rpc.ts";
import { PushService } from "./service.ts";

/** The opencode V2 plugin (Promise API): `{ id, setup }`, where setup returns the cleanup. */
export default {
  id: PLUGIN_ID,
  async setup(context: Host) {
    const service = new PushService({ host: context });
    await service.start((started) => context.rpc.register(definition, handlers(started)));
    return () => service.stop();
  },
};
