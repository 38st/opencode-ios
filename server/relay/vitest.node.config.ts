import { defineConfig } from "vitest/config";

// The Node entry point (node:http, node:http2, node:sqlite) and the unit tests.
export default defineConfig({
  test: {
    include: ["test/node/**/*.test.ts"],
  },
});
