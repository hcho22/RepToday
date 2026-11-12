import { COACH_TOOLS, type ToolCall } from "./coachTools";

/**
 * The one call the Coach makes to its model per turn (M4, US-CA01, ADR-0017).
 *
 * The provider is unchanged from before M4: OpenAI, through the Responses API, now from a Convex
 * action instead of the Cloudflare Worker. One request per turn, `store: false` (OpenAI keeps no
 * conversation; the memory is Rep Today's own `coachMemory` table), with the Coach's tools attached.
 * The model answers with text and, optionally, tool calls; the calls are never executed here - they
 * become proposals the user confirms in the app (`convex/coachTools.ts`). Because a proposal's result
 * is the user's later tap, not a server computation, a turn never needs a second model round trip.
 *
 * Model choice (Open Question 3, decided in M4 and recorded in ADR-0017): `gpt-5.6-luna` with low
 * reasoning effort - the provider's fast, low-cost tier, which supports strict function calling and
 * structured arguments. `COACH_MODEL` on the deployment overrides it for an evaluation run without a
 * code change.
 *
 * `OPENAI_API_KEY` is a deployment environment variable; without it the Coach answers
 * `coach_unavailable` and makes no call.
 */

declare const process: { readonly env: Readonly<Record<string, string | undefined>> };

export const DEFAULT_COACH_MODEL = "gpt-5.6-luna";
export const COACH_REASONING_EFFORT = "low";
/** The output ceiling: a reply plus one Custom Workout's arguments fit well inside it. */
export const COACH_MAX_OUTPUT_TOKENS = 2400;
/** How long the model call may take; the app's request allows 60 seconds in all. */
export const COACH_MODEL_TIMEOUT_MS = 40_000;
const OPENAI_RESPONSES_URL = "https://api.openai.com/v1/responses";

export type ModelInputMessage = { role: "developer" | "user" | "assistant"; content: string };

export type ModelRequest = {
  instructions: string;
  input: ModelInputMessage[];
  /** A one-way hash of the account, for the provider's abuse monitoring. */
  safetyIdentifier: string;
};

export type ModelOutcome =
  | { kind: "reply"; text: string; toolCalls: ToolCall[] }
  | { kind: "refusal" }
  | { kind: "unavailable" };

/** Whether this deployment can reach a model at all. */
export function coachModelConfigured(env: Readonly<Record<string, string | undefined>> = process.env): boolean {
  return env.COACH_MODEL_STUB === "1" || (env.OPENAI_API_KEY ?? "").length > 0;
}

/** Runs one Coach turn on the configured model. */
export async function runCoachModel(request: ModelRequest): Promise<ModelOutcome> {
  if (process.env.COACH_MODEL_STUB === "1") {
    return stubCoachModel(request);
  }
  const key = process.env.OPENAI_API_KEY;
  if (key === undefined || key.length === 0) {
    return { kind: "unavailable" };
  }
  let response: Response;
  try {
    response = await fetch(OPENAI_RESPONSES_URL, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${key}` },
      body: JSON.stringify(openAIRequestBody(request, process.env.COACH_MODEL || DEFAULT_COACH_MODEL)),
      signal: AbortSignal.timeout(COACH_MODEL_TIMEOUT_MS),
    });
  } catch {
    return { kind: "unavailable" };
  }
  if (!response.ok) {
    return { kind: "unavailable" };
  }
  try {
    return parseOpenAIResponse(await response.json());
  } catch {
    return { kind: "unavailable" };
  }
}

/** The Responses API request for one turn. */
export function openAIRequestBody(request: ModelRequest, model: string) {
  return {
    model,
    instructions: request.instructions,
    input: request.input.map((message) => ({ role: message.role, content: message.content })),
    tools: COACH_TOOLS,
    tool_choice: "auto",
    parallel_tool_calls: true,
    reasoning: { effort: COACH_REASONING_EFFORT },
    max_output_tokens: COACH_MAX_OUTPUT_TOKENS,
    store: false,
    safety_identifier: request.safetyIdentifier,
  };
}

/** Reads a Responses API answer: its text, its function calls, or a refusal. */
export function parseOpenAIResponse(body: unknown): ModelOutcome {
  const response = body as Record<string, unknown> | null;
  if (response === null || typeof response !== "object" || response.error != null) {
    return { kind: "unavailable" };
  }
  const incomplete = (response.incomplete_details as Record<string, unknown> | null | undefined)?.reason;
  if (incomplete === "content_filter") {
    return { kind: "refusal" };
  }
  if (response.status !== "completed" && !(response.status === "incomplete" && incomplete === "max_output_tokens")) {
    return { kind: "unavailable" };
  }
  const output = Array.isArray(response.output) ? (response.output as Record<string, unknown>[]) : [];
  const toolCalls: ToolCall[] = [];
  const texts: string[] = [];
  for (const item of output) {
    if (item?.type === "function_call" && typeof item.name === "string" && typeof item.arguments === "string") {
      toolCalls.push({ name: item.name, arguments: item.arguments });
    }
    if (item?.type === "message" && Array.isArray(item.content)) {
      for (const block of item.content as Record<string, unknown>[]) {
        if (block?.type === "refusal") {
          return { kind: "refusal" };
        }
        if (block?.type === "output_text" && typeof block.text === "string") {
          texts.push(block.text);
        }
      }
    }
  }
  return { kind: "reply", text: texts.join("").trim(), toolCalls };
}

/**
 * A scripted stand-in for the model, on only where `COACH_MODEL_STUB` is `1` (a development deployment
 * waiting for its provider key, or a Simulator walk that must not spend model calls). It recognises a
 * few plain requests and answers with the matching tool call, so every tool's card can be exercised end
 * to end; it never runs on production, which never sets the flag.
 */
export function stubCoachModel(request: ModelRequest): ModelOutcome {
  const last = [...request.input].reverse().find((message) => message.role === "user")?.content.toLowerCase() ?? "";
  const call = (name: string, args: unknown): ToolCall => ({ name, arguments: JSON.stringify(args) });
  const firstMovement = /- Today's session \(id: name\): ([a-z0-9_]+):/.exec(request.input.find((message) => message.role === "developer")?.content ?? "")?.[1];
  if (/\b(ran|run|swim|swam|hike|hiked|bike|biked|rowed|climb|climbed)\b/.test(last)) {
    const type = /\b(swim|swam)\b/.test(last) ? "swim" : /\b(hike|hiked)\b/.test(last) ? "hike" : /\b(bike|biked)\b/.test(last) ? "bike" : "run";
    return { kind: "reply", text: `Nice work getting that ${type} in. I've put it below for you to log.`, toolCalls: [call("log_outside_activity", { type, minutes: 30, distance_km: null, day: "today" })] };
  }
  if (/\btrain anyway\b/.test(last)) {
    return { kind: "reply", text: "You can train today instead of resting. Confirm below if you want today's session.", toolCalls: [call("set_rest_choice", { choice: "train_anyway" })] };
  }
  if (/\brest\b/.test(last)) {
    return { kind: "reply", text: "Resting today is a fine call. Confirm below and today becomes a rest day.", toolCalls: [call("set_rest_choice", { choice: "rest_today" })] };
  }
  if (/\b(shorter|less time|only have|minutes)\b/.test(last)) {
    const minutes = Number(/\b(5|10|15|20|30|45|60)\b/.exec(last)?.[1] ?? 10);
    return { kind: "reply", text: `A ${minutes}-minute session still counts. Confirm below to change today's length.`, toolCalls: [call("change_today_length", { minutes })] };
  }
  if (/\bswap\b/.test(last) && firstMovement !== undefined) {
    return { kind: "reply", text: "Rep Today can swap that for the closest alternative. Confirm below.", toolCalls: [call("swap_movement", { movement_id: firstMovement })] };
  }
  if (/\bfocus\b/.test(last)) {
    return { kind: "reply", text: "Here are the Focus Areas I'd set. Confirm below.", toolCalls: [call("set_focus_areas", { areas: ["chest", "abs"] })] };
  }
  if (/\bremind\b/.test(last)) {
    return { kind: "reply", text: "A reminder can help you show up. Confirm the time below.", toolCalls: [call("schedule_reminder", { time: "07:30", days: ["mon", "wed", "fri"] })] };
  }
  if (/\bworkout\b/.test(last)) {
    return {
      kind: "reply",
      text: "Here's a short workout built around your recent sessions. Look it over, edit anything, then accept it to play.",
      toolCalls: [
        call("propose_custom_workout", {
          title: "Desk Reset",
          note: "A short full-body circuit to undo a long day of sitting.",
          steps: [
            { name: "Incline Push-Up", catalog_id: "push_incline", sets: 3, reps: 10, seconds: null, per_side: false, rest_seconds: 30 },
            { name: "Bodyweight Squat", catalog_id: "squat_bodyweight", sets: 3, reps: 15, seconds: null, per_side: false, rest_seconds: 30 },
            { name: "Doorway Chest Opener", catalog_id: null, sets: 2, reps: null, seconds: 30, per_side: false, rest_seconds: 15 },
          ],
        }),
      ],
    };
  }
  return { kind: "reply", text: "I'm here to help with your training. Ask me about today's session, a movement, or a workout that fits your time.", toolCalls: [] };
}
