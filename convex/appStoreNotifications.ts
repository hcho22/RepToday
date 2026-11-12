import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";
import { appStoreConfig, AppStoreRefusalError, verifiedNotification } from "./appStore";
import { notificationArgs } from "./entitlements";

/**
 * `POST /appStore/notifications` (M4, US-CA02): the App Store Server Notifications V2 endpoint that
 * keeps each account's Premium entitlement current. Registered in `convex/http.ts`; the URL entered
 * in App Store Connect is this deployment's `.convex.site` origin plus that path.
 *
 * Apple posts `{ "signedPayload": "<JWS>" }` and retries anything that is not a 2xx. So:
 *
 * - **200** when the notification verified and was applied, was a retry already applied, or carried
 *   no subscription transaction (a `TEST` notification);
 * - **400** when it is not Apple-signed data for this app in an accepted environment - a forgery or a
 *   misrouted notification gains nothing from a retry;
 * - **503** when this deployment accepts no App Store data (`APPSTORE_ENVIRONMENTS` unset), and **500**
 *   when storing failed, both of which a retry can fix.
 *
 * No response body echoes the payload.
 */

/** Apple's notifications are a few kilobytes; anything far larger is refused before parsing. */
export const MAX_NOTIFICATION_BODY_BYTES = 64 * 1024;

const respond = (status: number, outcome: string) =>
  new Response(JSON.stringify({ outcome }), { status, headers: { "Content-Type": "application/json" } });

export const appStoreNotificationHandler = httpAction(async (ctx, request) => {
  const config = appStoreConfig();
  if (config === null) {
    return respond(503, "unavailable");
  }
  const raw = await request.arrayBuffer();
  if (raw.byteLength === 0 || raw.byteLength > MAX_NOTIFICATION_BODY_BYTES) {
    return respond(400, "malformed");
  }
  let signedPayload: unknown;
  try {
    signedPayload = (JSON.parse(new TextDecoder().decode(raw)) as Record<string, unknown> | null)?.signedPayload;
  } catch {
    return respond(400, "malformed");
  }
  if (typeof signedPayload !== "string") {
    return respond(400, "malformed");
  }
  let args;
  try {
    args = notificationArgs(await verifiedNotification(signedPayload, config, Date.now()));
  } catch (error) {
    if (error instanceof AppStoreRefusalError) {
      return respond(400, error.refusal);
    }
    console.error("App Store notification verification failed unexpectedly");
    return respond(500, "error");
  }
  try {
    const outcome = await ctx.runMutation(internal.entitlements.applyNotification, args);
    return respond(200, outcome);
  } catch {
    console.error("App Store notification could not be stored");
    return respond(500, "error");
  }
});
