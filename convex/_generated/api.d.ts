/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as accounts from "../accounts.js";
import type * as appStore from "../appStore.js";
import type * as appStoreJws from "../appStoreJws.js";
import type * as appStoreNotifications from "../appStoreNotifications.js";
import type * as appleRoots from "../appleRoots.js";
import type * as coach from "../coach.js";
import type * as coachCatalog from "../coachCatalog.js";
import type * as coachEval from "../coachEval.js";
import type * as coachModel from "../coachModel.js";
import type * as coachPrompt from "../coachPrompt.js";
import type * as coachSafety from "../coachSafety.js";
import type * as coachTools from "../coachTools.js";
import type * as crons from "../crons.js";
import type * as entitlements from "../entitlements.js";
import type * as events from "../events.js";
import type * as http from "../http.js";
import type * as ownership from "../ownership.js";
import type * as rateLimit from "../rateLimit.js";
import type * as reconcile from "../reconcile.js";
import type * as sync from "../sync.js";
import type * as webEvents from "../webEvents.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  accounts: typeof accounts;
  appStore: typeof appStore;
  appStoreJws: typeof appStoreJws;
  appStoreNotifications: typeof appStoreNotifications;
  appleRoots: typeof appleRoots;
  coach: typeof coach;
  coachCatalog: typeof coachCatalog;
  coachEval: typeof coachEval;
  coachModel: typeof coachModel;
  coachPrompt: typeof coachPrompt;
  coachSafety: typeof coachSafety;
  coachTools: typeof coachTools;
  crons: typeof crons;
  entitlements: typeof entitlements;
  events: typeof events;
  http: typeof http;
  ownership: typeof ownership;
  rateLimit: typeof rateLimit;
  reconcile: typeof reconcile;
  sync: typeof sync;
  webEvents: typeof webEvents;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {};
