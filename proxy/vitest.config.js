import { defineConfig } from "vitest/config";

/**
 * The proxy's behavioural test run (US-AC01).
 *
 * The Worker is a single default export whose `fetch(request, env)` we can drive directly in Node -
 * every global it uses (fetch/Request/Response/URL/TextEncoder/AbortSignal) exists in Node 20, so the
 * suite needs no deployment, no network, and no Wrangler runtime. The one upstream call (to Anthropic)
 * is stubbed on `globalThis.fetch`, which lets the tests prove the boundary: a valid request makes
 * exactly one upstream call and returns a reply; an oversized/invalid request is rejected *before*
 * that call; nothing is logged or persisted.
 */
export default defineConfig({
  test: {
    include: ["test/**/*.test.js"],
    environment: "node",
  },
});
