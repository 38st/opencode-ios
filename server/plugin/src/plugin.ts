import { PLUGIN_ID } from "../contracts/src/index.ts";
import { directFromOptions } from "./direct.ts";
import type { Host } from "./host.ts";
import { definition, handlers } from "./rpc.ts";
import { PushService } from "./service.ts";

/** The opencode V2 plugin (Promise API): `{ id, setup }`, where setup returns the cleanup. */
export default {
  id: PLUGIN_ID,
  async setup(context: Host) {
    // Direct mode is optional: a missing or invalid `apns` option leaves it off and relay devices unaffected.
    const direct = await directFromOptions(context.options, (message) => console.warn(`[mobilepush] ${message}`));
    const service = new PushService({ host: context, ...(direct ? { direct: direct.sender } : {}) });
    try {
      await service.start((started) => context.rpc.register(definition, handlers(started)));
    } catch (error) {
      direct?.release();
      throw error;
    }
    return async () => {
      await service.stop();
      direct?.release();
    };
  },
};
