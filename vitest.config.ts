import { defineConfig } from "vitest/config";

/**
 * The Convex sink's behavioural test run (US-T04).
 *
 * `convex-test` drives `convex/`'s functions and HTTP routes **in process**, against no deployment
 * and no network, in the same edge-runtime environment Convex functions actually execute in. That
 * is what makes `POST /logEvent`'s boundary re-checkable: US-T03 shipped it gated only by
 * `npm run typecheck` plus a one-time hand-run transcript, and `tsc` cannot catch a regression in
 * any of the behaviour three review rounds established.
 *
 * This is `convex/`'s toolchain only - `npm run test` here has nothing to do with the iOS suites,
 * which run under `xcodebuild`. The iOS side still carries **no** new third-party package; Lottie
 * remains its only one.
 */
export default defineConfig({
  test: {
    environment: "edge-runtime",
    include: ["convex/**/*.test.ts"],
    server: { deps: { inline: ["convex-test"] } },
  },
});
