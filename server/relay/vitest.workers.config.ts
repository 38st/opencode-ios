import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";
import { BUNDLE_ID, KEY_ID, TEAM_ID, TEST_LIMITS } from "./test/support/fixture.ts";

// The Worker in the local workerd runtime (Miniflare), with D1 and both Durable Objects.
export default defineConfig({
  plugins: [
    cloudflareTest(async ({ inject }) => ({
      main: "./src/worker.ts",
      wrangler: { configPath: "./wrangler.toml" },
      miniflare: {
        bindings: {
          APNS_TEAM_ID: TEAM_ID,
          APNS_KEY_ID: KEY_ID,
          APNS_PRIVATE_KEY: inject<string>("apnsPrivateKey"),
          APNS_SANDBOX_URL: inject<string>("mockURL"),
          APNS_PRODUCTION_URL: inject<string>("mockURL"),
          ALLOWED_BUNDLE_IDS: BUNDLE_ID,
          RELAY_TEST_MODE: "1",
          RELAY_TEST_LIMITS: JSON.stringify(TEST_LIMITS),
          TEST_MIGRATIONS: await readD1Migrations("./migrations"),
        },
      },
    })),
  ],
  test: {
    include: ["test/workers/**/*.test.ts"],
    globalSetup: ["./test/workers/global-setup.ts"],
    setupFiles: ["./test/workers/setup.ts"],
  },
});
