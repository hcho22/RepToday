/**
 * Clerk is the deployment's auth provider (M3, ADR-0016).
 *
 * Convex verifies the Clerk session token a client sends against this issuer, and every account
 * function reads the caller from that verified identity (`convex/ownership.ts`). `applicationID` is
 * the audience Clerk's Convex integration stamps on its session tokens.
 *
 * `CLERK_FRONTEND_API_URL` is the Clerk instance's Frontend API URL, set per deployment with
 * `npx convex env set` (a development instance on the dev deployment, the production instance on
 * production). It is an issuer URL, not a secret. A deployment without it refuses the push, so no
 * deployment can run the account functions without an issuer to check tokens against.
 *
 * The telemetry routes (`convex/http.ts`) do not use this; they stay anonymous.
 */
declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

export default {
  providers: [
    {
      domain: process.env.CLERK_FRONTEND_API_URL!,
      applicationID: "convex",
    },
  ],
};
